import 'dart:typed_data';

import 'package:bluey/bluey.dart';
import 'package:bluey/src/lifecycle.dart' as lifecycle;
import 'package:bluey/src/shared/device_id_coercion.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';
import '../fakes/test_helpers.dart';

/// Tests for `Bluey.watchPeer` — the streaming convenience over
/// `tryUpgrade` + `connection.servicesChanges`. Motivated by a real-device
/// observation where Android connected to a freshly-launched iOS server
/// and the Bluey lifecycle service wasn't visible in the central's stale
/// GATT cache; iOS pushed Service Changed shortly after, but by then the
/// one-shot `tryUpgrade` had already resolved null. `watchPeer` retries on
/// each `servicesChanges` emission until upgrade succeeds, then completes.
void main() {
  late FakeBlueyPlatform fakePlatform;
  late Bluey bluey;

  setUp(() {
    fakePlatform = FakeBlueyPlatform();
    platform.BlueyPlatform.instance = fakePlatform;
    bluey = Bluey(localIdentity: TestServerIds.localIdentity);
  });

  tearDown(() async {
    await bluey.dispose();
  });

  Device deviceFromAddress(String address, {String? name}) {
    return Device(id: deviceIdToUuid(address), address: address, name: name);
  }

  // Build a control-service tree that mirrors what `simulateBlueyServer`
  // installs initially, so we can hand it to
  // `simulateServiceChange(newServices: ...)` to model a server that
  // registers its lifecycle service after the central has already
  // discovered an empty-of-bluey-services tree.
  platform.PlatformService controlServiceTree() => platform.PlatformService(
    uuid: lifecycle.controlServiceUuid,
    isPrimary: true,
    characteristics: const [
      platform.PlatformCharacteristic(
        uuid: 'b1e70002-0000-1000-8000-00805f9b34fb',
        properties: platform.PlatformCharacteristicProperties(
          canRead: false,
          canWrite: true,
          canWriteWithoutResponse: false,
          canNotify: false,
          canIndicate: false,
        ),
        descriptors: [],
        handle: 0,
      ),
      platform.PlatformCharacteristic(
        uuid: 'b1e70003-0000-1000-8000-00805f9b34fb',
        properties: platform.PlatformCharacteristicProperties(
          canRead: true,
          canWrite: false,
          canWriteWithoutResponse: false,
          canNotify: false,
          canIndicate: false,
        ),
        descriptors: [],
        handle: 0,
      ),
      platform.PlatformCharacteristic(
        uuid: 'b1e70004-0000-1000-8000-00805f9b34fb',
        properties: platform.PlatformCharacteristicProperties(
          canRead: true,
          canWrite: false,
          canWriteWithoutResponse: false,
          canNotify: false,
          canIndicate: false,
        ),
        descriptors: [],
        handle: 0,
      ),
    ],
    includedServices: [],
  );

  Map<String, Uint8List> controlServiceCharValues(ServerId id) => {
    'b1e70003-0000-1000-8000-00805f9b34fb': lifecycle.encodeInterval(
      const Duration(seconds: 10),
    ),
    'b1e70004-0000-1000-8000-00805f9b34fb': lifecycle.lifecycleCodec
        .encodeAdvertisedIdentity(id),
  };

  group('Bluey.watchPeer', () {
    test('yields PeerConnection and completes when the device is already '
        'a Bluey peer at subscription time', () async {
      final id = ServerId.generate();
      const address = 'AA:BB:CC:DD:EE:01';
      fakePlatform.simulateBlueyServer(address: address, serverId: id);

      final conn = await bluey.connect(deviceFromAddress(address));

      final emissions = <PeerConnection?>[];
      // forEach completes only when the stream is done — proving the
      // contract that watchPeer terminates after the first non-null yield.
      await bluey.watchPeer(conn).forEach(emissions.add);

      expect(emissions, hasLength(1));
      expect(emissions.single, isNotNull);
      expect(emissions.single!.serverId, equals(id));

      await conn.disconnect();
    });

    test('yields null then PeerConnection when the control service appears '
        'via Service Changed (the stale-GATT-cache case)', () async {
      final id = ServerId.generate();
      const address = 'AA:BB:CC:DD:EE:02';
      // Initially: peripheral has no Bluey services (mirrors what a
      // central with a stale GATT cache sees on a server that hasn't
      // yet finished registering).
      fakePlatform.simulatePeripheral(id: address, name: 'Stale Cache');

      final conn = await bluey.connect(deviceFromAddress(address));

      final emissions = <PeerConnection?>[];
      bool completed = false;
      final sub = bluey
          .watchPeer(conn)
          .listen(emissions.add, onDone: () => completed = true);
      addTearDown(sub.cancel);

      // Initial tryUpgrade resolves null.
      await pumpEventQueue();
      expect(emissions, equals([null]));
      expect(completed, isFalse);

      // Server registers its lifecycle service; Service Changed fires.
      fakePlatform.simulateServiceChange(
        address,
        newServices: [controlServiceTree()],
        newCharacteristicValues: controlServiceCharValues(id),
      );
      await pumpEventQueue();

      expect(emissions, hasLength(2));
      expect(emissions[1], isNotNull);
      expect(emissions[1]!.serverId, equals(id));
      expect(
        completed,
        isTrue,
        reason: 'stream completes after first non-null peer emission',
      );

      await conn.disconnect();
    });

    test('subsequent service changes do not re-emit after a successful '
        'upgrade — the stream is already complete', () async {
      final id = ServerId.generate();
      const address = 'AA:BB:CC:DD:EE:03';
      fakePlatform.simulateBlueyServer(address: address, serverId: id);

      final conn = await bluey.connect(deviceFromAddress(address));

      final emissions = <PeerConnection?>[];
      bool completed = false;
      final sub = bluey
          .watchPeer(conn)
          .listen(emissions.add, onDone: () => completed = true);
      addTearDown(sub.cancel);

      await pumpEventQueue();
      expect(completed, isTrue);
      expect(emissions, hasLength(1));

      // Service Changed after completion must not produce a new emission.
      fakePlatform.simulateServiceChange(address);
      await pumpEventQueue();
      expect(emissions, hasLength(1));

      await conn.disconnect();
    });

    test('retries on every servicesChanges until upgrade succeeds — peer '
        'detected on a late service change is still surfaced', () async {
      final id = ServerId.generate();
      const address = 'AA:BB:CC:DD:EE:04';
      fakePlatform.simulatePeripheral(id: address, name: 'Late Bloomer');

      final conn = await bluey.connect(deviceFromAddress(address));

      final emissions = <PeerConnection?>[];
      final sub = bluey.watchPeer(conn).listen(emissions.add);
      addTearDown(sub.cancel);

      await pumpEventQueue();
      expect(emissions, equals([null]));

      // First Service Changed still has no control service.
      fakePlatform.simulateServiceChange(address);
      await pumpEventQueue();
      expect(emissions, equals([null, null]));

      // Second Service Changed adds the control service.
      fakePlatform.simulateServiceChange(
        address,
        newServices: [controlServiceTree()],
        newCharacteristicValues: controlServiceCharValues(id),
      );
      await pumpEventQueue();

      expect(emissions, hasLength(3));
      expect(emissions[2], isNotNull);
      expect(emissions[2]!.serverId, equals(id));

      await conn.disconnect();
    });

    test('stream completes when the underlying connection disconnects '
        'before any peer is detected', () async {
      const address = 'AA:BB:CC:DD:EE:05';
      fakePlatform.simulatePeripheral(id: address, name: 'Plain Device');

      final conn = await bluey.connect(deviceFromAddress(address));

      bool completed = false;
      final sub = bluey
          .watchPeer(conn)
          .listen((_) {}, onDone: () => completed = true);
      addTearDown(sub.cancel);

      await pumpEventQueue();
      expect(completed, isFalse, reason: 'still waiting on servicesChanges');

      await conn.disconnect();
      await pumpEventQueue();

      expect(
        completed,
        isTrue,
        reason:
            'stream must complete when connection closes so '
            'subscribers do not leak',
      );
    });
  });
}
