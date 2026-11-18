import 'dart:async';

import 'package:bluey/bluey.dart';
import 'package:bluey/src/lifecycle.dart' as lifecycle;
import 'package:bluey/src/peer/bluey_peer.dart';
import 'package:bluey/src/peer/peer_discovery.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';
import '../fakes/test_helpers.dart';
import '../fixtures/connection_rig.dart';

void main() {
  late FakeBlueyPlatform fakePlatform;

  setUp(() {
    fakePlatform = FakeBlueyPlatform();
    platform.BlueyPlatform.instance = fakePlatform;
  });

  group('PeerDiscovery.discover', () {
    test('returns empty when no Bluey servers advertising', () async {
      final discovery = PeerDiscovery(
        platformApi: fakePlatform,
        borrow: ConnectionRig(fakePlatform).borrow,
        logger: testLogger(),
      );
      final ids = await discovery.discover(
        timeout: const Duration(milliseconds: 200),
      );
      expect(ids, isEmpty);
    });

    test('returns one entry per unique ServerId', () async {
      final id1 = ServerId.generate();
      final id2 = ServerId.generate();
      fakePlatform.simulateBlueyServer(
        address: 'AA:BB:CC:DD:EE:01',
        serverId: id1,
      );
      fakePlatform.simulateBlueyServer(
        address: 'AA:BB:CC:DD:EE:02',
        serverId: id2,
      );

      final discovery = PeerDiscovery(
        platformApi: fakePlatform,
        borrow: ConnectionRig(fakePlatform).borrow,
        logger: testLogger(),
      );
      final ids = await discovery.discover(
        timeout: const Duration(milliseconds: 500),
      );
      expect(ids.toSet(), equals({id1, id2}));
    });

    test('deduplicates by ServerId', () async {
      final id = ServerId.generate();
      fakePlatform.simulateBlueyServer(
        address: 'AA:BB:CC:DD:EE:01',
        serverId: id,
      );
      fakePlatform.simulateBlueyServer(
        address: 'AA:BB:CC:DD:EE:02',
        serverId: id,
      );

      final discovery = PeerDiscovery(
        platformApi: fakePlatform,
        borrow: ConnectionRig(fakePlatform).borrow,
        logger: testLogger(),
      );
      final ids = await discovery.discover(
        timeout: const Duration(milliseconds: 500),
      );
      expect(ids, hasLength(1));
    });
  });

  group('PeerDiscovery.connectTo', () {
    test('returns a Connection when a match is found', () async {
      final id = ServerId.generate();
      fakePlatform.simulateBlueyServer(
        address: 'AA:BB:CC:DD:EE:01',
        serverId: id,
      );

      final discovery = PeerDiscovery(
        platformApi: fakePlatform,
        borrow: ConnectionRig(fakePlatform).borrow,
        logger: testLogger(),
      );
      final connection = await discovery.connectTo(
        id,
        scanTimeout: const Duration(milliseconds: 500),
      );
      expect(connection, isNotNull);
      // The probe read the server id over this very link, which
      // discovered its services, so it is already `ready`.
      expect(connection.state, ConnectionState.ready);
      await connection.disconnect();
    });

    test('throws PeerNotFoundException when no match within timeout', () async {
      fakePlatform.simulateBlueyServer(
        address: 'AA:BB:CC:DD:EE:01',
        serverId: ServerId.generate(),
      );
      final discovery = PeerDiscovery(
        platformApi: fakePlatform,
        borrow: ConnectionRig(fakePlatform).borrow,
        logger: testLogger(),
      );
      final target = ServerId('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');

      expect(
        () => discovery.connectTo(
          target,
          scanTimeout: const Duration(milliseconds: 300),
        ),
        throwsA(isA<PeerNotFoundException>()),
      );
    });

    test('skips non-matching candidates and finds the correct one', () async {
      final wrongId = ServerId.generate();
      final target = ServerId.generate();
      fakePlatform.simulateBlueyServer(
        address: 'AA:BB:CC:DD:EE:01',
        serverId: wrongId,
      );
      fakePlatform.simulateBlueyServer(
        address: 'AA:BB:CC:DD:EE:02',
        serverId: target,
      );

      final discovery = PeerDiscovery(
        platformApi: fakePlatform,
        borrow: ConnectionRig(fakePlatform).borrow,
        logger: testLogger(),
      );
      final connection = await discovery.connectTo(
        target,
        scanTimeout: const Duration(milliseconds: 500),
      );
      // The probe read the server id over this very link, which
      // discovered its services, so it is already `ready`.
      expect(connection.state, ConnectionState.ready);
      await connection.disconnect();
    });
  });

  group('PeerDiscovery error handling', () {
    // 25. discover skips candidates that fail to connect
    test('discover skips candidates that fail to connect', () async {
      final goodId = ServerId.generate();
      final badId = ServerId.generate();

      // Set up two Bluey servers.
      fakePlatform.simulateBlueyServer(
        address: 'AA:BB:CC:DD:EE:01',
        serverId: badId,
      );
      fakePlatform.simulateBlueyServer(
        address: 'AA:BB:CC:DD:EE:02',
        serverId: goodId,
      );

      // Remove the first peripheral AFTER scanning will have discovered it
      // but BEFORE the probe connects. PeerDiscovery scans first, collects
      // all candidate addresses, then probes each one sequentially. We can
      // remove the peripheral so that connect() throws for that address.
      //
      // To achieve this timing, we wrap the call: first let scan collect
      // candidates (the fake emits them synchronously in the next microtask),
      // then remove the bad peripheral. However, since discover() is a
      // single await, we need a different approach: remove the peripheral
      // after the scan phase but before the probe phase.
      //
      // The simplest reliable approach: use a custom subclass or just remove
      // the peripheral synchronously before calling discover(). But then scan
      // won't find it. Instead, let scan find it, then by the time
      // _probeServerId tries to connect, the peripheral is gone.
      //
      // Actually, the fake's scan emits in a Future(() { ... }), so the
      // scan completes in the same microtask. The connect happens later.
      // We can't intercept between scan and connect in a single discover().
      //
      // Alternative approach: set up the bad peripheral without the serverId
      // characteristic value, so readCharacteristic throws during the probe.
      fakePlatform.removePeripheral('AA:BB:CC:DD:EE:01');
      fakePlatform.simulatePeripheral(
        id: 'AA:BB:CC:DD:EE:01',
        name: 'Bad Server',
        serviceUuids: [lifecycle.controlServiceUuid],
        services: [
          platform.PlatformService(
            uuid: lifecycle.controlServiceUuid,
            isPrimary: true,
            characteristics: const [
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
          ),
        ],
        // No characteristicValues -- readCharacteristic will throw
        characteristicValues: {},
      );

      final discovery = PeerDiscovery(
        platformApi: fakePlatform,
        borrow: ConnectionRig(fakePlatform).borrow,
        logger: testLogger(),
      );
      final ids = await discovery.discover(
        timeout: const Duration(milliseconds: 500),
      );

      // Only the good server should be returned.
      expect(ids, hasLength(1));
      expect(ids.first, equals(goodId));
    });
  });

  // I055: peer discovery must filter the OS-level scan on the control
  // service UUID so probing is O(matches) rather than O(nearby devices).
  group('PeerDiscovery scan filter (I055)', () {
    test('discover scans with the control service UUID as filter', () async {
      fakePlatform.simulateBlueyServer(
        address: 'AA:BB:CC:DD:EE:01',
        serverId: ServerId.generate(),
      );
      final discovery = PeerDiscovery(
        platformApi: fakePlatform,
        borrow: ConnectionRig(fakePlatform).borrow,
        logger: testLogger(),
      );
      await discovery.discover(timeout: const Duration(milliseconds: 200));

      expect(
        fakePlatform.lastScanConfig?.serviceUuids,
        equals([lifecycle.controlServiceUuid]),
      );
    });

    test('connectTo scans with the control service UUID as filter', () async {
      final id = ServerId.generate();
      fakePlatform.simulateBlueyServer(
        address: 'AA:BB:CC:DD:EE:01',
        serverId: id,
      );
      final discovery = PeerDiscovery(
        platformApi: fakePlatform,
        borrow: ConnectionRig(fakePlatform).borrow,
        logger: testLogger(),
      );
      final connection = await discovery.connectTo(
        id,
        scanTimeout: const Duration(milliseconds: 500),
      );

      expect(
        fakePlatform.lastScanConfig?.serviceUuids,
        equals([lifecycle.controlServiceUuid]),
      );
      await connection.disconnect();
    });
  });

  // I056: probe-connect must use a short bounded timeout so a single
  // unresponsive candidate doesn't stall the whole discovery session.
  group('PeerDiscovery probe timeout (I056)', () {
    test('discover uses 3s default probe timeout when none provided', () async {
      fakePlatform.simulateBlueyServer(
        address: 'AA:BB:CC:DD:EE:01',
        serverId: ServerId.generate(),
      );
      final discovery = PeerDiscovery(
        platformApi: fakePlatform,
        borrow: ConnectionRig(fakePlatform).borrow,
        logger: testLogger(),
      );
      await discovery.discover(timeout: const Duration(milliseconds: 200));

      expect(fakePlatform.lastConnectConfig?.timeoutMs, equals(3000));
    });

    test(
      'discover threads custom probeTimeout through to platform connect',
      () async {
        fakePlatform.simulateBlueyServer(
          address: 'AA:BB:CC:DD:EE:01',
          serverId: ServerId.generate(),
        );
        final discovery = PeerDiscovery(
          platformApi: fakePlatform,
          borrow: ConnectionRig(fakePlatform).borrow,
          logger: testLogger(),
        );
        await discovery.discover(
          timeout: const Duration(milliseconds: 200),
          probeTimeout: const Duration(milliseconds: 750),
        );

        expect(fakePlatform.lastConnectConfig?.timeoutMs, equals(750));
      },
    );

    test(
      'connectTo threads custom probeTimeout through to platform connect',
      () async {
        final id = ServerId.generate();
        fakePlatform.simulateBlueyServer(
          address: 'AA:BB:CC:DD:EE:01',
          serverId: id,
        );
        final discovery = PeerDiscovery(
          platformApi: fakePlatform,
          borrow: ConnectionRig(fakePlatform).borrow,
          logger: testLogger(),
        );
        final connection = await discovery.connectTo(
          id,
          scanTimeout: const Duration(milliseconds: 500),
          probeTimeout: const Duration(milliseconds: 1500),
        );

        expect(fakePlatform.lastConnectConfig?.timeoutMs, equals(1500));
        await connection.disconnect();
      },
    );
  });

  // L9 (I394): the scan window bounds which candidates are probed, and a
  // radio that refuses to stop scanning does not cost the caller its peers.
  group('PeerDiscovery scan window and stopScan (L9)', () {
    const window = Duration(seconds: 2);
    const early = 'AA:BB:CC:DD:EE:01';
    const late = 'AA:BB:CC:DD:EE:02';

    test('a candidate seen after the window closes is not probed', () {
      fakeAsync((async) {
        // arrange
        final fake = _ScheduledScanPlatform();
        platform.BlueyPlatform.instance = fake;
        final earlyServerId = ServerId.generate();
        fake.connectDelays[early] = const Duration(seconds: 1);
        final discovery = PeerDiscovery(
          platformApi: fake,
          borrow: ConnectionRig(fake).borrow,
          logger: testLogger(),
        );

        // act
        List<ServerId>? result;
        discovery.discover(timeout: window).then((ids) => result = ids);
        async.elapse(const Duration(milliseconds: 1900));
        fake.advertise(early, earlyServerId);
        async.elapse(const Duration(milliseconds: 101));
        fake.advertise(late, ServerId.generate());
        async.elapse(const Duration(seconds: 10));

        // assert
        expect(fake.connectsTo(late), 0);
        expect(result, [earlyServerId]);
      });
    });

    test('a candidate queued inside the window whose probe has not started '
        'when it closes is not probed', () {
      fakeAsync((async) {
        // arrange
        final fake = _ScheduledScanPlatform();
        platform.BlueyPlatform.instance = fake;
        final earlyServerId = ServerId.generate();
        const queued = 'AA:BB:CC:DD:EE:03';
        fake.connectDelays[early] = const Duration(seconds: 2);
        final discovery = PeerDiscovery(
          platformApi: fake,
          borrow: ConnectionRig(fake).borrow,
          logger: testLogger(),
        );

        // act
        List<ServerId>? result;
        discovery.discover(timeout: window).then((ids) => result = ids);
        async.elapse(const Duration(milliseconds: 1000));
        fake.advertise(early, earlyServerId);
        async.elapse(const Duration(milliseconds: 500));
        fake.advertise(queued, ServerId.generate());
        async.elapse(const Duration(seconds: 10));

        // assert
        expect(fake.connectsTo(queued), 0);
        expect(result, [earlyServerId]);
      });
    });

    test('discover waits for the probe in flight before it returns', () {
      fakeAsync((async) {
        // arrange
        final fake = _ScheduledScanPlatform();
        platform.BlueyPlatform.instance = fake;
        final serverId = ServerId.generate();
        fake.connectDelays[early] = const Duration(seconds: 1);
        final discovery = PeerDiscovery(
          platformApi: fake,
          borrow: ConnectionRig(fake).borrow,
          logger: testLogger(),
        );

        // act
        List<ServerId>? result;
        discovery.discover(timeout: window).then((ids) => result = ids);
        async.elapse(const Duration(milliseconds: 1900));
        fake.advertise(early, serverId);
        async.elapse(const Duration(milliseconds: 200));
        final beforeTheProbeEnds = result;
        async.elapse(const Duration(seconds: 1));

        // assert
        expect(beforeTheProbeEnds, isNull);
        expect(result, [serverId]);
      });
    });

    test(
      'a failing stopScan is logged and the peers found are still returned',
      () {
        fakeAsync((async) {
          // arrange
          final serverId = ServerId.generate();
          fakePlatform.simulateBlueyServer(address: early, serverId: serverId);
          fakePlatform.enqueueFault(FakeOp.stopScan, StateError('radio busy'));
          final logger = testLogger();
          final records = <BlueyLogEvent>[];
          logger.events.listen(records.add);
          final discovery = PeerDiscovery(
            platformApi: fakePlatform,
            borrow: ConnectionRig(fakePlatform).borrow,
            logger: logger,
          );

          // act
          List<ServerId>? result;
          Object? error;
          discovery
              .discover(timeout: window)
              .then<void>(
                (ids) => result = ids,
                onError: (Object e) => error = e,
              );
          async.elapse(window);

          // assert
          expect(error, isNull);
          expect(result, [serverId]);
          final warnings = records.where((r) => r.level == BlueyLogLevel.warn);
          expect(warnings, hasLength(1));
          expect(warnings.single.context, 'bluey.peer.discovery');
          expect(warnings.single.message, 'discoverPeers stopScan failed');
        });
      },
    );

    test('connectTo returns the Connection it found when stopScan fails', () {
      fakeAsync((async) {
        // arrange
        final serverId = ServerId.generate();
        fakePlatform.simulateBlueyServer(address: early, serverId: serverId);
        fakePlatform.enqueueFault(FakeOp.stopScan, StateError('radio busy'));
        final logger = testLogger();
        final records = <BlueyLogEvent>[];
        logger.events.listen(records.add);
        final discovery = PeerDiscovery(
          platformApi: fakePlatform,
          borrow: ConnectionRig(fakePlatform).borrow,
          logger: logger,
        );

        // act
        Connection? connection;
        Object? error;
        discovery
            .connectTo(serverId, scanTimeout: window)
            .then<void>(
              (c) => connection = c,
              onError: (Object e) => error = e,
            );
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 100));

        // assert
        expect(error, isNull);
        expect(connection?.deviceAddress, const DeviceAddress(early));
        final warnings = records.where((r) => r.level == BlueyLogLevel.warn);
        expect(warnings, hasLength(1));
        expect(warnings.single.context, 'bluey.peer.discovery');
        expect(warnings.single.message, 'connectTo stopScan failed');

        connection?.disconnect();
        async.flushMicrotasks();
      });
    });
  });
  group('H2 (I380): peer discovery probes tear down live connections', () {
    test('discoverPeers leaves an existing peer connection intact', () async {
      // arrange
      const address = 'AA:BB:CC:DD:EE:01';
      fakePlatform.simulateBlueyServer(
        address: address,
        serverId: TestServerIds.remoteIdentity,
      );
      final bluey = await Bluey.create(
        localIdentity: TestServerIds.localIdentity,
      );
      final peer = await bluey.connectAsPeer(
        Device(address: const DeviceAddress(address)),
      );
      expect(fakePlatform.connectedDeviceIds, contains(address));

      // act
      await bluey.discoverPeers(timeout: const Duration(milliseconds: 300));
      await pumpEventQueue();

      // assert
      expect(
        fakePlatform.connectedDeviceIds,
        contains(address),
        reason: 'the probe disconnected the link the app was using',
      );
      expect(peer.connection.state, isNot(ConnectionState.disconnected));
      await peer.disconnect();
      await bluey.dispose();
    });
  });

  group('A probe borrows the link', () {
    const address = 'AA:BB:CC:DD:EE:01';

    test(
      "a probe of a device the app holds reads over the app's link and leaves it",
      () async {
        // arrange
        final serverId = ServerId.generate();
        final counting = _ScheduledScanPlatform();
        platform.BlueyPlatform.instance = counting;
        counting.simulateBlueyServer(address: address, serverId: serverId);
        final rig = ConnectionRig(counting);
        final held = await rig.connect(const DeviceAddress(address));
        await held.services();
        final discovery = PeerDiscovery(
          platformApi: counting,
          borrow: rig.borrow,
          logger: testLogger(),
        );

        // act
        final ids = await discovery.discover(
          timeout: const Duration(milliseconds: 300),
        );
        await pumpEventQueue();

        // assert
        expect(ids, [serverId]);
        expect(counting.connectsTo(address), 1);
        expect(held.state, ConnectionState.ready);
        expect(counting.connectedDeviceIds, contains(address));
        await held.disconnect();
      },
    );

    test('a probe gives back the link it opened', () async {
      // arrange
      final serverId = ServerId.generate();
      fakePlatform.simulateBlueyServer(address: address, serverId: serverId);
      final discovery = PeerDiscovery(
        platformApi: fakePlatform,
        borrow: ConnectionRig(fakePlatform).borrow,
        logger: testLogger(),
      );

      // act
      final ids = await discovery.discover(
        timeout: const Duration(milliseconds: 300),
      );
      await pumpEventQueue();

      // assert
      expect(ids, [serverId]);
      expect(fakePlatform.connectedDeviceIds, isNot(contains(address)));
    });

    test('BlueyPeer.connect keeps the link of the peer it found', () async {
      // arrange
      final serverId = ServerId.generate();
      fakePlatform.simulateBlueyServer(address: address, serverId: serverId);
      final rig = ConnectionRig(fakePlatform);
      final peer = createBlueyPeer(
        platformApi: fakePlatform,
        serverId: serverId,
        localIdentity: TestServerIds.localIdentity,
        logger: testLogger(),
        borrow: rig.borrow,
        connectionIdOf: rig.connectionIdOf,
      );

      // act
      final peerConnection = await peer.connect(
        scanTimeout: const Duration(milliseconds: 500),
      );
      await pumpEventQueue();
      final appConnection = await rig.connect(const DeviceAddress(address));

      // assert
      expect(peerConnection.connection.state, ConnectionState.ready);
      expect(fakePlatform.connectedDeviceIds, contains(address));
      expect(identical(appConnection, peerConnection.connection), isTrue);
      await peerConnection.disconnect();
    });
  });
}

