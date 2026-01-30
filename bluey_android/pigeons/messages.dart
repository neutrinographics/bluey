import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(PigeonOptions(
  dartOut: 'lib/src/messages.g.dart',
  dartOptions: DartOptions(),
  kotlinOut: 'android/src/main/kotlin/com/neutrinographics/bluey/Messages.g.kt',
  kotlinOptions: KotlinOptions(
    package: 'com.neutrinographics.bluey',
  ),
))

/// Bluetooth adapter state (DTO for platform channel).
enum BluetoothStateDto {
  unknown,
  unsupported,
  unauthorized,
  off,
  on,
}

/// Connection state (DTO for platform channel).
enum ConnectionStateDto {
  disconnected,
  connecting,
  connected,
  disconnecting,
}

/// Scan configuration (DTO for platform channel).
class ScanConfigDto {
  /// Service UUIDs to filter by.
  final List<String> serviceUuids;

  /// Timeout in milliseconds (null for no timeout).
  final int? timeoutMs;

  ScanConfigDto({
    required this.serviceUuids,
    this.timeoutMs,
  });
}

/// Connect configuration (DTO for platform channel).
class ConnectConfigDto {
  /// Connection timeout in milliseconds.
  final int? timeoutMs;

  /// Requested MTU.
  final int? mtu;

  ConnectConfigDto({
    this.timeoutMs,
    this.mtu,
  });
}

/// A discovered device (DTO for platform channel).
class DeviceDto {
  /// Device ID.
  final String id;

  /// Device name.
  final String? name;

  /// RSSI in dBm.
  final int rssi;

  /// Service UUIDs.
  final List<String> serviceUuids;

  /// Manufacturer data company ID.
  final int? manufacturerDataCompanyId;

  /// Manufacturer data bytes.
  final List<int>? manufacturerData;

  DeviceDto({
    required this.id,
    this.name,
    required this.rssi,
    required this.serviceUuids,
    this.manufacturerDataCompanyId,
    this.manufacturerData,
  });
}

/// Connection state event (DTO for platform channel).
class ConnectionStateEventDto {
  final String deviceId;
  final ConnectionStateDto state;

  ConnectionStateEventDto({
    required this.deviceId,
    required this.state,
  });
}

/// Host API - called from Dart to platform.
@HostApi()
abstract class BlueyHostApi {
  /// Get current Bluetooth state.
  @async
  BluetoothStateDto getState();

  /// Request to enable Bluetooth.
  /// Returns true if enabled, false if user declined.
  @async
  bool requestEnable();

  /// Open system Bluetooth settings.
  @async
  void openSettings();

  /// Start scanning.
  @async
  void startScan(ScanConfigDto config);

  /// Stop scanning.
  @async
  void stopScan();

  /// Connect to a device.
  /// Returns connection handle.
  @async
  String connect(String deviceId, ConnectConfigDto config);

  /// Disconnect from a device.
  @async
  void disconnect(String deviceId);
}

/// Flutter API - called from platform to Dart.
@FlutterApi()
abstract class BlueyFlutterApi {
  /// Bluetooth state changed.
  void onStateChanged(BluetoothStateDto state);

  /// Device discovered during scan.
  void onDeviceDiscovered(DeviceDto device);

  /// Scan completed or stopped.
  void onScanComplete();

  /// Connection state changed.
  void onConnectionStateChanged(ConnectionStateEventDto event);
}
