import 'package:bluey/bluey.dart';
import 'package:bluey/src/lifecycle.dart';
import 'package:bluey/src/peer/bluey_peer.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';
import '../fakes/test_helpers.dart';

void main() {
  late FakeBlueyPlatform fakePlatform;

  setUp(() {
    fakePlatform = FakeBlueyPlatform();
    platform.BlueyPlatform.instance = fakePlatform;
  });

  group('BlueyPeer', () {
    test(
      'connect() returns a PeerConnection with control service hidden',
      () async {
        final id = ServerId.generate();
        fakePlatform.simulateBlueyServer(
          address: 'AA:BB:CC:DD:EE:01',
          serverId: id,
        );

        final peer = createBlueyPeer(
          platformApi: fakePlatform,
          serverId: id,
          logger: testLogger(),
        );
        final peerConn = await peer.connect();

        expect(peerConn, isA<PeerConnection>());
        expect(peerConn.serverId, equals(id));
        expect(peerConn.connection.state, ConnectionState.ready);
        final services = await peerConn.services();
        expect(
          services.any((s) => s.uuid.toString() == controlServiceUuid),
          isFalse,
        );

        await peerConn.disconnect();
      },
    );

    test('connect() throws PeerNotFoundException if no match', () async {
      fakePlatform.simulateBlueyServer(
        address: 'AA:BB:CC:DD:EE:01',
        serverId: ServerId.generate(),
      );

      final peer = createBlueyPeer(
        platformApi: fakePlatform,
        serverId: ServerId('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
        logger: testLogger(),
      );

      expect(
        () => peer.connect(scanTimeout: const Duration(milliseconds: 300)),
        throwsA(isA<PeerNotFoundException>()),
      );
    });

    test('disconnects when heartbeat write fails', () {
      fakeAsync((async) {
        final id = ServerId.generate();
        fakePlatform.simulateBlueyServer(
          address: 'AA:BB:CC:DD:EE:01',
          serverId: id,
        );

        // Post-C.6 the LifecycleClient lives inside `_BlueyPeer.connect`'s
        // wrapper (no longer attached to `BlueyConnection`). It is started
        // with the configured `peerSilenceTimeout` and drives the
        // unreachable-detection path that triggers the local disconnect.
        final peer = createBlueyPeer(
          platformApi: fakePlatform,
          serverId: id,
          peerSilenceTimeout: const Duration(seconds: 8),
          logger: testLogger(),
        );

        late PeerConnection peerConn;
        peer
            .connect(scanTimeout: const Duration(milliseconds: 500))
            .then((c) => peerConn = c);

        // The scan phase uses Stream.timeout which needs elapsed time
        // in fakeAsync to close the scan stream.
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();

        final states = <ConnectionState>[];
        peerConn.connection.stateChanges.listen(states.add);

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
        logger: testLogger(),
      );
      expect(peer.serverId, equals(id));
    });

    test('concurrent connect() throws StateError', () async {
      final id = ServerId.generate();
      fakePlatform.simulateBlueyServer(
        address: 'AA:BB:CC:DD:EE:01',
        serverId: id,
      );

      final peer = createBlueyPeer(
        platformApi: fakePlatform,
        serverId: id,
        logger: testLogger(),
      );

      // Start first connect (will be in flight)
      final first = peer.connect();

      // Second connect should throw
      expect(() => peer.connect(), throwsStateError);

      // Let the first one finish
      final peerConn = await first;
      await peerConn.disconnect();
    });
  });
}
