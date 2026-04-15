import 'dart:typed_data';

import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';

// Control service UUIDs (must match lifecycle.dart)
const _controlServiceUuid = 'b1e70001-0000-1000-8000-00805f9b34fb';
const _heartbeatCharUuid = 'b1e70002-0000-1000-8000-00805f9b34fb';
const _intervalCharUuid = 'b1e70003-0000-1000-8000-00805f9b34fb';

const _deviceAddress = 'AA:BB:CC:DD:EE:01';

/// Builds a fake peripheral that advertises the lifecycle control service,
/// matching what a Bluey server would expose.
void _simulateBlueyServerPeripheral(FakeBlueyPlatform fakePlatform) {
  fakePlatform.simulatePeripheral(
    id: _deviceAddress,
    name: 'Bluey Server',
    services: const [
      platform.PlatformService(
        uuid: _controlServiceUuid,
        isPrimary: true,
        characteristics: [
          platform.PlatformCharacteristic(
            uuid: _heartbeatCharUuid,
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
            uuid: _intervalCharUuid,
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
    // Default interval: 10 seconds as 4-byte little-endian ms (10000 = 0x2710)
    characteristicValues: {
      _intervalCharUuid: _intervalBytes10s,
    },
  );
}

// 10_000 ms in 4-byte little-endian
final _intervalBytes10s = Uint8List.fromList([0x10, 0x27, 0x00, 0x00]);

Future<Connection> _connectAndDiscover(
  Bluey bluey, {
  int maxFailedHeartbeats = 1,
  bool requireLifecycle = false,
}) async {
  final device = Device(
    id: UUID('00000000-0000-0000-0000-aabbccddee01'),
    address: _deviceAddress,
    name: 'Bluey Server',
  );
  final connection = await bluey.connect(
    device,
    maxFailedHeartbeats: maxFailedHeartbeats,
    requireLifecycle: requireLifecycle,
  );
  // Discovering services is what starts the lifecycle heartbeat.
  await connection.services();
  return connection;
}

/// Builds a fake peripheral with some non-Bluey service (no control service).
void _simulateNonBlueyPeripheral(FakeBlueyPlatform fakePlatform) {
  fakePlatform.simulatePeripheral(
    id: _deviceAddress,
    name: 'Generic BLE Peer',
    services: const [
      platform.PlatformService(
        uuid: '00001800-0000-1000-8000-00805f9b34fb', // Generic Access
        isPrimary: true,
        characteristics: [],
        includedServices: [],
      ),
    ],
  );
}

void main() {
  late FakeBlueyPlatform fakePlatform;

  setUp(() {
    fakePlatform = FakeBlueyPlatform();
    platform.BlueyPlatform.instance = fakePlatform;
  });

  group('LifecycleClient disconnect detection', () {
    test(
        'disconnects when heartbeat write fails with default '
        'maxFailedHeartbeats (1)', () {
      fakeAsync((async) {
        _simulateBlueyServerPeripheral(fakePlatform);

        final bluey = Bluey();

        late Connection connection;
        _connectAndDiscover(bluey).then((c) => connection = c);
        // Let connect + service discovery + interval read complete.
        async.flushMicrotasks();

        final states = <ConnectionState>[];
        connection.stateChanges.listen(states.add);
        async.flushMicrotasks();

        // Server goes away — next heartbeat will fail.
        fakePlatform.simulateWriteFailure = true;

        // Default heartbeat interval is half the default 10s lifecycle
        // interval, i.e. 5 seconds. Advance well past that.
        async.elapse(const Duration(seconds: 6));
        async.flushMicrotasks();

        expect(
          states,
          contains(ConnectionState.disconnected),
          reason: 'Connection should transition to disconnected after the '
              'first failed heartbeat when maxFailedHeartbeats == 1',
        );

        bluey.dispose();
        async.flushMicrotasks();
      });
    });

    test(
        'requires maxFailedHeartbeats consecutive failures before '
        'disconnecting', () {
      fakeAsync((async) {
        _simulateBlueyServerPeripheral(fakePlatform);

        final bluey = Bluey();

        late Connection connection;
        _connectAndDiscover(bluey, maxFailedHeartbeats: 3)
            .then((c) => connection = c);
        async.flushMicrotasks();

        final states = <ConnectionState>[];
        connection.stateChanges.listen(states.add);
        async.flushMicrotasks();

        fakePlatform.simulateWriteFailure = true;

        // One heartbeat failure: not yet disconnected.
        async.elapse(const Duration(seconds: 6));
        async.flushMicrotasks();
        expect(
          states,
          isNot(contains(ConnectionState.disconnected)),
          reason: 'Should not disconnect after 1 failure when '
              'maxFailedHeartbeats == 3',
        );

        // Second failure: still not disconnected.
        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();
        expect(
          states,
          isNot(contains(ConnectionState.disconnected)),
          reason: 'Should not disconnect after 2 failures when '
              'maxFailedHeartbeats == 3',
        );

        // Third failure: should now disconnect.
        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();
        expect(
          states,
          contains(ConnectionState.disconnected),
          reason: 'Should disconnect after 3 consecutive failures',
        );

        bluey.dispose();
        async.flushMicrotasks();
      });
    });

    test('successful heartbeat resets the failure count', () {
      fakeAsync((async) {
        _simulateBlueyServerPeripheral(fakePlatform);

        final bluey = Bluey();

        late Connection connection;
        _connectAndDiscover(bluey, maxFailedHeartbeats: 2)
            .then((c) => connection = c);
        async.flushMicrotasks();

        final states = <ConnectionState>[];
        connection.stateChanges.listen(states.add);
        async.flushMicrotasks();

        // First heartbeat: fails.
        fakePlatform.simulateWriteFailure = true;
        async.elapse(const Duration(seconds: 6));
        async.flushMicrotasks();
        expect(states, isNot(contains(ConnectionState.disconnected)));

        // Server comes back — next heartbeat succeeds, resetting the counter.
        fakePlatform.simulateWriteFailure = false;
        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();
        expect(states, isNot(contains(ConnectionState.disconnected)));

        // Server goes away again — one more failure should NOT disconnect
        // because the counter was reset by the successful heartbeat.
        fakePlatform.simulateWriteFailure = true;
        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();
        expect(
          states,
          isNot(contains(ConnectionState.disconnected)),
          reason: 'Counter should have been reset by the successful '
              'heartbeat — a single failure after should not disconnect',
        );

        // A second consecutive failure now reaches the threshold.
        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();
        expect(
          states,
          contains(ConnectionState.disconnected),
          reason: 'Should disconnect after 2 consecutive failures following '
              'the reset',
        );

        bluey.dispose();
        async.flushMicrotasks();
      });
    });
  });

  group('LifecycleClient requireLifecycle', () {
    test(
        'permissive mode accepts a non-Bluey peer (no control service) '
        'without disconnecting', () {
      fakeAsync((async) {
        _simulateNonBlueyPeripheral(fakePlatform);

        final bluey = Bluey();

        late Connection connection;
        _connectAndDiscover(bluey).then((c) => connection = c);
        async.flushMicrotasks();

        final states = <ConnectionState>[];
        connection.stateChanges.listen(states.add);

        // Wait past any heartbeat interval — nothing should happen since no
        // heartbeat is running against a non-Bluey peer.
        async.elapse(const Duration(seconds: 30));
        async.flushMicrotasks();

        expect(
          states,
          isNot(contains(ConnectionState.disconnected)),
          reason: 'Permissive mode (default) should leave non-Bluey peers '
              'connected',
        );

        bluey.dispose();
        async.flushMicrotasks();
      });
    });

    test(
        'requireLifecycle disconnects when peer lacks the control service',
        () {
      fakeAsync((async) {
        _simulateNonBlueyPeripheral(fakePlatform);

        final bluey = Bluey();

        late Connection connection;
        _connectAndDiscover(bluey, requireLifecycle: true)
            .then((c) => connection = c);
        async.flushMicrotasks();

        final states = <ConnectionState>[];
        connection.stateChanges.listen(states.add);

        // The disconnect is fired synchronously during services() — but we
        // subscribed after services() returned, so let any pending async
        // propagation run.
        async.flushMicrotasks();
        async.elapse(Duration.zero);

        // Connection state should now reflect disconnection.
        expect(
          connection.state,
          ConnectionState.disconnected,
          reason: 'requireLifecycle should disconnect peers that do not host '
              'the control service',
        );

        bluey.dispose();
        async.flushMicrotasks();
      });
    });

    test(
        'requireLifecycle with a proper Bluey server does NOT spuriously '
        'disconnect', () {
      fakeAsync((async) {
        _simulateBlueyServerPeripheral(fakePlatform);

        final bluey = Bluey();

        late Connection connection;
        _connectAndDiscover(bluey, requireLifecycle: true)
            .then((c) => connection = c);
        async.flushMicrotasks();

        final states = <ConnectionState>[];
        connection.stateChanges.listen(states.add);

        // Let heartbeats flow normally.
        async.elapse(const Duration(seconds: 20));
        async.flushMicrotasks();

        expect(
          states,
          isNot(contains(ConnectionState.disconnected)),
          reason: 'A proper Bluey server should satisfy requireLifecycle',
        );

        bluey.dispose();
        async.flushMicrotasks();
      });
    });
  });
}
