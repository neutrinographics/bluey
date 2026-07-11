import 'dart:typed_data';

import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_platform.dart';
import 'test_helpers.dart';

/// I347 — the Android role-reversal ATT blackhole, injectable.
///
/// The documented condition (cross-platform-quirks.md §"Android stops
/// delivering GATT-server requests..."): the connection looks healthy,
/// but the server silently never receives its clients' requests — they
/// hang at the sender until the per-op timeout. With
/// `simulateServerRequestBlackhole` the fake reproduces that fingerprint
/// so the death watch's convergence is provable.
void main() {
  group('simulateServerRequestBlackhole', () {
    test('a blackholed write never reaches the server and times out at the '
        'sender', () {
      fakeAsync((async) {
        final fakePlatform = FakeBlueyPlatform();
        platform.BlueyPlatform.instance = fakePlatform;
        late Bluey bluey;
        Bluey.create().then((b) => bluey = b);
        async.flushMicrotasks();
        final server = bluey.server()!;
        server.startAdvertising(name: 'blackhole');
        async.flushMicrotasks();
        fakePlatform.simulateCentralConnection(
          centralId: TestDeviceIds.central1,
        );
        async.flushMicrotasks();

        final seen = <WriteRequest>[];
        server.writeRequests.listen(seen.add);

        fakePlatform.simulateServerRequestBlackhole(TestDeviceIds.central1);

        Object? error;
        fakePlatform
            .simulateWriteRequest(
              centralId: TestDeviceIds.central1,
              characteristicUuid: TestUuids.heartRateMeasurement,
              value: Uint8List.fromList([0x01]),
            )
            .catchError((Object e) {
          error = e;
        });
        async.flushMicrotasks();

        expect(seen, isEmpty, reason: 'the request vanished at the stack');
        expect(error, isNull, reason: 'the sender hangs, it does not fail');

        // The sender's per-op timeout is what finally fires.
        async.elapse(const Duration(seconds: 11));
        expect(error, isA<platform.GattOperationTimeoutException>());
        expect(seen, isEmpty);

        server.dispose();
        bluey.dispose();
        fakePlatform.dispose();
        async.flushMicrotasks();
      });
    });

    test('E2E over a real link: the blackhole starves the death watch into '
        'declaring the peer unreachable (the I208 fingerprint)', () {
      fakeAsync((async) {
        final serverFake = FakeBlueyPlatform();
        platform.BlueyPlatform.instance = serverFake;
        late Bluey serverBluey;
        Bluey.create(localIdentity: TestServerIds.remoteIdentity)
            .then((b) => serverBluey = b);
        async.flushMicrotasks();
        final server = serverBluey.server()!;

        final clientFake = FakeBlueyPlatform();
        platform.BlueyPlatform.instance = clientFake;
        late Bluey clientBluey;
        Bluey.create(localIdentity: TestServerIds.localIdentity)
            .then((b) => clientBluey = b);
        async.flushMicrotasks();

        final link = FakeBleLink(
          central: clientFake,
          peripheral: serverFake,
          deviceId: 'blackhole-server',
          centralId: 'blackhole-client',
        );

        server.startAdvertising(name: 'victim');
        async.flushMicrotasks();
        link.announce();

        PeerConnection? peer;
        clientBluey
            .connectAsPeer(
              Device(address: const DeviceAddress('blackhole-server')),
            )
            .then((p) => peer = p);
        async.elapse(const Duration(seconds: 1));
        expect(peer, isNotNull, reason: 'healthy connect before the blackhole');

        final unreachable = <PeerDeclaredUnreachableEvent>[];
        clientBluey.events
            .where((e) => e is PeerDeclaredUnreachableEvent)
            .cast<PeerDeclaredUnreachableEvent>()
            .listen(unreachable.add);

        // Roles reversed on a still-live link: the server stops
        // receiving this central's requests entirely.
        serverFake.simulateServerRequestBlackhole('blackhole-client');

        // Heartbeat probes hang for their full 10 s timeout, fail as
        // dead-peer signals, and the death watch (30 s) tears down.
        async.elapse(const Duration(seconds: 90));

        expect(unreachable, hasLength(1));
        expect(peer!.connection.state, ConnectionState.disconnected);

        server.dispose();
        serverBluey.dispose();
        clientBluey.dispose();
        serverFake.dispose();
        clientFake.dispose();
        async.flushMicrotasks();
      });
    });
  });
}
