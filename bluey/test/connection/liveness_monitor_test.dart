import 'package:bluey/src/connection/liveness_monitor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DateTime fakeNow;
  LivenessMonitor buildMonitor({
    int maxFailedProbes = 1,
    Duration activityWindow = const Duration(seconds: 5),
  }) {
    fakeNow = DateTime.utc(2026, 1, 1);
    return LivenessMonitor(
      maxFailedProbes: maxFailedProbes,
      activityWindow: activityWindow,
      now: () => fakeNow,
    );
  }

  void advance(Duration d) => fakeNow = fakeNow.add(d);

  group('LivenessMonitor', () {
    test('shouldSendProbe is true initially (no activity yet)', () {
      final m = buildMonitor();
      expect(m.shouldSendProbe(), isTrue);
    });

    test('recordActivity then shouldSendProbe within window returns false', () {
      final m = buildMonitor();
      m.recordActivity();
      advance(const Duration(seconds: 3));
      expect(m.shouldSendProbe(), isFalse);
    });

    test('recordActivity then shouldSendProbe at window boundary returns true', () {
      final m = buildMonitor(activityWindow: const Duration(seconds: 5));
      m.recordActivity();
      advance(const Duration(seconds: 5));
      // Boundary is inclusive: a tick co-scheduled with the window
      // expiry must probe in time to beat the server's matching timer.
      expect(m.shouldSendProbe(), isTrue);
    });

    test('markProbeInFlight prevents shouldSendProbe from firing again', () {
      final m = buildMonitor();
      m.markProbeInFlight();
      expect(m.shouldSendProbe(), isFalse);
    });

    test('recordProbeSuccess clears in-flight flag and refreshes activity', () {
      final m = buildMonitor(activityWindow: const Duration(seconds: 5));
      m.markProbeInFlight();
      m.recordProbeSuccess();
      advance(const Duration(seconds: 3));
      // In-flight cleared AND activity refreshed.
      expect(m.shouldSendProbe(), isFalse);
      advance(const Duration(seconds: 3));
      expect(m.shouldSendProbe(), isTrue);
    });

    test('recordProbeFailure increments counter and releases in-flight', () {
      final m = buildMonitor(maxFailedProbes: 3);
      m.markProbeInFlight();
      final tripped = m.recordProbeFailure();
      expect(tripped, isFalse, reason: '1 failure < threshold 3');
      // In-flight cleared → next tick can probe.
      expect(m.shouldSendProbe(), isTrue);
    });

    test('recordProbeFailure returns true when threshold is reached', () {
      final m = buildMonitor(maxFailedProbes: 2);
      m.markProbeInFlight();
      expect(m.recordProbeFailure(), isFalse);
      m.markProbeInFlight();
      expect(m.recordProbeFailure(), isTrue);
    });

    test('recordActivity resets the failure counter', () {
      final m = buildMonitor(maxFailedProbes: 3);
      m.markProbeInFlight();
      m.recordProbeFailure(); // counter=1
      m.markProbeInFlight();
      m.recordProbeFailure(); // counter=2
      m.recordActivity(); // should reset to 0
      m.markProbeInFlight();
      final tripped = m.recordProbeFailure(); // counter back to 1, not 3
      expect(tripped, isFalse);
    });

    test('recordActivity during in-flight probe does not release flag', () {
      final m = buildMonitor();
      m.markProbeInFlight();
      m.recordActivity();
      // Activity recorded, counter reset — but in-flight flag still true.
      expect(m.shouldSendProbe(), isFalse);
      m.recordProbeSuccess();
      // Now the flag releases.
      expect(m.shouldSendProbe(), isFalse); // activity is recent
    });

    test('recordProbeSuccess on non-in-flight monitor is idempotent', () {
      final m = buildMonitor();
      // Defensive guard: success without a matching markProbeInFlight is
      // safe. No production call path exercises this today (non-dead-peer
      // errors use cancelProbe instead), but keeping idempotence avoids
      // asymmetry bugs if a future caller forgets to markProbeInFlight.
      expect(() => m.recordProbeSuccess(), returnsNormally);
    });

    test('cancelProbe releases the in-flight flag', () {
      final m = buildMonitor();
      m.markProbeInFlight();
      m.cancelProbe();
      expect(m.shouldSendProbe(), isTrue);
    });

    test('cancelProbe does NOT reset the failure counter', () {
      final m = buildMonitor(maxFailedProbes: 2);
      m.markProbeInFlight();
      m.recordProbeFailure(); // counter=1
      m.markProbeInFlight();
      m.cancelProbe(); // must not zero the counter
      m.markProbeInFlight();
      final tripped = m.recordProbeFailure(); // counter=2, tripped
      expect(tripped, isTrue,
          reason: 'cancelProbe must not reset the failure counter');
    });

    test('cancelProbe does NOT refresh the activity timestamp', () {
      final m = buildMonitor(activityWindow: const Duration(seconds: 5));
      m.recordActivity();
      advance(const Duration(seconds: 10));
      m.markProbeInFlight();
      m.cancelProbe();
      // 10s since last real activity — cancel must not have updated it.
      expect(m.shouldSendProbe(), isTrue);
    });

    test('updateActivityWindow preserves in-flight and counter state', () {
      final m = buildMonitor(maxFailedProbes: 2);
      m.markProbeInFlight();
      m.recordProbeFailure(); // counter=1
      m.markProbeInFlight();
      m.updateActivityWindow(const Duration(seconds: 20));
      // In-flight flag preserved.
      expect(m.shouldSendProbe(), isFalse);
      // Counter preserved — next failure still trips at 2.
      expect(m.recordProbeFailure(), isTrue);
    });
  });
}
