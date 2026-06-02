import 'dart:typed_data';

import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    show BlueyPlatform, PlatformGattStatus;
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';

const _mac = 'AA:BB:CC:DD:EE:FF';
const _someCharUuid = '0000fff1-0000-1000-8000-00805f9b34fb';
const _interval = Duration(seconds: 5);

// -----------------------------------------------------------------------------
// I338 Stage 2 — server chokepoint: requests are serviced only within an
// *established session* (a real `centralConnections` connect). A request from
// a session-less client is evicted with the reserved
// `PlatformGattStatus.lifecycleEviction` status and never reaches the app.
//
// Modelling a session-less-but-transport-live client in the fake: connect the
// central (establishes the session), then let the lifecycle silence timer fire
// on the inferring (iOS-like) path — Stage 1 removes the domain session
// (`_connectedClients.remove`) while the fake's transport bookkeeping
// (`_connectedCentrals`) stays alive. A request injected afterwards is exactly
// the iOS "paused-then-resumed peer" trap: the transport is up but the domain
// session is gone, so the server must evict.
// -----------------------------------------------------------------------------

void main() {
  test(
    'inferring server: a write from a session-less client is rejected with '
    'the reserved status and NOT forwarded',
    () async {
      final fake = FakeBlueyPlatform(reportsCentralDisconnects: false);
      BlueyPlatform.instance = fake;
      final bluey = await Bluey.create();
      fakeAsync((async) {
        final server = bluey.server(lifecycleInterval: _interval)!;
        server.startAdvertising(name: 't');
        async.flushMicrotasks();

        final forwarded = <WriteRequest>[];
        server.writeRequests.listen(forwarded.add);

        // Establish a session, then let silence remove it (inferring path).
        fake.simulateCentralConnection(centralId: _mac);
        async.flushMicrotasks();
        fake.fireLifecycleSilence(_mac);
        async.flushMicrotasks();
        async.elapse(_interval); // silence fires → domain session removed
        async.flushMicrotasks();

        // Transport is still live in the fake, but no domain session.
        fake
            .simulateWriteRequest(
              centralId: _mac,
              characteristicUuid: _someCharUuid,
              value: Uint8List.fromList([1, 2, 3]),
            )
            .catchError((_) {});
        async.flushMicrotasks();

        expect(
          forwarded,
          isEmpty,
          reason: 'no session → not dispatched to app',
        );
        expect(
          fake.respondWriteCalls.last.status,
          PlatformGattStatus.lifecycleEviction,
        );

        server.dispose();
        bluey.dispose();
      });
    },
  );

  test(
    'inferring server: a read from a session-less client is rejected with '
    'the reserved status',
    () async {
      final fake = FakeBlueyPlatform(reportsCentralDisconnects: false);
      BlueyPlatform.instance = fake;
      final bluey = await Bluey.create();
      fakeAsync((async) {
        final server = bluey.server(lifecycleInterval: _interval)!;
        server.startAdvertising(name: 't');
        async.flushMicrotasks();

        final reads = <ReadRequest>[];
        server.readRequests.listen(reads.add);

        fake.simulateCentralConnection(centralId: _mac);
        async.flushMicrotasks();
        fake.fireLifecycleSilence(_mac);
        async.flushMicrotasks();
        async.elapse(_interval);
        async.flushMicrotasks();

        fake
            .simulateReadRequest(
              centralId: _mac,
              characteristicUuid: _someCharUuid,
            )
            .catchError((_) => Uint8List(0));
        async.flushMicrotasks();

        expect(reads, isEmpty);
        expect(
          fake.respondReadCalls.last.status,
          PlatformGattStatus.lifecycleEviction,
        );

        server.dispose();
        bluey.dispose();
      });
    },
  );

  test(
    'a session-less heartbeat does NOT re-create the client or re-emit '
    'peerConnections',
    () async {
      final fake = FakeBlueyPlatform(reportsCentralDisconnects: false);
      BlueyPlatform.instance = fake;
      final bluey = await Bluey.create();
      fakeAsync((async) {
        final server = bluey.server(lifecycleInterval: _interval)!;
        server.startAdvertising(name: 't');
        async.flushMicrotasks();

        final peers = <PeerClient>[];
        server.peerConnections.listen(peers.add);

        fake.fireLifecycleSilence(_mac); // heartbeat from an unknown client
        async.flushMicrotasks();

        expect(
          peers,
          isEmpty,
          reason: 'no session → heartbeat rejected, not identified',
        );
        expect(
          server.isClientConnected(const ClientAddress(_mac)),
          isFalse,
        );

        server.dispose();
        bluey.dispose();
      });
    },
  );

  test('an established client (real connect) is serviced normally', () async {
    final fake = FakeBlueyPlatform(reportsCentralDisconnects: false);
    BlueyPlatform.instance = fake;
    final bluey = await Bluey.create();
    fakeAsync((async) {
      final server = bluey.server(lifecycleInterval: _interval)!;
      server.startAdvertising(name: 't');
      async.flushMicrotasks();

      final forwarded = <WriteRequest>[];
      server.writeRequests.listen(forwarded.add);

      fake.simulateCentralConnection(centralId: _mac); // establishes session
      async.flushMicrotasks();

      fake.simulateWriteRequest(
        centralId: _mac,
        characteristicUuid: _someCharUuid,
        value: Uint8List.fromList([9]),
        responseNeeded: false,
      );
      async.flushMicrotasks();

      expect(
        forwarded,
        hasLength(1),
        reason: 'established session → dispatched',
      );

      server.dispose();
      bluey.dispose();
    });
  });

  test(
    'I338 contract: inferring server — silence-then-resume is rejected, '
    'forcing reconnect (cannot continue mid-stream)',
    () async {
      final fake = FakeBlueyPlatform(reportsCentralDisconnects: false);
      BlueyPlatform.instance = fake;
      final bluey = await Bluey.create();
      fakeAsync((async) {
        final server = bluey.server(lifecycleInterval: _interval)!;
        server.startAdvertising(name: 't');
        async.flushMicrotasks();

        final forwarded = <WriteRequest>[];
        server.writeRequests.listen(forwarded.add);

        // 1. Real connect → established session.
        fake.simulateCentralConnection(centralId: _mac);
        async.flushMicrotasks();

        // 2. Heartbeat silence removes the domain session (Stage 1 inferring
        //    path).
        fake.fireLifecycleSilence(_mac);
        async.flushMicrotasks();
        async.elapse(_interval);
        async.flushMicrotasks();
        expect(server.isClientConnected(const ClientAddress(_mac)), isFalse);

        // 3. Peer "resumes" mid-stream with an app write → MUST be rejected,
        //    not forwarded.
        fake
            .simulateWriteRequest(
              centralId: _mac,
              characteristicUuid: _someCharUuid,
              value: Uint8List.fromList([0xAA, 0xBB]),
            )
            .catchError((_) {});
        async.flushMicrotasks();

        expect(
          forwarded,
          isEmpty,
          reason: 'resumed write from a removed session must not reach the app',
        );
        expect(
          fake.respondWriteCalls.last.status,
          PlatformGattStatus.lifecycleEviction,
        );

        server.dispose();
        bluey.dispose();
      });
    },
  );

  test('reset-on-init: a surviving native-announced central is re-announced, '
      'so the fresh server re-establishes its session (not evicted)', () async {
    final fake = FakeBlueyPlatform(reportsCentralDisconnects: false);
    BlueyPlatform.instance = fake;
    final bluey = await Bluey.create();
    // A central the native side still tracks but the new Dart server has not
    // heard of.
    fake.simulateSurvivingAnnouncedCentral(_mac);
    fakeAsync((async) {
      final server =
          bluey.server(lifecycleInterval: _interval)!; // resetServerSessions()
      server.startAdvertising(name: 't');
      async.flushMicrotasks();

      // On reset, the fake re-announces survivors via centralConnections.
      expect(server.isClientConnected(const ClientAddress(_mac)), isTrue,
          reason: 'survivor re-announced → session re-established, not evicted');

      server.dispose();
      bluey.dispose();
    });
  });
}
