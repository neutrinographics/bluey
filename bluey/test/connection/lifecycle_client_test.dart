import 'dart:typed_data';

import 'package:bluey/bluey.dart';
import 'package:bluey/src/connection/lifecycle_client.dart';
import 'package:bluey/src/gatt_client/gatt.dart';
import 'package:bluey/src/lifecycle.dart' as lifecycle;
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';

const _deviceAddress = 'AA:BB:CC:DD:EE:01';

/// Helper to set up a simulated Bluey server and create a connected
/// [LifecycleClient] ready for testing.
Future<({
  LifecycleClient client,
  List<RemoteService> services,
  FakeBlueyPlatform fakePlatform,
})> _setUpConnectedClient({
  int maxFailedHeartbeats = 1,
  Duration intervalValue = const Duration(seconds: 10),
  required void Function() onServerUnreachable,
}) async {
  final fakePlatform = FakeBlueyPlatform();
  platform.BlueyPlatform.instance = fakePlatform;

  final serverId = ServerId.generate();
  fakePlatform.simulateBlueyServer(
    address: _deviceAddress,
    serverId: serverId,
    intervalValue: intervalValue,
  );

  await fakePlatform.connect(
    _deviceAddress,
    const platform.PlatformConnectConfig(timeoutMs: null, mtu: null),
  );

  final platformServices = await fakePlatform.discoverServices(_deviceAddress);
  final domainServices = platformServices
      .map((ps) => _TestRemoteService(ps, fakePlatform, _deviceAddress))
      .toList();

  final client = LifecycleClient(
    platformApi: fakePlatform,
    connectionId: _deviceAddress,
    maxFailedHeartbeats: maxFailedHeartbeats,
    onServerUnreachable: onServerUnreachable,
  );

  return (
    client: client,
    services: List<RemoteService>.from(domainServices),
    fakePlatform: fakePlatform,
  );
}

