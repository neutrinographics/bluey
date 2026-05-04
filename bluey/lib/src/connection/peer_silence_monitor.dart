import 'dart:async';

import 'package:clock/clock.dart';
import 'package:meta/meta.dart';

/// Detects when a peer has been silent for too long.
///
/// State machine:
/// - **Idle (no death watch).** No outstanding failure has been
///   recorded, or the most recent failure was followed by a success.
///   `_firstFailureAt` is null. No timer scheduled. The peer is
///   presumed alive.
/// - **Death watch active.** A failure has been recorded; no success
///   has cleared it. `_firstFailureAt` is non-null. A `Timer` is
///   scheduled to fire `onSilent` at `_firstFailureAt +
///   peerSilenceTimeout`. Any successful exchange returns the
///   monitor to idle.
///
/// The death watch deliberately ignores pending state — once armed,
/// the timer runs to completion regardless of whether further user
/// ops start or end. This ensures rapid back-to-back failures don't
/// indefinitely defer dead-peer detection. Only an explicit
/// `recordActivity` (or `recordProbeSuccess`) cancels the timer.
///
/// Pure-ish domain — no GATT, no platform dependencies. Schedules a
/// Dart `Timer`; tests use `fake_async` and the `clock` package's
/// `withClock` to control time.
///
/// Bidirectional symmetry note: the *server-side* `LifecycleServer`
/// uses a similar but distinct mechanism (watchdog from last activity
/// rather than death-watch from first failure). The two share
/// vocabulary — peer silence, pending exchange, activity reset — but
/// not implementation, because the server passively receives
/// heartbeats while the client actively initiates exchanges. See
/// `LifecycleServer` for the symmetric counterpart.
class PeerSilenceMonitor {
  /// How long after a first failure (without an intervening success)
  /// before the peer is declared silent and `onSilent` fires.
  final Duration peerSilenceTimeout;

  /// Fired exactly once when the death watch expires. The monitor
  /// stops itself on this call; further `recordPeerFailure` calls are
  /// no-ops until the surrounding `LifecycleClient` is restarted.
  final void Function() onSilent;

  /// Cadence at which the lifecycle client schedules heartbeat
  /// probes during idle periods. Independent of [peerSilenceTimeout].
  Duration _activityWindow;

  DateTime? _lastActivityAt;
  DateTime? _firstFailureAt;
  Timer? _deathTimer;
  bool _probeInFlight = false;
  bool _running = false;

  PeerSilenceMonitor({
    required this.peerSilenceTimeout,
    required this.onSilent,
    required Duration activityWindow,
  }) : _activityWindow = activityWindow {
    assert(
      peerSilenceTimeout > Duration.zero,
      'peerSilenceTimeout must be positive',
    );
    assert(activityWindow > Duration.zero, 'activityWindow must be positive');
  }

  /// Probe-scheduling cadence. Read-only from outside; mutate via
  /// [updateActivityWindow].
  Duration get activityWindow => _activityWindow;

  /// Becomes false when the monitor has fired `onSilent` (terminal)
  /// or `stop()` has been called.
  bool get isRunning => _running;

  /// Activates the monitor. Failures recorded before `start()` are
  /// ignored; activity is tracked but the timer is not armed.
  void start() {
    _running = true;
  }

  /// Deactivates the monitor, cancels any pending timer, and releases the
  /// in-flight probe flag. Idempotent.
  void stop() {
    _running = false;
    _probeInFlight = false;
    _deathTimer?.cancel();
    _deathTimer = null;
  }

  /// Records evidence that the peer is alive: a successful user op,
  /// an incoming notification, or a probe ack. Cancels the death
  /// watch if one is active.
  ///
  /// Deliberately does NOT clear `_probeInFlight`: a probe write that
  /// is genuinely still on the wire must complete via
  /// [recordProbeSuccess] / [cancelProbe] / [recordPeerFailure]. If
  /// recordActivity cleared the flag, a user op completing during a
  /// probe write could let the next scheduled tick dispatch a second
  /// probe before the first one resolves — the exact CoreBluetooth
  /// queue-contention pattern this monitor was introduced to avoid.
  /// Lingering `_probeInFlight` after [stop] is handled in [stop]
  /// itself.
  void recordActivity() {
    _lastActivityAt = clock.now();
    _firstFailureAt = null;
    _deathTimer?.cancel();
    _deathTimer = null;
  }

  /// Probe write succeeded and peer acknowledged. Equivalent to
  /// [recordActivity] plus releasing the in-flight flag.
  void recordProbeSuccess() {
    _probeInFlight = false;
    recordActivity();
  }

  /// Records evidence that the peer may be unresponsive. If this is
  /// the first failure since the last success, arms the death timer
  /// for `_firstFailureAt + peerSilenceTimeout`. Subsequent failures
  /// while the death watch is active are no-ops on `_firstFailureAt`
  /// (the deadline doesn't reset).
  void recordPeerFailure() {
    if (!_running) return;
    _firstFailureAt ??= clock.now();
    if (_deathTimer != null) return; // already armed
    final deadline = _firstFailureAt!.add(peerSilenceTimeout);
    final remaining = deadline.difference(clock.now());
    if (!remaining.isNegative && remaining != Duration.zero) {
      _deathTimer = Timer(remaining, _fireSilent);
    } else {
      _fireSilent();
    }
  }

  /// Probe write failed in a way that's not interpreted as dead-peer
  /// (e.g., a transient platform error like Android's
  /// "another op in flight"). Releases the in-flight flag without
  /// touching the death watch.
  void cancelProbe() {
    _probeInFlight = false;
  }

  void _fireSilent() {
    if (!_running) return;
    _deathTimer = null;
    _running = false; // single-fire
    onSilent();
  }

  /// Whether a probe is currently in flight. Caller-side flag set
  /// before dispatching the heartbeat write.
  bool get probeInFlight => _probeInFlight;

  /// Marks that a probe write has been dispatched. The caller must
  /// follow up with [recordProbeSuccess] or [cancelProbe] /
  /// [recordPeerFailure].
  void markProbeInFlight() {
    _probeInFlight = true;
  }

  /// Whether any successful activity has been recorded since the
  /// monitor was last (re)started. Used by `LifecycleClient` to
  /// distinguish between "timer fired exactly when scheduled, no
  /// activity has shifted the deadline" (fire the probe) and "activity
  /// raced the timer and pushed the deadline forward" (defer).
  bool get hasActivity => _lastActivityAt != null;

  /// How long from now until the next probe is due. Used by
  /// `LifecycleClient` to decide when to schedule the next probe
  /// timer in idle.
  Duration timeUntilNextProbe() {
    final last = _lastActivityAt;
    if (last == null) return _activityWindow;
    final elapsed = clock.now().difference(last);
    final remaining = _activityWindow - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Swaps in a new probe-scheduling cadence (e.g. after negotiating
  /// the server-preferred interval). Preserves all other state.
  void updateActivityWindow(Duration window) {
    assert(window > Duration.zero, 'activityWindow must be positive');
    _activityWindow = window;
  }

  @visibleForTesting
  DateTime? get lastActivityAt => _lastActivityAt;

  @visibleForTesting
  DateTime? get firstFailureAt => _firstFailureAt;

  @visibleForTesting
  bool get isDeathWatchActive => _deathTimer != null;
}
