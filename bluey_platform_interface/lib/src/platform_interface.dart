import 'package:flutter/foundation.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'capabilities.dart';

/// Bluetooth adapter state.
enum BluetoothState {
  unknown, // Initial state before platform reports
  unsupported, // Device doesn't support BLE
  unauthorized, // Permission not granted
  off, // Bluetooth disabled
  on; // Ready to use

  /// Whether Bluetooth is ready for use.
  bool get isReady => this == BluetoothState.on;
}

/// Connection state.
enum PlatformConnectionState {
  disconnected,
  connecting,
  connected,
  disconnecting,
}

/// Configuration for scanning.
@immutable
class PlatformScanConfig {
  /// Service UUIDs to filter by (as strings).
  final List<String> serviceUuids;

  /// Timeout in milliseconds (null for no timeout).
  final int? timeoutMs;

  const PlatformScanConfig({
    required this.serviceUuids,
    required this.timeoutMs,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PlatformScanConfig &&
        listEquals(other.serviceUuids, serviceUuids) &&
        other.timeoutMs == timeoutMs;
  }

  @override
  int get hashCode => Object.hash(Object.hashAll(serviceUuids), timeoutMs);
}

/// Configuration for connecting.
@immutable
class PlatformConnectConfig {
  /// Connection timeout in milliseconds (null for default).
  final int? timeoutMs;

  /// Requested MTU (null for default).
  final int? mtu;

  const PlatformConnectConfig({
    required this.timeoutMs,
    required this.mtu,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PlatformConnectConfig &&
        other.timeoutMs == timeoutMs &&
        other.mtu == mtu;
  }

  @override
  int get hashCode => Object.hash(timeoutMs, mtu);
}

/// A discovered device from the platform layer.
@immutable
class PlatformDevice {
  /// Platform-specific device identifier.
  final String id;

  /// Device name (null if not advertised).
  final String? name;

  /// Signal strength in dBm.
  final int rssi;

  /// Service UUIDs (as strings).
  final List<String> serviceUuids;

  /// Manufacturer data company ID.
  final int? manufacturerDataCompanyId;

  /// Manufacturer data bytes.
  final List<int>? manufacturerData;

  const PlatformDevice({
    required this.id,
    required this.name,
    required this.rssi,
    required this.serviceUuids,
    required this.manufacturerDataCompanyId,
    required this.manufacturerData,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PlatformDevice &&
        other.id == id &&
        other.name == name &&
        other.rssi == rssi &&
        listEquals(other.serviceUuids, serviceUuids) &&
        other.manufacturerDataCompanyId == manufacturerDataCompanyId &&
        listEquals(other.manufacturerData, manufacturerData);
  }

  @override
  int get hashCode => Object.hash(
        id,
        name,
        rssi,
        Object.hashAll(serviceUuids),
        manufacturerDataCompanyId,
        Object.hashAll(manufacturerData ?? []),
      );
}

/// Platform-specific implementation interface.
///
/// This follows the Clean Architecture pattern. Each platform
/// (Android, iOS, etc.) implements this interface.
abstract class BlueyPlatform extends PlatformInterface {
  BlueyPlatform() : super(token: _token);

  static final Object _token = Object();

  static BlueyPlatform _instance = _PlaceholderPlatform();

  /// The default instance of [BlueyPlatform] to use.
  static BlueyPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// instance when they register themselves.
  static set instance(BlueyPlatform instance) {
    PlatformInterface.verify(instance, _token);
    _instance = instance;
  }

  /// Platform capabilities.
  Capabilities get capabilities;

  // === State ===

  /// Stream of Bluetooth state changes.
  Stream<BluetoothState> get stateStream;

  /// Get current Bluetooth state.
  Future<BluetoothState> getState();

  /// Request to enable Bluetooth.
  /// Returns true if enabled, false if user declined.
  Future<bool> requestEnable();

  /// Open system Bluetooth settings.
  Future<void> openSettings();

  // === Scanning ===

  /// Start scanning for devices.
  /// Returns a stream of discovered devices.
  Stream<PlatformDevice> scan(PlatformScanConfig config);

  /// Stop scanning.
  Future<void> stopScan();

  // === Connection ===

  /// Connect to a device.
  /// Returns a connection handle (platform-specific ID).
  Future<String> connect(String deviceId, PlatformConnectConfig config);

  /// Disconnect from a device.
  Future<void> disconnect(String deviceId);

  /// Stream of connection state changes for a device.
  Stream<PlatformConnectionState> connectionStateStream(String deviceId);
}

/// Placeholder implementation that throws on all operations.
/// This is used until a real platform implementation is registered.
class _PlaceholderPlatform extends BlueyPlatform {
  @override
  Capabilities get capabilities => const Capabilities();

  @override
  Stream<BluetoothState> get stateStream => throw UnimplementedError(
      'No platform implementation registered. '
      'Did you forget to add bluey_android or bluey_ios to your dependencies?');

  @override
  Future<BluetoothState> getState() =>
      throw UnimplementedError('No platform implementation registered.');

  @override
  Future<bool> requestEnable() =>
      throw UnimplementedError('No platform implementation registered.');

  @override
  Future<void> openSettings() =>
      throw UnimplementedError('No platform implementation registered.');

  @override
  Stream<PlatformDevice> scan(PlatformScanConfig config) =>
      throw UnimplementedError('No platform implementation registered.');

  @override
  Future<void> stopScan() =>
      throw UnimplementedError('No platform implementation registered.');

  @override
  Future<String> connect(String deviceId, PlatformConnectConfig config) =>
      throw UnimplementedError('No platform implementation registered.');

  @override
  Future<void> disconnect(String deviceId) =>
      throw UnimplementedError('No platform implementation registered.');

  @override
  Stream<PlatformConnectionState> connectionStateStream(String deviceId) =>
      throw UnimplementedError('No platform implementation registered.');
}
