import 'dart:async';
import 'dart:typed_data';

import 'package:bluey/bluey.dart';
import 'package:bluey/src/lifecycle.dart' as lifecycle;
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';
import '../fakes/test_helpers.dart';

/// I068 — pins the contract that lifecycle-protocol state transitions
/// surface on `bluey.events` for programmatic monitoring.
///
/// Six new events:
///
///   * Client side:
///     - HeartbeatSentEvent — every probe write.
///     - HeartbeatAcknowledgedEvent — every successful ack.
///     - HeartbeatFailedEvent — on probe error (with isDeadPeerSignal flag).
///     - PeerDeclaredUnreachableEvent — silence detector trips.
///   * Server side:
///     - LifecyclePausedForPendingRequestEvent — first pending request
///       on a tracked client (transitions timer from active to paused).
///     - ClientLifecycleTimeoutEvent — client's heartbeat timer expires.
///
/// Tests use [fakeAsync] to drive the heartbeat / silence clocks
/// deterministically, mirroring `lifecycle_client_test.dart` and the
/// I079 pending-request tests in `bluey_server_test.dart`.
void main() {
  const deviceAddress = 'AA:BB:CC:DD:EE:01';
  final deviceId = UUID('00000000-0000-0000-0000-aabbccddee01');

  group('Client-side lifecycle events on bluey.events (I068)', () {
    test('HeartbeatSentEvent fires on every probe write; '
        'HeartbeatAcknowledgedEvent fires on every successful ack', () {
      fakeAsync((async) {
        final fakePlatform = FakeBlueyPlatform();
        platform.BlueyPlatform.instance = fakePlatform;

        final serverId = ServerId.generate();
        fakePlatform.simulateBlueyServer(
          address: deviceAddress,
          serverId: serverId,
          intervalValue: const Duration(seconds: 10),
        );

        final bluey = Bluey(localIdentity: TestServerIds.localIdentity);
        final eventLog = <BlueyEvent>[];
        bluey.events.listen(eventLog.add);

        late PeerConnection peerConn;
        bluey
            .peer(serverId, peerSilenceTimeout: const Duration(seconds: 30))
            .connect(scanTimeout: const Duration(milliseconds: 200))
            .then((c) => peerConn = c);
        async.elapse(const Duration(milliseconds: 300));
        async.flushMicrotasks();

        // Initial heartbeat fires during start(), then periodic at 5s
        // (interval=10s ÷ 2). Advance 12s to capture initial + 2 periodic.
        async.elapse(const Duration(seconds: 12));
        async.flushMicrotasks();

        final sent = eventLog.whereType<HeartbeatSentEvent>().toList();
        final acked = eventLog.whereType<HeartbeatAcknowledgedEvent>().toList();
        expect(
          sent,
          isNotEmpty,
          reason: 'at least one HeartbeatSentEvent expected',
        );
        expect(
          acked,
          isNotEmpty,
          reason: 'at least one HeartbeatAcknowledgedEvent expected',
        );
        // Sent count must equal or exceed acked count (each successful
        // ack corresponds to a prior send).
        expect(sent.length, greaterThanOrEqualTo(acked.length));
        for (final e in sent) {
          expect(e.deviceId, equals(deviceId));
        }
        for (final e in acked) {
          expect(e.deviceId, equals(deviceId));
        }

        peerConn.disconnect().catchError((_) {});
        async.flushMicrotasks();
        bluey.dispose();
      });
    });

    test('HeartbeatFailedEvent(isDeadPeerSignal: true) fires on '
        'GattOperationTimeoutException', () {
      fakeAsync((async) {
        final fakePlatform = FakeBlueyPlatform();
        platform.BlueyPlatform.instance = fakePlatform;

        final serverId = ServerId.generate();
        fakePlatform.simulateBlueyServer(
          address: deviceAddress,
          serverId: serverId,
          intervalValue: const Duration(seconds: 10),
        );

        final bluey = Bluey(localIdentity: TestServerIds.localIdentity);
        final eventLog = <BlueyEvent>[];
        bluey.events.listen(eventLog.add);

        late PeerConnection peerConn;
        bluey
            .peer(serverId, peerSilenceTimeout: const Duration(seconds: 30))
            .connect(scanTimeout: const Duration(milliseconds: 200))
            .then((c) => peerConn = c);
        async.elapse(const Duration(milliseconds: 300));
        async.flushMicrotasks();

        // Inject timeout failures starting after the initial heartbeat
        // succeeded (so the lifecycle is fully started).
        fakePlatform.simulateWriteTimeout = true;
        async.elapse(const Duration(seconds: 6));
        async.flushMicrotasks();

        final failed = eventLog.whereType<HeartbeatFailedEvent>().toList();
        expect(failed, isNotEmpty);
        expect(
          failed.first.isDeadPeerSignal,
          isTrue,
          reason: 'GattOperationTimeoutException is a dead-peer signal',
        );
        expect(failed.first.deviceId, equals(deviceId));

        fakePlatform.simulateWriteTimeout = false;
        peerConn.disconnect().catchError((_) {});
        async.flushMicrotasks();
        bluey.dispose();
      });
    });

    test('HeartbeatFailedEvent(isDeadPeerSignal: false) fires on '
        'transient (non-dead-peer) error', () {
      fakeAsync((async) {
        final fakePlatform = FakeBlueyPlatform();
        platform.BlueyPlatform.instance = fakePlatform;

        final serverId = ServerId.generate();
        fakePlatform.simulateBlueyServer(
          address: deviceAddress,
          serverId: serverId,
          intervalValue: const Duration(seconds: 10),
        );

        final bluey = Bluey(localIdentity: TestServerIds.localIdentity);
        final eventLog = <BlueyEvent>[];
        bluey.events.listen(eventLog.add);

        late PeerConnection peerConn;
        bluey
            .peer(serverId, peerSilenceTimeout: const Duration(seconds: 30))
            .connect(scanTimeout: const Duration(milliseconds: 200))
            .then((c) => peerConn = c);
        async.elapse(const Duration(milliseconds: 300));
        async.flushMicrotasks();

        // simulateWriteFailure produces a generic non-dead-peer error.
        fakePlatform.simulateWriteFailure = true;
        async.elapse(const Duration(seconds: 6));
        async.flushMicrotasks();

        final failed = eventLog.whereType<HeartbeatFailedEvent>().toList();
        expect(failed, isNotEmpty);
        expect(
          failed.first.isDeadPeerSignal,
          isFalse,
          reason: 'transient errors must not be tagged as dead-peer signals',
        );

        fakePlatform.simulateWriteFailure = false;
        peerConn.disconnect().catchError((_) {});
        async.flushMicrotasks();
        bluey.dispose();
      });
    });

    test('PeerDeclaredUnreachableEvent fires when silence detector trips', () {
      fakeAsync((async) {
        final fakePlatform = FakeBlueyPlatform();
        platform.BlueyPlatform.instance = fakePlatform;

        final serverId = ServerId.generate();
        fakePlatform.simulateBlueyServer(
          address: deviceAddress,
          serverId: serverId,
          intervalValue: const Duration(seconds: 10),
        );

        final bluey = Bluey(localIdentity: TestServerIds.localIdentity);
        final eventLog = <BlueyEvent>[];
        bluey.events.listen(eventLog.add);

        late PeerConnection peerConn;
        bluey
            .peer(serverId, peerSilenceTimeout: const Duration(seconds: 8))
            .connect(scanTimeout: const Duration(milliseconds: 200))
            .then((c) => peerConn = c);
        async.elapse(const Duration(milliseconds: 300));
        async.flushMicrotasks();

        // Force timeouts so the silence detector arms; advance past the
        // 8s peerSilenceTimeout window.
        fakePlatform.simulateWriteTimeout = true;
        async.elapse(const Duration(seconds: 20));
        async.flushMicrotasks();

        final unreachable =
            eventLog.whereType<PeerDeclaredUnreachableEvent>().toList();
        expect(
          unreachable,
          hasLength(1),
          reason: 'silence detector should have tripped exactly once',
        );
        expect(unreachable.single.deviceId, equals(deviceId));

        fakePlatform.simulateWriteTimeout = false;
        peerConn.disconnect().catchError((_) {});
        async.flushMicrotasks();
        bluey.dispose();
      });
    });
  });

  group('Server-side lifecycle events on bluey.events (I068)', () {
    test('LifecyclePausedForPendingRequestEvent fires when first pending '
        'request lands on a tracked client', () async {
      final fakePlatform = FakeBlueyPlatform();
      platform.BlueyPlatform.instance = fakePlatform;

      final bluey = Bluey(localIdentity: TestServerIds.localIdentity);
      final server = bluey.server()!;

      const clientId = '00000000-0000-0000-0000-000000000001';
      const userCharUuid = '12345678-1234-1234-1234-123456789abd';

      await server.addService(
        HostedService(
          uuid: UUID('12345678-1234-1234-1234-123456789abc'),
          isPrimary: true,
          characteristics: [
            HostedCharacteristic(
              uuid: UUID(userCharUuid),
              properties: const CharacteristicProperties(
                canRead: true,
                canWrite: true,
              ),
              permissions: const [GattPermission.read, GattPermission.write],
            ),
          ],
        ),
      );
      await server.startAdvertising();

      fakePlatform.simulateCentralConnection(centralId: clientId);

      final eventLog = <BlueyEvent>[];
      final eventSub = bluey.events.listen(eventLog.add);

      // First, send a heartbeat write so the client is tracked by the
      // lifecycle layer. Untracked clients are not paused.
      await fakePlatform.simulateWriteRequest(
        centralId: clientId,
        characteristicUuid: lifecycle.heartbeatCharUuid,
        value: heartbeatPayloadFrom(TestServerIds.remoteIdentity),
        responseNeeded: true,
      );
      await Future<void>.delayed(Duration.zero);

      // Listen for write requests; respond is what would normally drain
      // the pending request, so just observing the request is enough to
      // see the pause edge.
      server.writeRequests.listen((_) {});

      // Send a write-with-response on a user characteristic. This
      // marks the client's pending-request set non-empty for the first
      // time, transitioning the timer from active to paused. We don't
      // respond to the write — `simulateWriteRequest` only resolves
      // when `respondToWriteRequest` fires, so we deliberately leak the
      // future via `unawaited` and assert on the pause emission instead.
      unawaited(
        fakePlatform.simulateWriteRequest(
          centralId: clientId,
          characteristicUuid: userCharUuid,
          value: Uint8List.fromList([0xAB]),
          responseNeeded: true,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await eventSub.cancel();

      final paused =
          eventLog.whereType<LifecyclePausedForPendingRequestEvent>().toList();
      expect(
        paused,
        hasLength(1),
        reason: 'first pending request should fire pause event exactly once',
      );
      expect(paused.single.clientId, equals(clientId));

      await server.dispose();
      await bluey.dispose();
    });

    test('ClientLifecycleTimeoutEvent fires when heartbeat timer expires', () {
      fakeAsync((async) {
        final fakePlatform = FakeBlueyPlatform();
        platform.BlueyPlatform.instance = fakePlatform;

        final bluey = Bluey(localIdentity: TestServerIds.localIdentity);
        // Short interval so the timer expires quickly under fakeAsync.
        final server =
            bluey.server(lifecycleInterval: const Duration(seconds: 5))!;
        const clientId = '00000000-0000-0000-0000-000000000002';

        server.addService(
          HostedService(
            uuid: UUID('12345678-1234-1234-1234-123456789abc'),
            isPrimary: true,
            characteristics: const [],
          ),
        );
        server.startAdvertising();
        async.flushMicrotasks();

        fakePlatform.simulateCentralConnection(centralId: clientId);
        async.flushMicrotasks();

        final eventLog = <BlueyEvent>[];
        bluey.events.listen(eventLog.add);

        // Send one heartbeat write so the client is tracked. After this,
        // the lifecycle server starts a 5s timer.
        fakePlatform.simulateWriteRequest(
          centralId: clientId,
          characteristicUuid: lifecycle.heartbeatCharUuid,
          value: heartbeatPayloadFrom(TestServerIds.remoteIdentity),
          responseNeeded: true,
        );
        async.flushMicrotasks();

        // Advance past the 5s lifecycle interval — the timer should fire.
        async.elapse(const Duration(seconds: 6));
        async.flushMicrotasks();

        final timedOut =
            eventLog.whereType<ClientLifecycleTimeoutEvent>().toList();
        expect(timedOut, hasLength(1));
        expect(timedOut.single.clientId, equals(clientId));

        server.dispose();
        bluey.dispose();
      });
    });
  });
}
