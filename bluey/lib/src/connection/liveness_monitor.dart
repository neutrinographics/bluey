import 'package:clock/clock.dart';
import 'package:meta/meta.dart';

/// Tracks whether a peer is still alive, based on a stream of
/// observable events.
///
/// Pure domain — no GATT, no async, no platform dependencies. The
/// monitor is queried every tick by [LifecycleClient] to decide
/// whether to send a new probe; between ticks it receives events
/// when user ops complete, notifications arrive, or probes finish.
///
/// Invariants:
/// - At most one probe is "in flight" at any time.
/// - Failure counter is monotonically non-decreasing until reset.
/// - Any activity (user op success or probe ack) resets the counter.
class LivenessMonitor {
  /// Consecutive probe failures that trip peer-unreachable. Activity
  /// clears the counter before it reaches the threshold, so a trip
  /// only fires during genuine idle periods.
  final int maxFailedProbes;

  /// Clock injection for deterministic tests.
  final DateTime Function() _now;

  Duration _activityWindow;
  DateTime? _lastActivityAt;
  int _consecutiveFailures = 0;
  bool _probeInFlight = false;

  LivenessMonitor({
    required this.maxFailedProbes,
    required Duration activityWindow,
    DateTime Function()? now,
  })  : _activityWindow = activityWindow,
        _now = now ?? clock.now {
    assert(activityWindow > Duration.zero,
        'activityWindow must be positive');
  }

  /// Minimum time since last activity before the monitor will ask
  /// for a probe. Typically equals the probe tick interval so at most
  /// one probe is dispatched per idle window. Read-only from outside;
  /// callers mutate via [updateActivityWindow].
  Duration get activityWindow => _activityWindow;

  /// Last recorded activity timestamp, or null if no activity has been
  /// observed. Exposed for [LifecycleClient]'s test-only accessor.
  @visibleForTesting
  DateTime? get lastActivityAt => _lastActivityAt;

  /// Whether a probe is currently in flight. Needed by callers that
  /// schedule the next probe from timer callbacks — a fired timer must
  /// not send a new probe while a previous one is still pending.
  bool get probeInFlight => _probeInFlight;

  /// Any evidence that the peer is alive: a successful GATT op, an
  /// incoming notification, or a completed probe. Resets the failure
  /// counter and refreshes the activity timestamp.
  ///
  /// **Caller contract:** this shifts the probe deadline forward by
  /// [activityWindow]. Callers that arm a timer against
  /// [timeUntilNextProbe] must cancel and reschedule after calling this —
  /// otherwise the stale timer fires earlier than the deadline.
  void recordActivity() {
    _consecutiveFailures = 0;
    _lastActivityAt = _now();
  }

  /// How long from now until the next probe is due.
  ///
  /// Returns [Duration.zero] if the deadline is already past — caller
  /// should probe immediately. Returns [activityWindow] if no activity
  /// has been recorded yet, giving the caller a sensible first deadline.
  ///
  /// The in-flight flag is a separate dimension: this method reports
  /// the deadline regardless, so the caller can make a unified
  /// "time to probe" decision (via a one-shot timer) without needing
  /// to special-case the in-flight branch.
  Duration timeUntilNextProbe() {
    final last = _lastActivityAt;
    if (last == null) return _activityWindow;
    final elapsed = _now().difference(last);
    final remaining = _activityWindow - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Swaps in a new activity window (e.g. after negotiating the
  /// server-preferred interval). Preserves in-flight probe state and
  /// the failure counter.
  void updateActivityWindow(Duration window) {
    assert(window > Duration.zero, 'activityWindow must be positive');
    _activityWindow = window;
  }

  /// Called just before dispatching a probe write. Prevents parallel
  /// probes — [probeInFlight] will be true until the probe completes.
  void markProbeInFlight() {
    _probeInFlight = true;
  }

  /// Probe write completed and peer acknowledged. Equivalent to
  /// [recordActivity] plus releasing the in-flight flag.
  void recordProbeSuccess() {
    _probeInFlight = false;
    _consecutiveFailures = 0;
    _lastActivityAt = _now();
  }

  /// Probe write failed with a transient, non-dead-peer error (e.g.
  /// "another op in flight" on Android). Releases the in-flight flag so
  /// the next tick can retry, but does NOT reset the failure counter or
  /// refresh the activity timestamp.
  void cancelProbe() {
    _probeInFlight = false;
  }

  /// Probe write failed with a dead-peer signal (caller determines
  /// what counts as dead-peer). Returns true if the failure threshold
  /// is now reached — caller should tear down the connection.
  bool recordProbeFailure() {
    _probeInFlight = false;
    _consecutiveFailures++;
    return _consecutiveFailures >= maxFailedProbes;
  }
}