void main() {
  group('LifecycleClient', () {
    // 1. start() with no control service does not start heartbeat
    test('start() with no control service does not start heartbeat', () async {
      final fakePlatform = FakeBlueyPlatform();
      platform.BlueyPlatform.instance = fakePlatform;

      fakePlatform.simulatePeripheral(
        id: _deviceAddress,
        name: 'Regular Device',
        services: const [
          platform.PlatformService(
            uuid: '0000180d-0000-1000-8000-00805f9b34fb',
            isPrimary: true,
            characteristics: [],
            includedServices: [],
          ),
        ],
      );

      await fakePlatform.connect(
        _deviceAddress,
        const platform.PlatformConnectConfig(timeoutMs: null, mtu: null),
      );

      final platformServices =
          await fakePlatform.discoverServices(_deviceAddress);
      final domainServices = platformServices
          .map((ps) => _TestRemoteService(ps, fakePlatform, _deviceAddress))
          .toList();

      final client = LifecycleClient(
        platformApi: fakePlatform,
        connectionId: _deviceAddress,
        onServerUnreachable: () {},
      );

      client.start(allServices: List<RemoteService>.from(domainServices));

      expect(client.isRunning, isFalse);
      expect(fakePlatform.writeCharacteristicCalls, isEmpty);
    });

    // 2. start() with control service but no heartbeat char does not start
    test(
      'start() with control service but no heartbeat char does not start',
      () async {
        final fakePlatform = FakeBlueyPlatform();
        platform.BlueyPlatform.instance = fakePlatform;

        fakePlatform.simulatePeripheral(
          id: _deviceAddress,
          name: 'Partial Bluey',
          services: [
            platform.PlatformService(
              uuid: lifecycle.controlServiceUuid,
              isPrimary: true,
              characteristics: const [
                // Only interval char, no heartbeat char
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
              ],
              includedServices: [],
            ),
          ],
        );

        await fakePlatform.connect(
          _deviceAddress,
          const platform.PlatformConnectConfig(timeoutMs: null, mtu: null),
        );

        final platformServices =
            await fakePlatform.discoverServices(_deviceAddress);
        final domainServices = platformServices
            .map((ps) => _TestRemoteService(ps, fakePlatform, _deviceAddress))
            .toList();

        final client = LifecycleClient(
          platformApi: fakePlatform,
          connectionId: _deviceAddress,
          onServerUnreachable: () {},
        );

        client.start(allServices: List<RemoteService>.from(domainServices));

        expect(client.isRunning, isFalse);
        expect(fakePlatform.writeCharacteristicCalls, isEmpty);
      },
    );

    // 3. start() is idempotent when already started
    test('start() is idempotent when already started', () {
      fakeAsync((async) {
        late LifecycleClient client;
        late List<RemoteService> services;
        late FakeBlueyPlatform fakePlatform;

        _setUpConnectedClient(onServerUnreachable: () {}).then((setup) {
          client = setup.client;
          services = setup.services;
          fakePlatform = setup.fakePlatform;
        });
        async.flushMicrotasks();

        client.start(allServices: services);
        async.flushMicrotasks();

        final writesAfterFirstStart =
            fakePlatform.writeCharacteristicCalls.length;

        client.start(allServices: services);
        async.flushMicrotasks();

        expect(
          fakePlatform.writeCharacteristicCalls.length,
          equals(writesAfterFirstStart),
          reason: 'Second start() should not send additional heartbeats',
        );

        client.stop();
      });
    });

    // 4. start() sends first heartbeat immediately
    test('start() sends first heartbeat immediately', () {
      fakeAsync((async) {
        late LifecycleClient client;
        late List<RemoteService> services;
        late FakeBlueyPlatform fakePlatform;

        _setUpConnectedClient(onServerUnreachable: () {}).then((setup) {
          client = setup.client;
          services = setup.services;
          fakePlatform = setup.fakePlatform;
        });
        async.flushMicrotasks();

        client.start(allServices: services);
        async.flushMicrotasks();

        final heartbeatWrites = fakePlatform.writeCharacteristicCalls.where(
          (call) =>
              call.characteristicUuid == lifecycle.heartbeatCharUuid &&
              call.value.length == 1 &&
              call.value[0] == 0x01,
        );
        expect(heartbeatWrites, isNotEmpty,
            reason: 'First heartbeat should be sent during start()');

        client.stop();
      });
    });

    // 5. start() reads interval and sets heartbeat to half
    test('start() reads interval and sets heartbeat to half', () {
      fakeAsync((async) {
        late LifecycleClient client;
        late List<RemoteService> services;
        late FakeBlueyPlatform fakePlatform;

        // Server interval = 20s => heartbeat at 10s
        _setUpConnectedClient(
          onServerUnreachable: () {},
          intervalValue: const Duration(seconds: 20),
        ).then((setup) {
          client = setup.client;
          services = setup.services;
          fakePlatform = setup.fakePlatform;
        });
        async.flushMicrotasks();

        client.start(allServices: services);
        async.flushMicrotasks();

        fakePlatform.writeCharacteristicCalls.clear();

        // Advance 10 seconds -- heartbeat should fire.
        async.elapse(const Duration(seconds: 10));

        final heartbeatWrites = fakePlatform.writeCharacteristicCalls.where(
          (call) =>
              call.characteristicUuid == lifecycle.heartbeatCharUuid &&
              call.value[0] == 0x01,
        );
        expect(heartbeatWrites, hasLength(1),
            reason: 'Heartbeat should fire at half the server interval (10s)');

        client.stop();
      });
    });

    // 6. start() falls back to default interval when interval read fails
    test('start() falls back to default interval when interval read fails', () {
      fakeAsync((async) {
        final fakePlatform = FakeBlueyPlatform();
        platform.BlueyPlatform.instance = fakePlatform;

        // Set up a Bluey server but remove the interval char VALUE so the
        // read will throw, while the interval char UUID itself is still
        // discoverable in the service structure.
        fakePlatform.simulatePeripheral(
          id: _deviceAddress,
          name: 'Bluey Server',
          serviceUuids: [lifecycle.controlServiceUuid],
          services: [
            platform.PlatformService(
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
              ],
              includedServices: [],
            ),
          ],
          // No values => readCharacteristic will throw
          characteristicValues: {},
        );

        fakePlatform.connect(
          _deviceAddress,
          const platform.PlatformConnectConfig(timeoutMs: null, mtu: null),
        );
        async.flushMicrotasks();

        late List<platform.PlatformService> pServices;
        fakePlatform.discoverServices(_deviceAddress).then((s) => pServices = s);
        async.flushMicrotasks();

        final domainServices = pServices
            .map((ps) => _TestRemoteService(ps, fakePlatform, _deviceAddress))
            .toList();

        final client = LifecycleClient(
          platformApi: fakePlatform,
          connectionId: _deviceAddress,
          onServerUnreachable: () {},
        );

        client.start(allServices: List<RemoteService>.from(domainServices));
        async.flushMicrotasks();

        expect(client.isRunning, isTrue);
        fakePlatform.writeCharacteristicCalls.clear();

        // Default interval = 10s, heartbeat = 5s.
        async.elapse(const Duration(seconds: 5));

        final heartbeatWrites = fakePlatform.writeCharacteristicCalls.where(
          (call) =>
              call.characteristicUuid == lifecycle.heartbeatCharUuid &&
              call.value[0] == 0x01,
        );
        expect(heartbeatWrites, hasLength(1),
            reason: 'Should fall back to default interval (10s / 2 = 5s)');

        client.stop();
      });
    });

    // 7. start() falls back to default interval when interval char is absent
    test(
      'start() falls back to default interval when interval char is absent',
      () {
        fakeAsync((async) {
          final fakePlatform = FakeBlueyPlatform();
          platform.BlueyPlatform.instance = fakePlatform;

          fakePlatform.simulatePeripheral(
            id: _deviceAddress,
            name: 'No Interval',
            serviceUuids: [lifecycle.controlServiceUuid],
            services: [
              platform.PlatformService(
                uuid: lifecycle.controlServiceUuid,
                isPrimary: true,
                characteristics: const [
                  // Heartbeat char only -- no interval char
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
                ],
                includedServices: [],
              ),
            ],
          );

          fakePlatform.connect(
            _deviceAddress,
            const platform.PlatformConnectConfig(timeoutMs: null, mtu: null),
          );
          async.flushMicrotasks();

          late List<platform.PlatformService> pServices;
          fakePlatform
              .discoverServices(_deviceAddress)
              .then((s) => pServices = s);
          async.flushMicrotasks();

          final domainServices = pServices
              .map(
                (ps) => _TestRemoteService(ps, fakePlatform, _deviceAddress),
              )
              .toList();

          final client = LifecycleClient(
            platformApi: fakePlatform,
            connectionId: _deviceAddress,
            onServerUnreachable: () {},
          );

          client.start(
            allServices: List<RemoteService>.from(domainServices),
          );
          async.flushMicrotasks();

          expect(client.isRunning, isTrue);
          fakePlatform.writeCharacteristicCalls.clear();

          // Default interval = 10s, heartbeat = 5s.
          async.elapse(const Duration(seconds: 5));

          final heartbeatWrites = fakePlatform.writeCharacteristicCalls.where(
            (call) =>
                call.characteristicUuid == lifecycle.heartbeatCharUuid &&
                call.value[0] == 0x01,
          );
          expect(heartbeatWrites, hasLength(1),
              reason: 'Should use default interval when interval char absent');

          client.stop();
        });
      },
    );

    // 8. stop() cancels timer and resets state
    test('stop() cancels timer and resets state', () {
      fakeAsync((async) {
        late LifecycleClient client;
        late List<RemoteService> services;

        _setUpConnectedClient(onServerUnreachable: () {}).then((setup) {
          client = setup.client;
          services = setup.services;
        });
        async.flushMicrotasks();

        client.start(allServices: services);
        async.flushMicrotasks();
        expect(client.isRunning, isTrue);

        client.stop();

        expect(client.isRunning, isFalse);
      });
    });

    // 9. sendDisconnectCommand() writes 0x00 with response
    test('sendDisconnectCommand() writes 0x00 with response', () {
      fakeAsync((async) {
        late LifecycleClient client;
        late List<RemoteService> services;
        late FakeBlueyPlatform fakePlatform;

        _setUpConnectedClient(onServerUnreachable: () {}).then((setup) {
          client = setup.client;
          services = setup.services;
          fakePlatform = setup.fakePlatform;
        });
        async.flushMicrotasks();

        client.start(allServices: services);
        async.flushMicrotasks();

        fakePlatform.writeCharacteristicCalls.clear();

        client.sendDisconnectCommand();
        async.flushMicrotasks();

        final disconnectWrites = fakePlatform.writeCharacteristicCalls.where(
          (call) =>
              call.characteristicUuid == lifecycle.heartbeatCharUuid &&
              call.value.length == 1 &&
              call.value[0] == 0x00 &&
              call.withResponse == true,
        );
        expect(disconnectWrites, hasLength(1),
            reason: 'Should write 0x00 with response to heartbeat char');

        client.stop();
      });
    });

    // 10. sendDisconnectCommand() is no-op when not started
    test('sendDisconnectCommand() is no-op when not started', () async {
      final setup = await _setUpConnectedClient(
        onServerUnreachable: () {},
      );

      await setup.client.sendDisconnectCommand();

      expect(setup.fakePlatform.writeCharacteristicCalls, isEmpty,
          reason: 'Should not write when not started');
    });

    // 11. sendDisconnectCommand() swallows errors
    test('sendDisconnectCommand() swallows errors', () {
      fakeAsync((async) {
        late LifecycleClient client;
        late List<RemoteService> services;
        late FakeBlueyPlatform fakePlatform;

        _setUpConnectedClient(onServerUnreachable: () {}).then((setup) {
          client = setup.client;
          services = setup.services;
          fakePlatform = setup.fakePlatform;
        });
        async.flushMicrotasks();

        client.start(allServices: services);
        async.flushMicrotasks();

        fakePlatform.simulateWriteFailure = true;

        // Should NOT throw.
        client.sendDisconnectCommand();
        async.flushMicrotasks();

        fakePlatform.simulateWriteFailure = false;
        client.stop();
      });
    });

    // 12. heartbeat success resets failure count
    test('heartbeat success resets failure count', () {
      fakeAsync((async) {
        var unreachableFired = false;
        late LifecycleClient client;
        late List<RemoteService> services;
        late FakeBlueyPlatform fakePlatform;

        _setUpConnectedClient(
          maxFailedHeartbeats: 3,
          onServerUnreachable: () => unreachableFired = true,
        ).then((setup) {
          client = setup.client;
          services = setup.services;
          fakePlatform = setup.fakePlatform;
        });
        async.flushMicrotasks();

        client.start(allServices: services);
        async.flushMicrotasks();

        // Fail 2 heartbeats (below threshold of 3).
        fakePlatform.simulateWriteFailure = true;
        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();

        // Succeed one heartbeat -- resets failure count.
        fakePlatform.simulateWriteFailure = false;
        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();

        // Fail 2 more -- still below threshold because count was reset.
        fakePlatform.simulateWriteFailure = true;
        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();

        expect(unreachableFired, isFalse,
            reason: 'Success should have reset the failure counter');

        fakePlatform.simulateWriteFailure = false;
        client.stop();
      });
    });

    // 13. heartbeat failure fires onServerUnreachable after maxFailedHeartbeats
    test(
      'heartbeat failure fires onServerUnreachable after maxFailedHeartbeats',
      () {
        fakeAsync((async) {
          var unreachableFired = false;
          late LifecycleClient client;
          late List<RemoteService> services;
          late FakeBlueyPlatform fakePlatform;

          _setUpConnectedClient(
            maxFailedHeartbeats: 3,
            onServerUnreachable: () => unreachableFired = true,
          ).then((setup) {
            client = setup.client;
            services = setup.services;
            fakePlatform = setup.fakePlatform;
          });
          async.flushMicrotasks();

          client.start(allServices: services);
          async.flushMicrotasks();

          // Initial immediate heartbeat succeeds. Now enable failures.
          fakePlatform.simulateWriteFailure = true;

          // Failure 1
          async.elapse(const Duration(seconds: 5));
          async.flushMicrotasks();
          expect(unreachableFired, isFalse);

          // Failure 2
          async.elapse(const Duration(seconds: 5));
          async.flushMicrotasks();
          expect(unreachableFired, isFalse);

          // Failure 3 -- should trigger callback
          async.elapse(const Duration(seconds: 5));
          async.flushMicrotasks();
          expect(unreachableFired, isTrue);
          expect(client.isRunning, isFalse,
              reason: 'stop() should have been called internally');

          fakePlatform.simulateWriteFailure = false;
        });
      },
    );

    // 14. heartbeat failure with default maxFailedHeartbeats=1 fires immediately
    test(
      'heartbeat failure with default maxFailedHeartbeats=1 fires immediately',
      () {
        fakeAsync((async) {
          var unreachableFired = false;
          late LifecycleClient client;
          late List<RemoteService> services;
          late FakeBlueyPlatform fakePlatform;

          _setUpConnectedClient(
            maxFailedHeartbeats: 1,
            onServerUnreachable: () => unreachableFired = true,
          ).then((setup) {
            client = setup.client;
            services = setup.services;
            fakePlatform = setup.fakePlatform;
          });
          async.flushMicrotasks();

          client.start(allServices: services);
          async.flushMicrotasks();

          // Initial heartbeat succeeds. Now enable failures.
          fakePlatform.simulateWriteFailure = true;

          // First periodic heartbeat fails -- should trigger immediately.
          async.elapse(const Duration(seconds: 5));
          async.flushMicrotasks();

          expect(unreachableFired, isTrue);
          expect(client.isRunning, isFalse);

          fakePlatform.simulateWriteFailure = false;
        });
      },
    );

    // 15. non-timeout heartbeat error does NOT increment failure count
    test(
      'non-timeout heartbeat error does NOT increment failure counter',
      () {
        fakeAsync((async) {
          var unreachableFired = false;
          late LifecycleClient client;
          late List<RemoteService> services;
          late FakeBlueyPlatform fakePlatform;

          _setUpConnectedClient(
            maxFailedHeartbeats: 1,
            onServerUnreachable: () => unreachableFired = true,
          ).then((setup) {
            client = setup.client;
            services = setup.services;
            fakePlatform = setup.fakePlatform;
          });
          async.flushMicrotasks();

          client.start(allServices: services);
          async.flushMicrotasks();

          // Initial heartbeat succeeded. Now simulate a non-timeout error
          // (e.g. another GATT op in flight on Android).
          fakePlatform.simulateWriteFailure = true;

          // Even with maxFailedHeartbeats=1, ten consecutive non-timeout
          // errors should NOT trigger onServerUnreachable.
          for (var i = 0; i < 10; i++) {
            async.elapse(const Duration(seconds: 5));
            async.flushMicrotasks();
          }

          expect(unreachableFired, isFalse,
              reason: 'Non-timeout errors are transient and must be ignored');
          expect(client.isRunning, isTrue,
              reason: 'Heartbeat must keep running through non-timeout errors');

          fakePlatform.simulateWriteFailure = false;
          client.stop();
        });
      },
    );

    // 16. timeout heartbeat error DOES increment failure count
    test(
      'timeout heartbeat error fires onServerUnreachable after threshold',
      () {
        fakeAsync((async) {
          var unreachableFired = false;
          late LifecycleClient client;
          late List<RemoteService> services;
          late FakeBlueyPlatform fakePlatform;

          _setUpConnectedClient(
            maxFailedHeartbeats: 2,
            onServerUnreachable: () => unreachableFired = true,
          ).then((setup) {
            client = setup.client;
            services = setup.services;
            fakePlatform = setup.fakePlatform;
          });
          async.flushMicrotasks();

          client.start(allServices: services);
          async.flushMicrotasks();

          fakePlatform.simulateWriteTimeout = true;

          // Timeout 1 — below threshold
          async.elapse(const Duration(seconds: 5));
          async.flushMicrotasks();
          expect(unreachableFired, isFalse);

          // Timeout 2 — at threshold, should fire
          async.elapse(const Duration(seconds: 5));
          async.flushMicrotasks();
          expect(unreachableFired, isTrue);
          expect(client.isRunning, isFalse);

          fakePlatform.simulateWriteTimeout = false;
        });
      },
    );

    // 17. mixed timeouts and non-timeouts: only timeouts count
    test(
      'mixed timeouts and non-timeouts: only timeouts count toward threshold',
      () {
        fakeAsync((async) {
          var unreachableFired = false;
          late LifecycleClient client;
          late List<RemoteService> services;
          late FakeBlueyPlatform fakePlatform;

          _setUpConnectedClient(
            maxFailedHeartbeats: 3,
            onServerUnreachable: () => unreachableFired = true,
          ).then((setup) {
            client = setup.client;
            services = setup.services;
            fakePlatform = setup.fakePlatform;
          });
          async.flushMicrotasks();

          client.start(allServices: services);
          async.flushMicrotasks();

          // Timeout 1
          fakePlatform.simulateWriteTimeout = true;
          async.elapse(const Duration(seconds: 5));
          async.flushMicrotasks();
          expect(unreachableFired, isFalse);

          // 5 non-timeout failures interleaved — must NOT advance the counter
          fakePlatform.simulateWriteTimeout = false;
          fakePlatform.simulateWriteFailure = true;
          for (var i = 0; i < 5; i++) {
            async.elapse(const Duration(seconds: 5));
            async.flushMicrotasks();
          }
          expect(unreachableFired, isFalse,
              reason: 'Non-timeout errors must not advance the counter');
          fakePlatform.simulateWriteFailure = false;

          // Timeout 2
          fakePlatform.simulateWriteTimeout = true;
          async.elapse(const Duration(seconds: 5));
          async.flushMicrotasks();
          expect(unreachableFired, isFalse);

          // Timeout 3 — threshold
          async.elapse(const Duration(seconds: 5));
          async.flushMicrotasks();
          expect(unreachableFired, isTrue);

          fakePlatform.simulateWriteTimeout = false;
        });
      },
    );
  });
}

