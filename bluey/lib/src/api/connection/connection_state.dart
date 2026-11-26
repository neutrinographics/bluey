/// Where a `Connection` stands, as an app reads it.
///
/// - [linked]: the link is up, but its services have not been discovered,
///   so GATT operations are not safe yet. A `Connection` starts here.
/// - [ready]: services have been discovered, so GATT operations are safe.
/// - [disconnecting]: the link is being closed.
/// - [disconnected]: the link has ended, asked for or lost.
/// - [invalidated]: the link ended because the radio became unusable
///   (Bluetooth turned off, say), so it cannot be trusted to exist; build a
///   new connection once the radio is back.
/// - [connecting]: kept for apps that switch over every state; a
///   `Connection` never reports it, since it exists only once its link is
///   up.
///
/// Most apps want [isConnected] (true for either [linked] or [ready]) for
/// "is the link up?" or [isReady] for "is it safe to issue GATT operations?".
enum ConnectionState {
  disconnected,
  connecting,
  linked,
  ready,
  disconnecting,

  /// Terminal state set when this connection is invalidated by an
  /// adapter-state transition (e.g. Bluetooth toggled off). Distinct
  /// from [disconnected] which represents a normal disconnect path.
  /// See I333 for the broader invalidation contract.
  invalidated;

  /// Whether the connection is somewhere in its active lifecycle —
  /// connecting, linked, or fully ready. False once disconnecting starts.
  bool get isActive => this == connecting || this == linked || this == ready;

  /// Whether the link is up at the controller level. True for both
  /// [linked] and [ready]; use this if you only care that the device is
  /// reachable, not whether services have been discovered yet.
  bool get isConnected => this == linked || this == ready;

  /// Whether the connection has finished service discovery and is safe
  /// to issue GATT reads/writes/notifications on. Strictly stronger than
  /// [isConnected].
  bool get isReady => this == ready;
}
