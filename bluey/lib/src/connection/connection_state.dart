/// Connection state for a device.
enum ConnectionState {
  disconnected,
  connecting,
  connected,
  disconnecting;

  /// Whether the connection is active (connecting or connected).
  bool get isActive => this == connecting || this == connected;

  /// Whether fully connected.
  bool get isConnected => this == connected;
}