// ==========================================================================
// Minimal RemoteService / RemoteCharacteristic implementations for testing.
//
// LifecycleClient only inspects service/characteristic UUIDs (via
// toString().toLowerCase()) and calls _platform.readCharacteristic /
// _platform.writeCharacteristic directly. These wrappers satisfy the
// interface without pulling in the full BlueyConnection machinery.
// ==========================================================================

class _TestRemoteService implements RemoteService {
  final platform.PlatformService _ps;
  final FakeBlueyPlatform _fakePlatform;
  final String _connectionId;

  _TestRemoteService(this._ps, this._fakePlatform, this._connectionId);

  @override
  UUID get uuid => UUID(_ps.uuid);

  @override
  bool get isPrimary => _ps.isPrimary;

  @override
  List<RemoteCharacteristic> get characteristics => _ps.characteristics
      .map((pc) => _TestRemoteCharacteristic(pc, _fakePlatform, _connectionId))
      .toList();

  @override
  List<RemoteService> get includedServices => _ps.includedServices
      .map((ps) => _TestRemoteService(ps, _fakePlatform, _connectionId))
      .toList();

  @override
  RemoteCharacteristic characteristic(UUID uuid) {
    for (final c in characteristics) {
      if (c.uuid == uuid) return c;
    }
    throw CharacteristicNotFoundException(uuid);
  }
}

