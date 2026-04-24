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
    test('recordProbeSuccess clears in-flight flag and refreshes activity', () {
      final m = buildMonitor(activityWindow: const Duration(seconds: 5));
      m.markProbeInFlight();
      m.recordProbeSuccess();
      advance(const Duration(seconds: 3));
      // In-flight cleared AND activity refreshed.
      expect(m.probeInFlight, isFalse);
      expect(m.timeUntilNextProbe(), const Duration(seconds: 2));
      advance(const Duration(seconds: 3));
      expect(m.timeUntilNextProbe(), Duration.zero);
    });

    test('recordProbeFailure increments counter and releases in-flight', () {
      final m = buildMonitor(maxFailedProbes: 3);
      m.markProbeInFlight();
      final tripped = m.recordProbeFailure();
      expect(tripped, isFalse, reason: '1 failure < threshold 3');
      // In-flight cleared.
      expect(m.probeInFlight, isFalse);
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
      expect(m.probeInFlight, isTrue);
      m.recordProbeSuccess();
      // Now the flag releases.
      expect(m.probeInFlight, isFalse);
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
      expect(m.probeInFlight, isFalse);
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
      expect(m.timeUntilNextProbe(), Duration.zero);
    });

    test('probeInFlight getter reflects markProbeInFlight + release', () {
      final m = buildMonitor();
      expect(m.probeInFlight, isFalse);
      m.markProbeInFlight();
      expect(m.probeInFlight, isTrue);
      m.recordProbeSuccess();
      expect(m.probeInFlight, isFalse);
    });

    test('probeInFlight released by cancelProbe', () {
      final m = buildMonitor();
      m.markProbeInFlight();
      m.cancelProbe();
      expect(m.probeInFlight, isFalse);
    });

    test('probeInFlight released by recordProbeFailure', () {
      final m = buildMonitor(maxFailedProbes: 3);
      m.markProbeInFlight();
      m.recordProbeFailure();
      expect(m.probeInFlight, isFalse);
    });

    test('updateActivityWindow preserves in-flight and counter state', () {
      final m = buildMonitor(maxFailedProbes: 2);
      m.markProbeInFlight();
      m.recordProbeFailure(); // counter=1
      m.markProbeInFlight();
      m.updateActivityWindow(const Duration(seconds: 20));
      // In-flight flag preserved.
      expect(m.probeInFlight, isTrue);
      // Counter preserved — next failure still trips at 2.
      expect(m.recordProbeFailure(), isTrue);
    });

    test('timeUntilNextProbe returns activityWindow when no activity recorded yet', () {
      final m = buildMonitor(activityWindow: const Duration(seconds: 5));
      // lastActivity is null — deadline falls back to a full activityWindow
      // from now, so the first schedule after construction is activityWindow.
      expect(m.timeUntilNextProbe(), const Duration(seconds: 5));
    });

    test('timeUntilNextProbe returns activityWindow immediately after recordActivity', () {
      final m = buildMonitor(activityWindow: const Duration(seconds: 5));
      m.recordActivity();
      expect(m.timeUntilNextProbe(), const Duration(seconds: 5));
    });

    test('timeUntilNextProbe decreases as clock advances', () {
      final m = buildMonitor(activityWindow: const Duration(seconds: 5));
      m.recordActivity();
      advance(const Duration(seconds: 2));
      expect(m.timeUntilNextProbe(), const Duration(seconds: 3));
    });

    test('timeUntilNextProbe returns Duration.zero once deadline has passed', () {
      final m = buildMonitor(activityWindow: const Duration(seconds: 5));
      m.recordActivity();
      advance(const Duration(seconds: 10));
      expect(m.timeUntilNextProbe(), Duration.zero,
          reason: 'Never returns a negative value; caller should probe immediately');
    });

    test('timeUntilNextProbe reflects updateActivityWindow', () {
      final m = buildMonitor(activityWindow: const Duration(seconds: 5));
      m.recordActivity();
      advance(const Duration(seconds: 2));
      m.updateActivityWindow(const Duration(seconds: 10));
      // With the new 10s window, 8s remain.
      expect(m.timeUntilNextProbe(), const Duration(seconds: 8));
    });

    test('timeUntilNextProbe is not affected by markProbeInFlight', () {
      // The in-flight flag is a separate dimension — the deadline
      // still advances in real time regardless of whether a probe is pending.
      final m = buildMonitor(activityWindow: const Duration(seconds: 5));
      m.recordActivity();
      advance(const Duration(seconds: 2));
      m.markProbeInFlight();
      expect(m.timeUntilNextProbe(), const Duration(seconds: 3));
    });
  });
}
