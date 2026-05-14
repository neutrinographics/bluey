/// Lifecycle state of a [Server]'s advertising operation.
///
/// Wraps the previously-boolean `isAdvertising` field with explicit
/// transient states so consumers can observe the windows during which
/// the platform call is in flight.
enum AdvertisingState {
  /// Not currently advertising and not in the middle of starting.
  idle,

  /// `startAdvertising()` has been called; platform-side start is in
  /// flight.
  starting,

  /// Platform confirms advertising is active.
  advertising,

  /// `stopAdvertising()` has been called; platform-side stop is in
  /// flight.
  stopping,

  /// Terminal state set when the parent [Server] is invalidated by an
  /// adapter-state transition. See I333.
  invalidated,
}
