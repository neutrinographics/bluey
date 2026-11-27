/// Lifecycle state of a [Scanner].
///
/// Wraps the previously-boolean `isScanning` field with explicit
/// transient states so consumers can observe the windows during which
/// the platform call is in flight.
enum ScanState {
  /// No scan active and none being started.
  stopped,

  /// `scan()` has been called; the platform-side start is in flight.
  starting,

  /// Platform confirms the scan is running.
  scanning,

  /// `stop()` has been called (or the consumer cancelled the
  /// subscription, or a `timeout` fired); the platform-side stop is
  /// in flight.
  stopping,

  /// Terminal state set when this scanner is invalidated by an
  /// adapter-state transition. Distinct from [stopped] which is a
  /// resumable rest state. See I333.
  invalidated,
}