/// A fake that lets a test advertise a candidate at a chosen moment of an
/// open scan, and delay and count the connects to each device, so a probe
/// can be placed on either side of the scan window's close.
final class _ScheduledScanPlatform extends FakeBlueyPlatform {
  final List<StreamController<platform.PlatformDevice>> _scans = [];
  final List<String> _connects = [];

  /// How long a connect to each device takes before it reaches the fake.
  final Map<String, Duration> connectDelays = {};

  /// How many connects were asked of [address].
  int connectsTo(String address) =>
      _connects.where((id) => id == address).length;

  /// Registers a Bluey server at [address] and reports it to every scan
  /// opened so far.
  void advertise(String address, ServerId serverId) {
    simulateBlueyServer(address: address, serverId: serverId);
    for (final scan in _scans) {
      scan.add(
        platform.PlatformDevice(
          id: address,
          name: 'Bluey Server',
          rssi: -50,
          serviceUuids: [lifecycle.controlServiceUuid],
          manufacturerDataCompanyId: null,
          manufacturerData: null,
        ),
      );
    }
  }

  @override
  Stream<platform.PlatformDevice> scan(platform.PlatformScanConfig config) {
    final scan = StreamController<platform.PlatformDevice>.broadcast();
    _scans.add(scan);
    super.scan(config).listen(scan.add, onError: scan.addError);
    return scan.stream;
  }

  @override
  Future<String> connect(
    String deviceId,
    platform.PlatformConnectConfig config,
  ) async {
    _connects.add(deviceId);
    final delay = connectDelays[deviceId];
    if (delay != null) {
      final elapsed = Completer<void>();
      Timer(delay, elapsed.complete);
      await elapsed.future;
    }
    return super.connect(deviceId, config);
  }
}
