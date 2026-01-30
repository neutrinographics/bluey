import 'connection_state.dart';
import 'gatt.dart';
import 'uuid.dart';

export 'connection_state.dart';

/// An active connection to a BLE device.
///
/// This is the aggregate root for all GATT operations on a connected device.
/// Use [service] or [services] to access the device's GATT services.
///
/// The connection has the following invariants:
/// - GATT access is only valid when [state] is [ConnectionState.connected]
/// - Services are discovered lazily on first access
///
/// Example:
/// ```dart
/// final connection = await bluey.connect(device);
///
/// // Get heart rate service
/// final heartRateService = connection.service(UUID.heartRate);
///
/// // Read heart rate measurement
/// final hrChar = heartRateService.characteristic(UUID.short(0x2A37));
/// final value = await hrChar.read();
///
/// // Subscribe to notifications
/// hrChar.notifications.listen((value) {
///   print('Heart rate: ${value[1]} bpm');
/// });
///
/// // Disconnect when done
/// await connection.disconnect();
/// ```
abstract class Connection {
  /// The connected device's ID.
  UUID get deviceId;

  /// Current connection state.
  ConnectionState get state;

  /// Stream of connection state changes.
  ///
  /// Emits whenever the connection state changes. Use this to react to
  /// disconnection events.
  Stream<ConnectionState> get stateChanges;

  /// Current MTU (Maximum Transmission Unit).
  ///
  /// The MTU determines the maximum size of data that can be sent in a
  /// single write operation. The default is typically 23 bytes.
  int get mtu;

  /// Get a service by UUID.
  ///
  /// Services are discovered lazily on first access.
  ///
  /// Throws [ServiceNotFoundException] if the service is not found.
  /// Throws [DisconnectedException] if not connected.
  RemoteService service(UUID uuid);

  /// Get all services on the device.
  ///
  /// Triggers service discovery if not already done.
  ///
  /// Throws [DisconnectedException] if not connected.
  Future<List<RemoteService>> get services;

  /// Check if a service exists on the device.
  ///
  /// Returns true if the device has a service with the given UUID.
  /// Triggers service discovery if not already done.
  Future<bool> hasService(UUID uuid);

  /// Request a specific MTU.
  ///
  /// Returns the negotiated MTU, which may be different from the requested
  /// value. The actual MTU depends on what both the device and the platform
  /// support.
  ///
  /// Throws [DisconnectedException] if not connected.
  Future<int> requestMtu(int mtu);

  /// Read the current RSSI (signal strength).
  ///
  /// Returns the RSSI in dBm (typically -30 to -100).
  ///
  /// Throws [DisconnectedException] if not connected.
  Future<int> readRssi();

  /// Disconnect from the device.
  ///
  /// After calling disconnect, this connection instance should not be used.
  Future<void> disconnect();
}

/// Connection state for a device.
///
/// Note: This is re-exported from bluey.dart for convenience.
/// The actual definition is in bluey.dart.
