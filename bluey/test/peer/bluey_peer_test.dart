import 'package:bluey/bluey.dart';
import 'package:bluey/src/lifecycle.dart';
import 'package:bluey/src/peer/bluey_peer.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';

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
      fakePlatform.simulateBlueyServer(address: 'AA:BB:CC:DD:EE:01', serverId: id);

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
      fakePlatform.simulateBlueyServer(address: 'AA:BB:CC:DD:EE:01', serverId: ServerId.generate());

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
        fakePlatform.simulateBlueyServer(address: 'AA:BB:CC:DD:EE:01', serverId: id);

        // Note: this test actually exercises BlueyConnection's own
        // `_peerSilenceTimeout` (the lifecycle installed by `_tryUpgrade`
        // during `services()`), NOT the `createBlueyPeer` parameter.
        // `BlueyPeer.connect` reinstalls a second LifecycleClient via
        // `blueyConnection.upgrade(...)` but never starts it (the
        // post-upgrade `services()` already filtered out the control
        // service, so `LifecycleClient.start` finds no heartbeat char).
        // The OLD lifecycle leaks per I071 and is the one that fires.
        //
        // Until I071 is fixed, the timeout that actually matters here is
        // the BlueyConnection default — currently
        // `lifecycle.defaultPeerSilenceTimeout` (30 s).
        final peer = createBlueyPeer(
          platformApi: fakePlatform,
          serverId: id,
          peerSilenceTimeout: const Duration(seconds: 8),
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
        fakePlatform.simulateWriteTimeout = true;

        // Heartbeat interval is half the 10s lifecycle interval = 5s.
        // First probe failure at ~T=5s arms the OLD lifecycle's death
        // watch for T=5+30=35s. Advance to T~=40s plus drain so the
        // cascading async disconnect operations complete.
        async.elapse(const Duration(seconds: 40));
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 5));
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
      fakePlatform.simulateBlueyServer(address: 'AA:BB:CC:DD:EE:01', serverId: id);

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
