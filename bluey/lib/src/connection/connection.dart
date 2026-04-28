import '../gatt_client/gatt.dart';
import '../peer/server_id.dart';
import '../shared/uuid.dart';
import 'android_connection_extensions.dart';
import 'connection_state.dart';
import 'ios_connection_extensions.dart';
import 'value_objects/mtu.dart';

export 'connection_state.dart';
export 'value_objects/connection_interval.dart';
export 'value_objects/mtu.dart';
export 'value_objects/peripheral_latency.dart';
export 'value_objects/supervision_timeout.dart';
export 'value_objects/connection_parameters.dart' show ConnectionParameters;

/// Bonding state of a device.
///
/// Bonding (also known as pairing) establishes a trusted relationship
/// between devices that persists across connections. Bonded devices
/// can reconnect without re-pairing and may have access to encrypted
/// characteristics.
enum BondState {
  /// No bond exists with this device.
  none,

  /// Bonding is in progress.
  ///
  /// The user may be prompted to confirm a pairing code.
  bonding,

  /// The device is bonded.
  ///
  /// The bond persists across disconnections and app restarts.
  bonded,
}

/// BLE Physical Layer (PHY) options.
///
/// The PHY determines the radio modulation used for the connection,
/// affecting throughput, range, and power consumption.
enum Phy {
  /// 1 Mbps PHY (default, most compatible).
  ///
  /// This is the standard BLE PHY supported by all BLE devices.
  /// Good balance of range, speed, and compatibility.
  le1m,

  /// 2 Mbps PHY (faster, shorter range).
  ///
  /// Doubles the data rate compared to LE 1M, reducing transmission
  /// time and power consumption for large transfers. However, it has
  /// slightly reduced range. Requires Bluetooth 5.0+.
  le2m,

  /// Coded PHY (longer range, slower).
  ///
  /// Uses forward error correction for improved sensitivity, enabling
  /// significantly longer range (up to 4x LE 1M). The tradeoff is lower
  /// throughput. Requires Bluetooth 5.0+.
  leCoded,
}

/// An active connection to a BLE device.
///
/// This is the aggregate root for all GATT operations on a connected device.
/// Use [service] or [services] to access the device's GATT services.
///
/// The connection has the following invariants:
/// - GATT access is only valid when [state] is [ConnectionState.ready]
///   (or use the [ConnectionState.isReady] helper). Use
///   [ConnectionState.isConnected] (true for both `linked` and `ready`)
///   if you only need to know the link is up.
/// - Services are discovered lazily on first access; the `linked` →
///   `ready` transition fires once that discovery completes.
///
/// Example:
/// ```dart
/// final connection = await bluey.connect(device);
///
/// // Get heart rate service
/// final heartRateService = connection.service(Services.heartRate);
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

  /// Whether this connection is to a Bluey server running the lifecycle
  /// protocol (heartbeat-based disconnect detection, stable identity).
  bool get isBlueyServer;

  /// The server's stable identity, if this is a Bluey server connection.
  /// Returns null for non-Bluey connections.
  ServerId? get serverId;

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
  /// single write operation. The default is typically 23 bytes. Wrapped
  /// as an [Mtu] value object; access the wire-level integer via
  /// [Mtu.value].
  Mtu get mtu;

  /// Get a service by UUID.
  ///
  /// Services are discovered lazily on first access.
  ///
  /// Throws [ServiceNotFoundException] if the service is not found.
  /// Throws [DisconnectedException] if not connected.
  RemoteService service(UUID uuid);

  /// Get all services on the device.
  ///
  /// By default, this always performs service discovery on the device.
  /// Set [cache] to true to return previously discovered services if
  /// available, which avoids the round-trip to the device.
  ///
  /// Throws [DisconnectedException] if not connected.
  Future<List<RemoteService>> services({bool cache = false});

  /// Check if a service exists on the device.
  ///
  /// Returns true if the device has a service with the given UUID.
  /// Triggers service discovery if not already done.
  Future<bool> hasService(UUID uuid);

  /// Request a specific MTU.
  ///
  /// Returns the negotiated MTU, which may be different from the requested
  /// value. The actual MTU depends on what both the device and the platform
  /// support. Both the parameter and the returned future are wrapped as
  /// [Mtu] value objects; the wire-level integer is available via
  /// [Mtu.value].
  ///
  /// Throws [DisconnectedException] if not connected.
  Future<Mtu> requestMtu(Mtu mtu);

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

  // === Platform-specific extensions ===

  /// Android-specific extensions (bonding, PHY, connection parameters).
  ///
  /// Returns a non-null facade when the underlying platform's
  /// [Capabilities] indicate at least one Android-only feature is
  /// available (`canBond`, `canRequestPhy`, or
  /// `canRequestConnectionParameters`). Returns `null` on platforms that
  /// don't expose these APIs (notably iOS).
  ///
  /// Use the null-aware operator for safe access:
  /// ```dart
  /// await connection.android?.bond();
  /// final phy = connection.android?.txPhy ?? Phy.le1m;
  /// ```
  AndroidConnectionExtensions? get android;

  /// iOS-specific extensions.
  ///
  /// Returns a non-null facade on iOS-flavored capabilities (heuristic:
  /// none of the Android-only flags are set). Currently exposes no
  /// members; reserved for future iOS-specific features.
  IosConnectionExtensions? get ios;
}

/// Connection state for a device.
///
/// Note: This is re-exported from bluey.dart for convenience.
/// The actual definition is in bluey.dart.