class _TestRemoteCharacteristic implements RemoteCharacteristic {
  final platform.PlatformCharacteristic _pc;
  final FakeBlueyPlatform _fakePlatform;
  final String _connectionId;

  _TestRemoteCharacteristic(
      this._pc, this._fakePlatform, this._connectionId);

  @override
  UUID get uuid => UUID(_pc.uuid);

  @override
  CharacteristicProperties get properties => CharacteristicProperties(
        canRead: _pc.properties.canRead,
        canWrite: _pc.properties.canWrite,
        canWriteWithoutResponse: _pc.properties.canWriteWithoutResponse,
        canNotify: _pc.properties.canNotify,
        canIndicate: _pc.properties.canIndicate,
      );

  @override
  Future<Uint8List> read() =>
      _fakePlatform.readCharacteristic(_connectionId, _pc.uuid);

  @override
  Future<void> write(Uint8List value, {bool withResponse = true}) =>
      _fakePlatform.writeCharacteristic(
          _connectionId, _pc.uuid, value, withResponse);

  @override
  Stream<Uint8List> get notifications => const Stream.empty();

  @override
  RemoteDescriptor descriptor(UUID uuid) =>
      throw UnimplementedError('Not needed for lifecycle tests');

  @override
  List<RemoteDescriptor> get descriptors => const [];
}
