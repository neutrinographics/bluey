import 'package:clock/clock.dart';

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

  /// Any evidence that the peer is alive: a successful GATT op, an
  /// incoming notification, or a completed probe. Resets the failure
  /// counter and refreshes the activity timestamp.
  void recordActivity() {
    _consecutiveFailures = 0;
    _lastActivityAt = _now();
  }

  /// Tick-time decision: should we send a probe this tick? False if
  /// a probe is already pending, or activity is recent within the
  /// window. Uses `>=` at the boundary so the first tick after the
  /// window expires sends a heartbeat in time to beat the server's
  /// matching per-client timeout — with `>` the boundary slides the
  /// heartbeat out to the NEXT tick, racing the server timer.
  bool shouldSendProbe() {
    if (_probeInFlight) return false;
    final last = _lastActivityAt;
    if (last == null) return true;
    return _now().difference(last) >= _activityWindow;
  }

  /// Swaps in a new activity window (e.g. after negotiating the
  /// server-preferred interval). Preserves in-flight probe state and
  /// the failure counter.
  void updateActivityWindow(Duration window) {
    assert(window > Duration.zero, 'activityWindow must be positive');
    _activityWindow = window;
  }

  /// Called just before dispatching a probe write. Prevents parallel
  /// probes — next tick will skip via [shouldSendProbe].
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
