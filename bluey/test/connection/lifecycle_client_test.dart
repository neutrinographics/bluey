import 'dart:typed_data';

import 'package:bluey/bluey.dart';
import 'package:bluey/src/connection/lifecycle_client.dart';
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
  Duration peerSilenceTimeout = const Duration(seconds: 20),
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
    peerSilenceTimeout: peerSilenceTimeout,
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
        peerSilenceTimeout: const Duration(seconds: 20),
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
          peerSilenceTimeout: const Duration(seconds: 20),
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
          peerSilenceTimeout: const Duration(seconds: 20),
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
            peerSilenceTimeout: const Duration(seconds: 20),
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

    // 12. heartbeat success resets the death watch
    test('heartbeat success resets the death watch', () {
      fakeAsync((async) {
        var unreachableFired = false;
        late LifecycleClient client;
        late List<RemoteService> services;
        late FakeBlueyPlatform fakePlatform;

        // peerSilenceTimeout = 30s; heartbeat interval = 5s (10s server / 2).
        // The first failure arms the death watch at T+30s. After a success,
        // the death watch is cancelled and must be re-armed from scratch on the
        // next failure. We verify that the callback does NOT fire within 20s
        // of the success (less than one full peerSilenceTimeout from the reset).
        _setUpConnectedClient(
          peerSilenceTimeout: const Duration(seconds: 30),
          onServerUnreachable: () => unreachableFired = true,
        ).then((setup) {
          client = setup.client;
          services = setup.services;
          fakePlatform = setup.fakePlatform;
        });
        async.flushMicrotasks();

        client.start(allServices: services);
        async.flushMicrotasks();

        // Arm the death watch: first failure at ~T=5s.
        fakePlatform.simulateWriteTimeout = true;
        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();
        expect(unreachableFired, isFalse,
            reason: 'Death watch is armed but not yet expired');

        // One success clears _firstFailureAt and cancels the death timer.
        fakePlatform.simulateWriteTimeout = false;
        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();

        // Now fail again — the death watch resets from now. We should NOT
        // trip within the next 20s because 20s < peerSilenceTimeout (30s).
        fakePlatform.simulateWriteTimeout = true;
        async.elapse(const Duration(seconds: 20));
        async.flushMicrotasks();

        expect(unreachableFired, isFalse,
            reason: 'Success must have reset the death watch; '
                'new 30s window is not yet expired at 20s');

        fakePlatform.simulateWriteTimeout = false;
        client.stop();
      });
    });

    // 13. heartbeat failure fires onServerUnreachable after peerSilenceTimeout
    test(
      'heartbeat failure fires onServerUnreachable after peerSilenceTimeout',
      () {
        fakeAsync((async) {
          var unreachableFired = false;
          late LifecycleClient client;
          late List<RemoteService> services;
          late FakeBlueyPlatform fakePlatform;

          // peerSilenceTimeout = 30s; heartbeat interval = 5s (10s server / 2).
          // Equivalent spirit to the old 3-failure test: ~3 probes at 5s each
          // corresponds to 15s of silence, but we use 30s to be explicit about
          // the time-based contract.
          _setUpConnectedClient(
            peerSilenceTimeout: const Duration(seconds: 30),
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
          fakePlatform.simulateWriteTimeout = true;

          // First failure at ~T=5s arms the death watch for T=5+30=35s.
          // Advance 33s — the first probe fires at T=5 so we're safely before
          // the 35s deadline.
          async.elapse(const Duration(seconds: 33));
          async.flushMicrotasks();
          expect(unreachableFired, isFalse,
              reason: 'peerSilenceTimeout not yet elapsed');

          // Advance 4 more seconds — now past the 35s deadline.
          async.elapse(const Duration(seconds: 4));
          async.flushMicrotasks();
          expect(unreachableFired, isTrue,
              reason: 'peerSilenceTimeout elapsed — onServerUnreachable must fire');
          expect(client.isRunning, isFalse,
              reason: 'stop() should have been called internally');

          fakePlatform.simulateWriteTimeout = false;
        });
      },
    );

    // 14. heartbeat failure fires onServerUnreachable after a short peerSilenceTimeout
    test(
      'heartbeat failure fires onServerUnreachable after a short peerSilenceTimeout',
      () {
        fakeAsync((async) {
          var unreachableFired = false;
          late LifecycleClient client;
          late List<RemoteService> services;
          late FakeBlueyPlatform fakePlatform;

          // Use a short 8s timeout: the first failure at ~5s arms the watch,
          // which fires 8s later at ~13s total.
          _setUpConnectedClient(
            peerSilenceTimeout: const Duration(seconds: 8),
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
          fakePlatform.simulateWriteTimeout = true;

          // First failure at T=5s arms the death watch; timeout at T=5+8=13s.
          async.elapse(const Duration(seconds: 5));
          async.flushMicrotasks();
          expect(unreachableFired, isFalse,
              reason: 'death watch armed but not yet expired');

          // Advance past the 8s timeout.
          async.elapse(const Duration(seconds: 9));
          async.flushMicrotasks();
          expect(unreachableFired, isTrue);
          expect(client.isRunning, isFalse);

          fakePlatform.simulateWriteTimeout = false;
        });
      },
    );

    // 15. non-timeout heartbeat error does NOT arm the death watch
    test(
      'non-timeout heartbeat error does NOT arm the death watch',
      () {
        fakeAsync((async) {
          var unreachableFired = false;
          late LifecycleClient client;
          late List<RemoteService> services;
          late FakeBlueyPlatform fakePlatform;

          // Short peerSilenceTimeout: if non-timeout errors incorrectly armed
          // the death watch, onServerUnreachable would fire within 10s.
          _setUpConnectedClient(
            peerSilenceTimeout: const Duration(seconds: 10),
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

          // Ten consecutive non-timeout errors across 50s of simulated time
          // must NOT trigger onServerUnreachable regardless of peerSilenceTimeout.
          for (var i = 0; i < 10; i++) {
            async.elapse(const Duration(seconds: 5));
            async.flushMicrotasks();
          }

          expect(unreachableFired, isFalse,
              reason: 'Non-timeout errors are transient and must not arm the death watch');
          expect(client.isRunning, isTrue,
              reason: 'Heartbeat must keep running through non-timeout errors');

          fakePlatform.simulateWriteFailure = false;
          client.stop();
        });
      },
    );

    // 16. timeout heartbeat error DOES arm the death watch and fires after peerSilenceTimeout
    test(
      'timeout heartbeat error fires onServerUnreachable after peerSilenceTimeout',
      () {
        fakeAsync((async) {
          var unreachableFired = false;
          late LifecycleClient client;
          late List<RemoteService> services;
          late FakeBlueyPlatform fakePlatform;

          // peerSilenceTimeout = 12s; heartbeat interval = 5s.
          // First timeout at ~5s arms the watch; fires at ~5+12=17s.
          _setUpConnectedClient(
            peerSilenceTimeout: const Duration(seconds: 12),
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

          // First timeout — arms the death watch; not yet expired.
          async.elapse(const Duration(seconds: 5));
          async.flushMicrotasks();
          expect(unreachableFired, isFalse,
              reason: 'death watch armed but not yet expired');

          // Advance past peerSilenceTimeout — death watch fires.
          async.elapse(const Duration(seconds: 13));
          async.flushMicrotasks();
          expect(unreachableFired, isTrue);
          expect(client.isRunning, isFalse);

          fakePlatform.simulateWriteTimeout = false;
        });
      },
    );

    // 17. mixed timeouts and non-timeouts: only timeouts arm the death watch
    test(
      'mixed timeouts and non-timeouts: only timeouts arm the death watch',
      () {
        fakeAsync((async) {
          var unreachableFired = false;
          late LifecycleClient client;
          late List<RemoteService> services;
          late FakeBlueyPlatform fakePlatform;

          // peerSilenceTimeout = 20s. A timeout at ~5s arms the watch;
          // non-timeout errors in between must not reset _firstFailureAt
          // or re-arm the timer. Death watch fires at ~5+20=25s.
          _setUpConnectedClient(
            peerSilenceTimeout: const Duration(seconds: 20),
            onServerUnreachable: () => unreachableFired = true,
          ).then((setup) {
            client = setup.client;
            services = setup.services;
            fakePlatform = setup.fakePlatform;
          });
          async.flushMicrotasks();

          client.start(allServices: services);
          async.flushMicrotasks();

          // First timeout at ~5s arms the death watch.
          fakePlatform.simulateWriteTimeout = true;
          async.elapse(const Duration(seconds: 5));
          async.flushMicrotasks();
          expect(unreachableFired, isFalse,
              reason: 'death watch armed, not yet expired');

          // Switch to non-timeout errors — these must NOT reset _firstFailureAt
          // or cancel the death watch. Advance 10s through non-timeout noise.
          fakePlatform.simulateWriteTimeout = false;
          fakePlatform.simulateWriteFailure = true;
          async.elapse(const Duration(seconds: 10));
          async.flushMicrotasks();
          expect(unreachableFired, isFalse,
              reason: 'Non-timeout errors must not cancel or reset the death watch');
          fakePlatform.simulateWriteFailure = false;

          // Another timeout while death watch is already armed — the watch
          // deadline stays at _firstFailureAt + 20s, unchanged.
          fakePlatform.simulateWriteTimeout = true;
          async.elapse(const Duration(seconds: 5));
          async.flushMicrotasks();
          expect(unreachableFired, isFalse,
              reason: 'Death watch deadline should not have moved');

          // Advance past the original deadline (started at ~5s, timeout=20s →
          // fires at 25s total; we're now at ~20s; need 6 more seconds).
          async.elapse(const Duration(seconds: 6));
          async.flushMicrotasks();
          expect(unreachableFired, isTrue,
              reason: 'Original death watch (from first timeout) must have fired');

          fakePlatform.simulateWriteTimeout = false;
        });
      },
    );

    // 20a. GattOperationStatusFailedException (e.g. GATT_INVALID_HANDLE)
    // counts as dead-peer signal — this is the Android-client→iOS-server
    // force-kill path, where Service Changed on the peer side invalidates
    // the characteristic handle and every subsequent heartbeat write
    // returns status 0x01.
    test(
      'GattOperationStatusFailedException trips onServerUnreachable',
      () {
        fakeAsync((async) {
          var unreachableFired = false;
          late LifecycleClient client;
          late List<RemoteService> services;
          late FakeBlueyPlatform fakePlatform;

          _setUpConnectedClient(
            peerSilenceTimeout: const Duration(seconds: 8),
            onServerUnreachable: () => unreachableFired = true,
          ).then((setup) {
            client = setup.client;
            services = setup.services;
            fakePlatform = setup.fakePlatform;
          });
          async.flushMicrotasks();

          client.start(allServices: services);
          async.flushMicrotasks();

          fakePlatform.simulateWriteStatusFailed = 0x01;

          // First failure at ~5s arms the death watch; fires at ~5+8=13s.
          async.elapse(const Duration(seconds: 14));
          async.flushMicrotasks();
          expect(unreachableFired, isTrue);
          expect(client.isRunning, isFalse);

          fakePlatform.simulateWriteStatusFailed = null;
        });
      },
    );

    // 20. GattOperationDisconnectedException counts as dead-peer signal.
    //
    // Symmetric with Phase 2a's Android queue drain: when a pending heartbeat
    // is drained by `queue.drainAll(gatt-disconnected)` during a mid-op link
    // loss, the heartbeat should treat it as proof of peer absence rather
    // than a transient error.
    test(
      'GattOperationDisconnectedException trips onServerUnreachable',
      () {
        fakeAsync((async) {
          var unreachableFired = false;
          late LifecycleClient client;
          late List<RemoteService> services;
          late FakeBlueyPlatform fakePlatform;

          _setUpConnectedClient(
            peerSilenceTimeout: const Duration(seconds: 8),
            onServerUnreachable: () => unreachableFired = true,
          ).then((setup) {
            client = setup.client;
            services = setup.services;
            fakePlatform = setup.fakePlatform;
          });
          async.flushMicrotasks();

          client.start(allServices: services);
          async.flushMicrotasks();

          fakePlatform.simulateWriteDisconnected = true;

          // First failure at ~5s arms the death watch; fires at ~5+8=13s.
          async.elapse(const Duration(seconds: 14));
          async.flushMicrotasks();
          expect(unreachableFired, isTrue);
          expect(client.isRunning, isFalse);

          fakePlatform.simulateWriteDisconnected = false;
        });
      },
    );

    // 21. Unrecognized PlatformException code is still ignored (safety net).
    //
    // Complement to test #15: the counter must not react to exotic platform
    // errors that have no defined "peer is dead" meaning. Only the known
    // dead-peer codes (notFound/notConnected) should trip.
    test(
      'unrecognized PlatformException code does NOT trip counter',
      () {
        fakeAsync((async) {
          var unreachableFired = false;
          late LifecycleClient client;
          late List<RemoteService> services;
          late FakeBlueyPlatform fakePlatform;

          _setUpConnectedClient(
            peerSilenceTimeout: const Duration(seconds: 10),
            onServerUnreachable: () => unreachableFired = true,
          ).then((setup) {
            client = setup.client;
            services = setup.services;
            fakePlatform = setup.fakePlatform;
          });
          async.flushMicrotasks();

          client.start(allServices: services);
          async.flushMicrotasks();

          fakePlatform.simulateWritePlatformErrorCode = 'something-unrelated';

          // 5 unrecognized errors across 25s — death watch must not be armed.
          for (var i = 0; i < 5; i++) {
            async.elapse(const Duration(seconds: 5));
            async.flushMicrotasks();
          }
          expect(unreachableFired, isFalse);
          expect(client.isRunning, isTrue);

          fakePlatform.simulateWritePlatformErrorCode = null;
          client.stop();
        });
      },
    );

    test('recordActivity cancels the death watch', () {
      fakeAsync((async) {
        var unreachableFired = false;
        late LifecycleClient client;
        late List<RemoteService> services;
        late FakeBlueyPlatform fakePlatform;

        // peerSilenceTimeout = 15s; heartbeat interval = 5s.
        _setUpConnectedClient(
          peerSilenceTimeout: const Duration(seconds: 15),
          onServerUnreachable: () => unreachableFired = true,
        ).then((setup) {
          client = setup.client;
          services = setup.services;
          fakePlatform = setup.fakePlatform;
        });
        async.flushMicrotasks();

        client.start(allServices: services);
        async.flushMicrotasks();

        // First heartbeat succeeds in the initial send. Now cause
        // timeouts and have activity rescue the connection.
        fakePlatform.simulateWriteTimeout = true;

        // First timeout at ~5s arms the death watch (fires at ~5+15=20s).
        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();
        expect(unreachableFired, isFalse,
            reason: 'death watch armed but not yet expired');

        // User op success → recordActivity cancels the death watch and
        // resets _firstFailureAt. A fresh 15s window starts from here.
        client.recordActivity();

        // Advance 14s — new death watch (if re-armed by subsequent failure)
        // should not have expired yet, and the old one was cancelled.
        async.elapse(const Duration(seconds: 14));
        async.flushMicrotasks();
        expect(unreachableFired, isFalse,
            reason: 'recordActivity cancelled the watch; new window not expired');

        // The first post-reset probe fails at T=10 (T=5+5s window), arming a
        // fresh death watch for T=10+15=25s. We are at T=5+14=19s. Advance 7s
        // more to reach T=26s > 25s, past the fresh deadline.
        async.elapse(const Duration(seconds: 7));
        async.flushMicrotasks();
        expect(unreachableFired, isTrue,
            reason: 'Fresh death watch from post-reset failure must eventually fire');

        fakePlatform.simulateWriteTimeout = false;
      });
    });

    test('recordActivity within probe interval skips next probe send', () {
      fakeAsync((async) {
        late LifecycleClient client;
        late List<RemoteService> services;
        late FakeBlueyPlatform fakePlatform;

        _setUpConnectedClient(
          onServerUnreachable: () {},
        ).then((setup) {
          client = setup.client;
          services = setup.services;
          fakePlatform = setup.fakePlatform;
        });
        async.flushMicrotasks();

        client.start(allServices: services);
        async.flushMicrotasks();

        // Advance partway through the probe interval so activity is
        // recorded mid-window, not at a tick boundary.
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
        fakePlatform.writeCharacteristicCalls.clear();

        // Activity at T=2s; next tick at T=5s sees difference=3s < 5s window.
        client.recordActivity();
        async.elapse(const Duration(seconds: 3));
        async.flushMicrotasks();

        final heartbeatWrites = fakePlatform.writeCharacteristicCalls.where(
          (c) => c.characteristicUuid == lifecycle.heartbeatCharUuid,
        );
        expect(heartbeatWrites, isEmpty,
            reason: 'activity within window should cause probe tick to skip');

        client.stop();
      });
    });

    test(
      'I077 regression: recordActivity reschedules probe to exactly '
      'activityWindow from now (not next periodic tick)',
      () {
        fakeAsync((async) {
          late LifecycleClient client;
          late List<RemoteService> services;
          late FakeBlueyPlatform fakePlatform;

          // Set up the full connected lifecycle client (10s server interval →
          // 5s client heartbeat window).
          _setUpConnectedClient(
            onServerUnreachable: () {},
          ).then((setup) {
            client = setup.client;
            services = setup.services;
            fakePlatform = setup.fakePlatform;
          });
          async.flushMicrotasks();

          client.start(allServices: services);

          // Let the start() sequence settle: initial probe + interval read +
          // schedule the first periodic/one-shot timer. After this elapse,
          // the initial probe has written, completed, and recorded activity.
          async.elapse(const Duration(milliseconds: 100));
          async.flushMicrotasks();
          final initialProbeCount = fakePlatform.writeCharacteristicCalls.length;
          expect(initialProbeCount, greaterThanOrEqualTo(1),
              reason: 'start() should have issued the initial probe');

          // At T=3s, simulate a user op completing. recordActivity must
          // reset the deadline so the next probe is due at T=3+5 = 8s.
          async.elapse(const Duration(seconds: 3));
          async.flushMicrotasks();
          client.recordActivity();

          // Advance to T=5s total. Activity at T=3 reset the deadline to
          // T=8, so no probe has fired yet — deadline is still in the future.
          async.elapse(const Duration(seconds: 2));
          async.flushMicrotasks();
          expect(
            fakePlatform.writeCharacteristicCalls.length,
            initialProbeCount,
            reason: 'At T=5s, deadline is T=8 so no probe yet',
          );

          // Advance to T=8s total. Deadline reached — one probe fires exactly
          // at recordActivity + activityWindow, not at some fixed tick interval.
          async.elapse(const Duration(seconds: 3));
          async.flushMicrotasks();
          expect(
            fakePlatform.writeCharacteristicCalls.length,
            initialProbeCount + 1,
            reason: 'Deadline-driven scheduler must probe at '
                'recordActivity + activityWindow, not at the next periodic tick',
          );

          client.stop();
        });
      },
    );

    test('start() is idempotent when interval-read is in flight', () {
      fakeAsync((async) {
        late LifecycleClient client;
        late FakeBlueyPlatform fakePlatform;
        late List<RemoteService> services;

        _setUpConnectedClient(onServerUnreachable: () {}).then((fixture) {
          client = fixture.client;
          services = fixture.services;
          fakePlatform = fixture.fakePlatform;
        });
        async.flushMicrotasks();

        fakePlatform.holdNextReadCharacteristic();

        client.start(allServices: services);
        async.flushMicrotasks();
        // First start dispatched the initial heartbeat write and the interval read.
        final writesAfterFirst = fakePlatform.writeCharacteristicCalls.length;
        final readsAfterFirst = fakePlatform.readCharacteristicCalls.length;

        // Second start() before the interval-read resolves — must be a no-op.
        client.start(allServices: services);
        async.flushMicrotasks();

        expect(fakePlatform.writeCharacteristicCalls.length, writesAfterFirst,
            reason: 'second start() must not dispatch another heartbeat write');
        expect(fakePlatform.readCharacteristicCalls.length, readsAfterFirst,
            reason: 'second start() must not dispatch another interval-read');
        expect(client.isRunning, isTrue);

        // Clean up the held future so fakeAsync doesn't complain.
        fakePlatform.resolveHeldRead(lifecycle.encodeInterval(const Duration(seconds: 10)));
        async.flushMicrotasks();
        client.stop();
      });
    });

    // I070: interval-read callbacks must not mutate monitor state after stop().
    //
    // The pre-existing _heartbeatCharUuid == null guard already blocks probe
    // writes, but _beginHeartbeat calls _monitor.updateActivityWindow BEFORE
    // _scheduleProbe. Without the _isRunning guard added in the production
    // fix, a late .then callback would silently mutate activityWindow on a
    // stopped client. The .catchError branch shares the same guard pattern;
    // a single test on the .then path drives both guards.
    test(
      'I070: interval-read success after stop() does not mutate monitor activityWindow',
      () {
        fakeAsync((async) {
          late LifecycleClient client;
          late FakeBlueyPlatform fakePlatform;
          late List<RemoteService> services;

          // Use intervalValue: 12s so the fixture interval (12s → 6s half)
          // differs from the client's hardcoded default (5s). The monitor is
          // initialised at 5s and stays there until the interval-read resolves.
          _setUpConnectedClient(
            onServerUnreachable: () {},
            intervalValue: const Duration(seconds: 12),
          ).then((fixture) {
            client = fixture.client;
            services = fixture.services;
            fakePlatform = fixture.fakePlatform;
          });
          async.flushMicrotasks();

          fakePlatform.holdNextReadCharacteristic();
          client.start(allServices: services);
          async.flushMicrotasks();

          // Capture pre-stop() state: activityWindow is still the client's
          // default (5s) because the interval-read is still pending.
          final windowBefore = client.activityWindowForTest;
          final writesBefore = fakePlatform.writeCharacteristicCalls.length;

          client.stop();
          async.flushMicrotasks();

          // Late interval-read succeeds with a DIFFERENT value: 8s → 4s half.
          // Without the guard, _beginHeartbeat would call
          // _monitor.updateActivityWindow(4s), mutating state on a stopped client.
          fakePlatform.resolveHeldRead(
              lifecycle.encodeInterval(const Duration(seconds: 8)));
          async.flushMicrotasks();

          // Any armed timer would fire within 60 s.
          async.elapse(const Duration(seconds: 60));
          async.flushMicrotasks();

          expect(client.isRunning, isFalse);
          expect(
            client.activityWindowForTest,
            windowBefore,
            reason:
                'stopped client must not have its monitor mutated by a late interval-read',
          );
          expect(
            fakePlatform.writeCharacteristicCalls.length,
            writesBefore,
            reason: 'no probe may dispatch after stop()',
          );
        });
      },
    );

    test('I070: probe-write success after stop() does not mutate monitor activity', () {
      fakeAsync((async) {
        late LifecycleClient client;
        late FakeBlueyPlatform fakePlatform;
        late List<RemoteService> services;

        _setUpConnectedClient(onServerUnreachable: () {}).then((fixture) {
          client = fixture.client;
          services = fixture.services;
          fakePlatform = fixture.fakePlatform;
        });
        async.flushMicrotasks();

        client.start(allServices: services);
        async.flushMicrotasks();

        // Fixture defaults intervalValue to 10s → heartbeat interval = 5s.
        // Elapse 6s so the probe timer fires and dispatches. Hold the
        // probe-write so stop() can happen while the write is in flight.
        fakePlatform.holdNextWriteCharacteristic();
        async.elapse(const Duration(seconds: 6));
        async.flushMicrotasks();

        final activityBefore = client.lastActivityAtForTest;

        client.stop();
        async.flushMicrotasks();

        // Late success resolves after stop. Without the .then guard,
        // _monitor.recordProbeSuccess() would mutate _lastActivityAt.
        fakePlatform.resolveHeldWrite();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 60));
        async.flushMicrotasks();

        expect(client.isRunning, isFalse);
        expect(client.lastActivityAtForTest, activityBefore,
            reason: 'late probe success must not refresh the activity timestamp after stop()');
      });
    });

    test('I070: probe-write transient failure after stop() does not mutate monitor', () {
      fakeAsync((async) {
        late LifecycleClient client;
        late FakeBlueyPlatform fakePlatform;
        late List<RemoteService> services;

        _setUpConnectedClient(onServerUnreachable: () {}).then((fixture) {
          client = fixture.client;
          services = fixture.services;
          fakePlatform = fixture.fakePlatform;
        });
        async.flushMicrotasks();

        client.start(allServices: services);
        async.flushMicrotasks();

        fakePlatform.holdNextWriteCharacteristic();
        async.elapse(const Duration(seconds: 6));
        async.flushMicrotasks();

        final activityBefore = client.lastActivityAtForTest;
        final writesBefore = fakePlatform.writeCharacteristicCalls.length;

        client.stop();
        async.flushMicrotasks();

        // Transient (non-dead-peer) error — e.g. a platform-layer Exception.
        fakePlatform.failHeldWrite(Exception('transient platform error'));
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 60));
        async.flushMicrotasks();

        expect(client.isRunning, isFalse);
        // The transient-failure branch, without the guard, would call
        // _monitor.cancelProbe() (no-op post-stop since stop() already did)
        // and _scheduleProbe (also no-op since _heartbeatCharUuid is null).
        // Neither currently mutates _lastActivityAt, so the timestamp
        // assertion below is defense-in-depth: it locks in that future
        // additions to the transient branch won't sneak past the guard.
        expect(client.lastActivityAtForTest, activityBefore,
            reason: 'late transient-failure path must not refresh activity timestamp after stop()');
        expect(fakePlatform.writeCharacteristicCalls.length, writesBefore);
      });
    });

    test('I070: probe-write dead-peer failure after stop() does not fire onServerUnreachable', () {
      fakeAsync((async) {
        var unreachableCalls = 0;
        late LifecycleClient client;
        late FakeBlueyPlatform fakePlatform;
        late List<RemoteService> services;

        _setUpConnectedClient(
          onServerUnreachable: () => unreachableCalls++,
        ).then((fixture) {
          client = fixture.client;
          services = fixture.services;
          fakePlatform = fixture.fakePlatform;
        });
        async.flushMicrotasks();

        client.start(allServices: services);
        async.flushMicrotasks();

        fakePlatform.holdNextWriteCharacteristic();
        async.elapse(const Duration(seconds: 6));
        async.flushMicrotasks();

        client.stop();
        async.flushMicrotasks();

        // Dead-peer signal. Without the guard the late .catchError invokes
        // recordPeerFailure (→ death watch armed) → onServerUnreachable.
        fakePlatform.failHeldWrite(
          const platform.GattOperationTimeoutException('writeCharacteristic'),
        );
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 60));
        async.flushMicrotasks();

        expect(unreachableCalls, 0,
            reason: 'onServerUnreachable must not fire after stop()');
      });
    });

    test('stop() releases in-flight probe so monitor does not strand probeInFlight', () {
      fakeAsync((async) {
        late LifecycleClient client;
        late FakeBlueyPlatform fakePlatform;
        late List<RemoteService> services;

        _setUpConnectedClient(onServerUnreachable: () {}).then((fixture) {
          client = fixture.client;
          services = fixture.services;
          fakePlatform = fixture.fakePlatform;
        });
        async.flushMicrotasks();

        // Start normally so interval-read resolves and the probe timer is armed.
        client.start(allServices: services);
        async.flushMicrotasks();

        // Fixture defaults intervalValue to 10s → heartbeat interval = 5s.
        // Elapse 6s so the probe timer fires and dispatches.
        fakePlatform.holdNextWriteCharacteristic();
        async.elapse(const Duration(seconds: 6));
        async.flushMicrotasks();

        // Sanity: a probe is now in flight.
        expect(client.probeInFlightForTest, isTrue,
            reason: 'probe should be in flight after tick + dispatch');

        // Call stop() while the write is still pending.
        client.stop();

        // Assert: probeInFlight is released synchronously even though
        // the write future has not resolved.
        expect(client.probeInFlightForTest, isFalse,
            reason: 'stop() must release the monitor in-flight flag');

        // Clean up the held future so fakeAsync doesn't complain.
        fakePlatform.resolveHeldWrite();
        async.flushMicrotasks();
      });
    });

    test('start() with no control service leaves _isRunning false and is retryable', () async {
      final fakePlatform = FakeBlueyPlatform();
      platform.BlueyPlatform.instance = fakePlatform;

      // First: a regular (non-Bluey) device with no control service.
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

      final platformServicesNoControl =
          await fakePlatform.discoverServices(_deviceAddress);
      final domainServicesNoControl = platformServicesNoControl
          .map((ps) => _TestRemoteService(ps, fakePlatform, _deviceAddress))
          .toList();

      final client = LifecycleClient(
        platformApi: fakePlatform,
        connectionId: _deviceAddress,
        peerSilenceTimeout: const Duration(seconds: 20),
        onServerUnreachable: () {},
      );

      client.start(
          allServices: List<RemoteService>.from(domainServicesNoControl));

      // No control service found — start() must NOT commit to running.
      expect(client.isRunning, isFalse,
          reason: 'start() without a control service must not commit');

      // Disconnect, re-simulate the same address as a full Bluey server,
      // reconnect, re-discover. This gives us a fresh services list that
      // includes the control service.
      await fakePlatform.disconnect(_deviceAddress);
      fakePlatform.simulateBlueyServer(
        address: _deviceAddress,
        serverId: ServerId.generate(),
      );
      await fakePlatform.connect(
        _deviceAddress,
        const platform.PlatformConnectConfig(timeoutMs: null, mtu: null),
      );
      final platformServicesWithControl =
          await fakePlatform.discoverServices(_deviceAddress);
      final domainServicesWithControl = platformServicesWithControl
          .map((ps) => _TestRemoteService(ps, fakePlatform, _deviceAddress))
          .toList();

      client.start(
          allServices: List<RemoteService>.from(domainServicesWithControl));

      expect(client.isRunning, isTrue,
          reason: 'retry with control service must succeed');

      client.stop();
    });

    test('start() unwinds fully when writeCharacteristic throws synchronously', () async {
      final fixture = await _setUpConnectedClient(onServerUnreachable: () {});
      final client = fixture.client;
      final fakePlatform = fixture.fakePlatform;
      final services = fixture.services;

      fakePlatform.simulateSyncWriteThrow = true;

      Object? caught;
      try {
        client.start(allServices: services);
      } catch (e) {
        caught = e;
      }

      expect(caught, isA<StateError>(),
          reason: 'synchronous throw must propagate out of start()');
      expect(client.isRunning, isFalse,
          reason: '_isRunning must be cleared on sync-throw unwind');
      expect(client.probeInFlightForTest, isFalse,
          reason: 'monitor probeInFlight must be released');

      // A second start() with a healthy platform must be able to run.
      fakePlatform.simulateSyncWriteThrow = false;
      client.start(allServices: services);
      expect(client.isRunning, isTrue);

      client.stop();
    });

    test('I078: recordActivity during interval-read window shifts the probe deadline', () {
      fakeAsync((async) {
        late LifecycleClient client;
        late FakeBlueyPlatform fakePlatform;
        late List<RemoteService> services;

        _setUpConnectedClient(onServerUnreachable: () {}).then((fixture) {
          client = fixture.client;
          services = fixture.services;
          fakePlatform = fixture.fakePlatform;
        });
        async.flushMicrotasks();

        fakePlatform.holdNextReadCharacteristic();

        client.start(allServices: services);
        async.flushMicrotasks();
        // T=0: initial heartbeat dispatched synchronously inside start().
        final writesAfterStart = fakePlatform.writeCharacteristicCalls.length;

        // T=3s: simulate a user GATT op completing INSIDE the interval-read
        // window. Without I078's fix this call would be dropped silently.
        async.elapse(const Duration(seconds: 3));
        client.recordActivity();
        async.flushMicrotasks();

        // Resolve the interval-read at T=3s with 10s interval → monitor
        // activityWindow becomes 5s (half). Probe deadline = _lastActivityAt
        // + activityWindow = T=3s + 5s = T=8s.
        fakePlatform.resolveHeldRead(
            lifecycle.encodeInterval(const Duration(seconds: 10)));
        async.flushMicrotasks();

        // Advance to T=7s (total elapsed 7s, so 4s more from T=3s). No
        // probe should have fired yet.
        async.elapse(const Duration(seconds: 4));
        async.flushMicrotasks();
        expect(fakePlatform.writeCharacteristicCalls.length, writesAfterStart,
            reason: 'recordActivity at T=3s must push probe deadline to T=8s');

        // Advance past T=8s → probe should now fire.
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
        expect(fakePlatform.writeCharacteristicCalls.length, writesAfterStart + 1,
            reason: 'probe fires at T=8s (activity at T=3s + window 5s)');

        client.stop();
      });
    });

    // I097 user-op tracking tests.

    // I097-1: probe is deferred while a user op is pending
    test('probe deferred while user op pending', () {
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
        // Let the interval-read settle and capture baseline.
        final heartbeatCharUuid = lifecycle.heartbeatCharUuid;

        // Clear writes from start (initial probe).
        fakePlatform.writeCharacteristicCalls.clear();

        // Signal that a user op has started — probes must be deferred.
        client.markUserOpStarted();

        // Advance 30s — well past the 5s heartbeat interval.
        async.elapse(const Duration(seconds: 30));
        async.flushMicrotasks();

        final heartbeatWrites = fakePlatform.writeCharacteristicCalls
            .where((c) =>
                c.characteristicUuid.toLowerCase() == heartbeatCharUuid)
            .length;
        expect(heartbeatWrites, equals(0),
            reason: 'probes must be deferred while a user op is pending');

        client.markUserOpEnded();
        client.stop();
      });
    });

    // I097-2: probe fires after user op ends
    test('probe fires after user op ends', () {
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

        client.markUserOpStarted();
        async.elapse(const Duration(seconds: 30));
        async.flushMicrotasks();

        client.markUserOpEnded();
        // After the op ends, the next scheduled tick should dispatch a probe.
        async.elapse(const Duration(seconds: 6));
        async.flushMicrotasks();

        final heartbeatWrites = fakePlatform.writeCharacteristicCalls.where(
          (c) => c.characteristicUuid.toLowerCase() == lifecycle.heartbeatCharUuid,
        );
        expect(heartbeatWrites, isNotEmpty,
            reason: 'probe should fire after user op ends');

        client.stop();
      });
    });

    // I097-3: multiple concurrent user ops are correctly counted
    test('multiple concurrent user ops correctly counted', () {
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

        // Two concurrent ops: count = 2.
        client.markUserOpStarted();
        client.markUserOpStarted();
        // End one: count drops to 1 — still deferred.
        client.markUserOpEnded();

        final writesBeforeWait = fakePlatform.writeCharacteristicCalls
            .where((c) =>
                c.characteristicUuid.toLowerCase() == lifecycle.heartbeatCharUuid)
            .length;

        async.elapse(const Duration(seconds: 30));
        async.flushMicrotasks();

        final writesAfterWait = fakePlatform.writeCharacteristicCalls
            .where((c) =>
                c.characteristicUuid.toLowerCase() == lifecycle.heartbeatCharUuid)
            .length;
        expect(writesAfterWait, equals(writesBeforeWait),
            reason: 'one op still pending — probes should be deferred');

        // End the second op: count = 0 — probes resume.
        client.markUserOpEnded();
        async.elapse(const Duration(seconds: 6));
        async.flushMicrotasks();

        expect(
          fakePlatform.writeCharacteristicCalls.where((c) =>
              c.characteristicUuid.toLowerCase() == lifecycle.heartbeatCharUuid),
          isNotEmpty,
          reason: 'probes must resume once all user ops have ended',
        );

        client.stop();
      });
    });

    // I097-4: recordUserOpFailure with a timeout feeds the silence detector
    test('recordUserOpFailure with timeout feeds the silence detector', () {
      fakeAsync((async) {
        var unreachable = false;
        late LifecycleClient client;
        late List<RemoteService> services;
        late FakeBlueyPlatform fakePlatform;

        _setUpConnectedClient(
          peerSilenceTimeout: const Duration(seconds: 10),
          onServerUnreachable: () => unreachable = true,
        ).then((setup) {
          client = setup.client;
          services = setup.services;
          fakePlatform = setup.fakePlatform;
        });
        async.flushMicrotasks();

        client.start(allServices: services);
        async.flushMicrotasks();

        // Make subsequent heartbeat probes also time out so that successful
        // probes do not reset the death watch that we're about to arm.
        fakePlatform.simulateWriteTimeout = true;

        // A user op times out — this should arm the death watch.
        client.recordUserOpFailure(
          const platform.GattOperationTimeoutException('writeCharacteristic'),
        );

        // Before peerSilenceTimeout: not yet fired.
        async.elapse(const Duration(seconds: 9));
        async.flushMicrotasks();
        expect(unreachable, isFalse,
            reason: 'peerSilenceTimeout not yet elapsed');

        // Past peerSilenceTimeout: death watch fires.
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
        expect(unreachable, isTrue,
            reason: 'timeout failure must arm the death watch');
      });
    });

    // I097-5: recordUserOpFailure with a non-timeout is a no-op for the silence detector
    test('recordUserOpFailure with non-timeout is a no-op', () {
      fakeAsync((async) {
        var unreachable = false;
        late LifecycleClient client;
        late List<RemoteService> services;

        _setUpConnectedClient(
          peerSilenceTimeout: const Duration(seconds: 10),
          onServerUnreachable: () => unreachable = true,
        ).then((setup) {
          client = setup.client;
          services = setup.services;
        });
        async.flushMicrotasks();

        client.start(allServices: services);
        async.flushMicrotasks();

        // A user op fails with a status error — NOT a timeout; must not arm
        // the death watch at this layer.
        client.recordUserOpFailure(
          const platform.GattOperationStatusFailedException(
              'writeCharacteristic', 0x03),
        );

        // Advance well past peerSilenceTimeout — no callback.
        async.elapse(const Duration(seconds: 30));
        async.flushMicrotasks();
        expect(unreachable, isFalse,
            reason: 'non-timeout failures must not arm the death watch via '
                'recordUserOpFailure');

        client.stop();
      });
    });
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
