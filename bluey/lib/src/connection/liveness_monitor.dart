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

  /// Minimum time since last activity before the monitor will ask
  /// for a probe. Typically equals the probe tick interval so at most
  /// one probe is dispatched per idle window.
  final Duration activityWindow;

  /// Clock injection for deterministic tests.
  final DateTime Function() _now;

  DateTime? _lastActivityAt;
  int _consecutiveFailures = 0;
  bool _probeInFlight = false;

  LivenessMonitor({
    required this.maxFailedProbes,
    required this.activityWindow,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// Any evidence that the peer is alive: a successful GATT op, an
  /// incoming notification, or a completed probe. Resets the failure
  /// counter and refreshes the activity timestamp.
  void recordActivity() {
    _consecutiveFailures = 0;
    _lastActivityAt = _now();
  }

  /// Tick-time decision: should we send a probe this tick? False if
  /// a probe is already pending, or activity is recent within the
  /// window.
  bool shouldSendProbe() {
    if (_probeInFlight) return false;
    final last = _lastActivityAt;
    if (last == null) return true;
    return _now().difference(last) >= activityWindow;
  }

  /// Called just before dispatching a probe write. Prevents parallel
  /// probes — next tick will skip via [shouldSendProbe].
  void markProbeInFlight() {
    _probeInFlight = true;
  }

  /// Probe write completed and peer acknowledged. Equivalent to
  /// [recordActivity] plus releasing the in-flight flag.
  ///
  /// Also safe to call when no probe was in flight (used when a
  /// non-dead-peer error fires during the probe write — releases
  /// the flag without counting a failure).
  void recordProbeSuccess() {
    _probeInFlight = false;
    _consecutiveFailures = 0;
    _lastActivityAt = _now();
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
