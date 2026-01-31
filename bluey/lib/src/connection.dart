import 'package:flutter/foundation.dart';

import 'connection_state.dart';
import 'gatt.dart';
import 'uuid.dart';

export 'connection_state.dart';

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

/// BLE connection parameters.
///
/// These parameters control the timing and behavior of the connection,
/// affecting latency, throughput, and power consumption.
@immutable
class ConnectionParameters {
  /// Connection interval in milliseconds (7.5ms to 4000ms).
  ///
  /// The connection interval is the time between two connection events.
  /// Smaller values provide lower latency but higher power consumption.
  final double intervalMs;

  /// Slave latency (0 to 499).
  ///
  /// The number of connection events the peripheral can skip if it has
  /// no data to send. Higher values save power but increase latency for
  /// peripheral-initiated communication.
  final int latency;

  /// Supervision timeout in milliseconds (100ms to 32000ms).
  ///
  /// The time after which the connection is considered lost if no valid
  /// packets are received. Should be larger than (1 + latency) * intervalMs.
  final int timeoutMs;

  /// Creates connection parameters.
  const ConnectionParameters({
    required this.intervalMs,
    required this.latency,
    required this.timeoutMs,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ConnectionParameters &&
        other.intervalMs == intervalMs &&
        other.latency == latency &&
        other.timeoutMs == timeoutMs;
  }

  @override
  int get hashCode => Object.hash(intervalMs, latency, timeoutMs);

  @override
  String toString() =>
      'ConnectionParameters(interval: ${intervalMs}ms, latency: $latency, timeout: ${timeoutMs}ms)';
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
/// - GATT access is only valid when [state] is [ConnectionState.connected]
/// - Services are discovered lazily on first access
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

  // === Bonding ===

  /// Current bonding state.
  ///
  /// Returns the current bond state between this device and the local device.
  BondState get bondState;

  /// Stream of bonding state changes.
  ///
  /// Emits whenever the bonding state changes. Use this to react to
  /// bonding completion or failure.
  Stream<BondState> get bondStateChanges;

  /// Initiate bonding/pairing with the device.
  ///
  /// This will start the bonding process, which may prompt the user to
  /// confirm a pairing code on one or both devices.
  ///
  /// The [bondStateChanges] stream will emit [BondState.bonding] when
  /// the process starts, and [BondState.bonded] when complete.
  ///
  /// Throws [DisconnectedException] if not connected.
  Future<void> bond();

  /// Remove bond with the device.
  ///
  /// This removes the stored bonding information. The device will need
  /// to be paired again for encrypted characteristic access.
  ///
  /// Throws [DisconnectedException] if not connected.
  Future<void> removeBond();

  // === PHY ===

  /// Current transmit PHY.
  ///
  /// Returns the PHY being used for transmitting data to the device.
  Phy get txPhy;

  /// Current receive PHY.
  ///
  /// Returns the PHY being used for receiving data from the device.
  Phy get rxPhy;

  /// Stream of PHY changes.
  ///
  /// Emits whenever either the transmit or receive PHY changes.
  /// The record contains both the new transmit and receive PHY values.
  Stream<({Phy tx, Phy rx})> get phyChanges;

  /// Request specific PHY settings.
  ///
  /// Requests the controller to use the specified PHY for transmit and/or
  /// receive. The actual PHY used may differ based on what the remote
  /// device supports.
  ///
  /// [txPhy] - Preferred transmit PHY. If null, no preference is specified.
  /// [rxPhy] - Preferred receive PHY. If null, no preference is specified.
  ///
  /// The [phyChanges] stream will emit when the PHY actually changes.
  ///
  /// Throws [DisconnectedException] if not connected.
  Future<void> requestPhy({Phy? txPhy, Phy? rxPhy});

  // === Connection Parameters ===

  /// Current connection parameters.
  ///
  /// Returns the current connection parameters including interval,
  /// latency, and supervision timeout.
  ConnectionParameters get connectionParameters;

  /// Request updated connection parameters.
  ///
  /// Requests the controller to use the specified connection parameters.
  /// The actual parameters used may differ based on what the remote
  /// device and controller support.
  ///
  /// [params] - The desired connection parameters.
  ///
  /// Throws [DisconnectedException] if not connected.
  Future<void> requestConnectionParameters(ConnectionParameters params);
}

/// Connection state for a device.
///
/// Note: This is re-exported from bluey.dart for convenience.
/// The actual definition is in bluey.dart.
