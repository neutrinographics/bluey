/// The state of the Bluetooth adapter.
enum BluetoothState {
  /// Initial state before platform reports.
  unknown,

  /// Device doesn't support BLE.
  unsupported,

  /// Permission not granted.
  unauthorized,

  /// Bluetooth is disabled.
  off,

  /// Bluetooth is ready to use.
  on;

  /// Whether Bluetooth is ready for use.
  bool get isReady => this == BluetoothState.on;

  /// Whether Bluetooth can be enabled (only true when off).
  bool get canBeEnabled => this == BluetoothState.off;
}
