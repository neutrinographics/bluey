import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';
import '../fakes/test_helpers.dart';

/// I349 — peer connect must not wait out the full scan window.
///
/// `connectTo` used to collect-then-probe: `await` the entire scan
/// timeout before probing any candidate, so every peer connect had a
/// hard scan-window floor (5 s by default) even when the target
/// advertised instantly. Probe-as-you-scan probes candidates as the
/// scan emits them and completes on the first identity match; the scan
/// timeout bounds only the *failure* path.
void main() {
  ({FakeBlueyPlatform fake, Bluey bluey}) boot(FakeAsync async) {
    final fake = FakeBlueyPlatform();
    platform.BlueyPlatform.instance = fake;
    late Bluey bluey;
    Bluey.create(localIdentity: TestServerIds.localIdentity)
        .then((b) => bluey = b);
    async.flushMicrotasks();
    return (fake: fake, bluey: bluey);
  }

  test('connect completes as soon as the target is discovered and probed — '
      'not at the end of the scan window', () {
    fakeAsync((async) {
      final env = boot(async);
      env.fake.simulateBlueyServer(
        address: 'INSTANT-PEER',
        serverId: TestServerIds.remoteIdentity,
      );

      PeerConnection? peer;
      env.bluey
          .peer(TestServerIds.remoteIdentity)
          .connect(scanTimeout: const Duration(seconds: 5))
          .then((p) => peer = p);

      // Well under the 5 s window: the candidate advertises instantly
      // and the probe is instant in the fake, so a small slice of
      // virtual time must be enough.
      async.elapse(const Duration(milliseconds: 500));
      expect(
        peer,
        isNotNull,
        reason: 'probe-as-you-scan must not wait out the scan window',
      );
      expect(peer!.serverId, equals(TestServerIds.remoteIdentity));
      expect(
        env.fake.isScanning,
        isFalse,
        reason: 'the scan stops once the match is found',
      );

      peer!.disconnect();
      env.bluey.dispose();
      env.fake.dispose();
      async.flushMicrotasks();
    });
  });

  test('a wrong-identity candidate is probed, rejected, and disconnected; '
      'the right one connects — still within the window', () {
    fakeAsync((async) {
      final env = boot(async);
      env.fake.simulateBlueyServer(
        address: 'WRONG-PEER',
        serverId: TestServerIds.thirdParty,
      );
      env.fake.simulateBlueyServer(
        address: 'RIGHT-PEER',
        serverId: TestServerIds.remoteIdentity,
      );

      PeerConnection? peer;
      env.bluey
          .peer(TestServerIds.remoteIdentity)
          .connect(scanTimeout: const Duration(seconds: 5))
          .then((p) => peer = p);

      async.elapse(const Duration(milliseconds: 500));
      expect(peer, isNotNull);
      expect(
        peer!.connection.deviceAddress,
        const DeviceAddress('RIGHT-PEER'),
      );
      expect(
        env.fake.connectedDeviceIds,
        equals(['RIGHT-PEER']),
        reason: 'the rejected probe connection was torn down',
      );

      peer!.disconnect();
      env.bluey.dispose();
      env.fake.dispose();
      async.flushMicrotasks();
    });
  });

  test('no match still fails with PeerNotFoundException exactly at the '
      'scan timeout (the failure bound is unchanged)', () {
    fakeAsync((async) {
      final env = boot(async);
      env.fake.simulateBlueyServer(
        address: 'WRONG-PEER',
        serverId: TestServerIds.thirdParty,
      );

      Object? error;
      env.bluey
          .peer(TestServerIds.remoteIdentity)
          .connect(scanTimeout: const Duration(seconds: 5))
          .then<void>((_) => fail('must not connect'))
          .catchError((Object e) {
        error = e;
      });

      async.elapse(const Duration(milliseconds: 4900));
      expect(error, isNull, reason: 'still inside the scan window');
      async.elapse(const Duration(milliseconds: 200));
      expect(error, isA<PeerNotFoundException>());

      env.bluey.dispose();
      env.fake.dispose();
      async.flushMicrotasks();
    });
  });
}
