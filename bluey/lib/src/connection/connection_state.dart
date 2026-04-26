/// Connection state for a device.
///
/// Models the BLE connection lifecycle as five distinct phases:
///
/// - [disconnected] — no link.
/// - [connecting] — link being established (platform-level connect in flight).
/// - [linked] — link is up at the controller level. Services have not yet
///   been discovered, so GATT operations are not safe to issue. This is the
///   first state observable after a successful platform connect.
/// - [ready] — services have been discovered and (for Bluey peers) the
///   lifecycle protocol upgrade is complete. GATT operations are safe.
/// - [disconnecting] — link being torn down.
///
/// The [linked] → [ready] split (added in I067) replaces the previous
/// single `connected` value. Most consumers want [isConnected] (true for
/// either [linked] or [ready]) for "is the link up?" or [isReady] for
/// "is the connection safe to issue GATT ops on?".
enum ConnectionState {
  disconnected,
  connecting,
  linked,
  ready,
  disconnecting;

  /// Whether the connection is somewhere in its active lifecycle —
  /// connecting, linked, or fully ready. False once disconnecting starts.
  bool get isActive =>
      this == connecting || this == linked || this == ready;

  /// Whether the link is up at the controller level. True for both
  /// [linked] and [ready]; use this if you only care that the device is
  /// reachable, not whether services have been discovered yet.
  bool get isConnected => this == linked || this == ready;

  /// Whether the connection has finished service discovery and is safe
  /// to issue GATT reads/writes/notifications on. Strictly stronger than
  /// [isConnected].
  bool get isReady => this == ready;
}
