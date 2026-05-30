import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';

/// Short lifecycle interval used in these tests so the silence timer
/// fires after a predictable `async.elapse` call.
const _silenceInterval = Duration(seconds: 5);

/// MAC address used as the simulated central in both tests.
const _mac = 'AA:BB:CC:DD:EE:FF';

void main() {
  // -------------------------------------------------------------------------
  // I338 Stage 1: silence timeout branching on reportsCentralDisconnects
  //
  // On authoritative platforms (reportsCentralDisconnects == true, e.g.
  // Android) the heartbeat silence is advisory — the platform's
  // onConnectionStateChange remains the sole source of `disconnections`.
  // On inferring platforms (reportsCentralDisconnects == false, e.g. iOS)
  // the silence IS the disconnect signal.
  // -------------------------------------------------------------------------

  test(
    'I338: authoritative platform — silence does NOT emit disconnections',
    () async {
      // reportsCentralDisconnects == true (Capabilities.fake default)
      final fake = FakeBlueyPlatform();
      BlueyPlatform.instance = fake;
      final bluey = await Bluey.create();

      fakeAsync((async) {
        final server =
            bluey.server(lifecycleInterval: _silenceInterval)!;

        server.startAdvertising(name: 't');
        async.flushMicrotasks();

        final gone = <ClientAddress>[];
        server.disconnections.listen(gone.add);

        // A central connects.
        fake.simulateCentralConnection(centralId: _mac);
        async.flushMicrotasks();

        // Arm the silence timer by sending a heartbeat write.
        // `fireLifecycleSilence` sends the heartbeat that starts the timer;
        // advancing fake time fires the silence timeout.
        fake.fireLifecycleSilence(_mac);
        async.flushMicrotasks();

        // Fire the silence timer.
        async.elapse(_silenceInterval);

        expect(
          gone,
          isEmpty,
          reason:
              'silence is advisory on authoritative platforms — '
              'the platform disconnect callback is the sole source of '
              'disconnections; silence must not emit.',
        );
        expect(
          server.isClientConnected(const ClientAddress(_mac)),
          isTrue,
          reason:
              'client remains tracked until the platform fires a real '
              'central-disconnect event.',
        );

        server.dispose();
        bluey.dispose();
      });
    },
  );

  test(
    'I338: inferring platform — silence DOES emit disconnections '
    '(current iOS behaviour)',
    () async {
      // reportsCentralDisconnects == false → iOS-like inferring platform
      final fake = FakeBlueyPlatform(reportsCentralDisconnects: false);
      BlueyPlatform.instance = fake;
      final bluey = await Bluey.create();

      fakeAsync((async) {
        final server =
            bluey.server(lifecycleInterval: _silenceInterval)!;

        server.startAdvertising(name: 't');
        async.flushMicrotasks();

        final gone = <ClientAddress>[];
        server.disconnections.listen(gone.add);

        // A central connects.
        fake.simulateCentralConnection(centralId: _mac);
        async.flushMicrotasks();

        // Arm the silence timer.
        fake.fireLifecycleSilence(_mac);
        async.flushMicrotasks();

        // Fire the silence timer — on an inferring platform this should
        // propagate to the full disconnect path.
        async.elapse(_silenceInterval);

        expect(
          gone,
          equals([const ClientAddress(_mac)]),
          reason:
              'silence is the authoritative disconnect signal on '
              'inferring platforms (iOS has no central-disconnect callback).',
        );

        server.dispose();
        bluey.dispose();
      });
    },
  );
}
