/// Connection state for a device.
///
/// Models the BLE connection lifecycle as five distinct phases, plus a
/// terminal [invalidated] state for adapter-driven teardown:
///
/// - [disconnected] — no link.
/// - [connecting] — link being established (platform-level connect in flight).
/// - [linked] — link is up at the controller level. Services have not yet
///   been discovered, so GATT operations are not safe to issue. This is the
///   first state observable after a successful platform connect.
/// - [ready] — services have been discovered and (for Bluey peers) the
///   lifecycle protocol upgrade is complete. GATT operations are safe.
/// - [disconnecting] — link being torn down.
/// - [invalidated] — terminal state set when the adapter is disabled while
///   the connection was active. Distinct from [disconnected] which represents
///   a normal disconnect path. See I333 for the broader invalidation contract.
///
/// Most consumers want [isConnected] (true for either [linked] or
/// [ready]) for "is the link up?" or [isReady] for "is the connection
/// safe to issue GATT ops on?".
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
