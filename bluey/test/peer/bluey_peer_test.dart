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

        // Use a short peerSilenceTimeout so the test doesn't need to advance
        // a full 20 seconds after the first failure.
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
        // First failure at ~T=5s arms the death watch for T=5+8=13s.
        // Advance 20s to ensure the death watch fires, plus give time for
        // the cascading async disconnect operations to complete.
        async.elapse(const Duration(seconds: 20));
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
