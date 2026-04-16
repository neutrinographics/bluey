import 'dart:typed_data';

import 'package:bluey/bluey.dart';
import 'package:bluey/src/lifecycle.dart';
import 'package:bluey/src/peer/bluey_peer.dart';
import 'package:bluey/src/peer/server_id.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';

String _simulateBlueyServer(
  FakeBlueyPlatform fakePlatform,
  ServerId id, {
  String? addressSuffix,
  Duration intervalValue = const Duration(seconds: 10),
}) {
  final address = 'AA:BB:CC:DD:EE:${addressSuffix ?? '01'}';
  fakePlatform.simulatePeripheral(
    id: address,
    name: 'Bluey Server',
    serviceUuids: [controlServiceUuid],
    services: [
      platform.PlatformService(
        uuid: controlServiceUuid,
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
          ),
        ],
        includedServices: [],
      ),
    ],
    characteristicValues: {
      'b1e70003-0000-1000-8000-00805f9b34fb': encodeInterval(intervalValue),
      'b1e70004-0000-1000-8000-00805f9b34fb': id.toBytes(),
    },
  );
  return address;
}

void main() {
  late FakeBlueyPlatform fakePlatform;

  setUp(() {
    fakePlatform = FakeBlueyPlatform();
    platform.BlueyPlatform.instance = fakePlatform;
  });

  group('BlueyPeer', () {
    test('connect() returns a Connection with control service hidden',
        () async {
      final id = ServerId.generate();
      _simulateBlueyServer(fakePlatform, id);

      final peer = createBlueyPeer(
        platformApi: fakePlatform,
        serverId: id,
      );
      final conn = await peer.connect();

      expect(conn.state, ConnectionState.connected);
      final services = await conn.services();
      expect(
        services.any((s) => s.uuid.toString() == controlServiceUuid),
        isFalse,
      );

      await conn.disconnect();
    });

    test('connect() throws PeerNotFoundException if no match', () async {
      _simulateBlueyServer(fakePlatform, ServerId.generate());

      final peer = createBlueyPeer(
        platformApi: fakePlatform,
        serverId: ServerId('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
      );

      expect(
        () => peer.connect(scanTimeout: const Duration(milliseconds: 300)),
        throwsA(isA<PeerNotFoundException>()),
      );
    });

    test('disconnects when heartbeat write fails', () {
      fakeAsync((async) {
        final id = ServerId.generate();
        _simulateBlueyServer(fakePlatform, id);

        final peer = createBlueyPeer(
          platformApi: fakePlatform,
          serverId: id,
        );

        late Connection conn;
        peer
            .connect(scanTimeout: const Duration(milliseconds: 500))
            .then((c) => conn = c);

        // The scan phase uses Stream.timeout which needs elapsed time
        // in fakeAsync to close the scan stream.
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();

        final states = <ConnectionState>[];
        conn.stateChanges.listen(states.add);

        // Simulate server unreachable.
        fakePlatform.simulateWriteFailure = true;

        // Heartbeat interval is half the 10s lifecycle interval = 5s.
        async.elapse(const Duration(seconds: 6));
        async.flushMicrotasks();

        expect(states, contains(ConnectionState.disconnected));
      });
    });

    test('serverId getter returns the configured id', () {
      final id = ServerId.generate();
      final peer = createBlueyPeer(
        platformApi: fakePlatform,
        serverId: id,
      );
      expect(peer.serverId, equals(id));
    });

    test('concurrent connect() throws StateError', () async {
      final id = ServerId.generate();
      _simulateBlueyServer(fakePlatform, id);

      final peer = createBlueyPeer(
        platformApi: fakePlatform,
        serverId: id,
      );

      // Start first connect (will be in flight)
      final first = peer.connect();

      // Second connect should throw
      expect(() => peer.connect(), throwsStateError);

      // Let the first one finish
      final conn = await first;
      await conn.disconnect();
    });
  });
}
