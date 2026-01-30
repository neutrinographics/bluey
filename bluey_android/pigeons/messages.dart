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

/// Characteristic properties flags (DTO for platform channel).
class CharacteristicPropertiesDto {
  final bool canRead;
  final bool canWrite;
  final bool canWriteWithoutResponse;
  final bool canNotify;
  final bool canIndicate;

  CharacteristicPropertiesDto({
    required this.canRead,
    required this.canWrite,
    required this.canWriteWithoutResponse,
    required this.canNotify,
    required this.canIndicate,
  });
}

/// A descriptor on a remote device (DTO for platform channel).
class DescriptorDto {
  final String uuid;

  DescriptorDto({required this.uuid});
}

/// A characteristic on a remote device (DTO for platform channel).
class CharacteristicDto {
  final String uuid;
  final CharacteristicPropertiesDto properties;
  final List<DescriptorDto> descriptors;

  CharacteristicDto({
    required this.uuid,
    required this.properties,
    required this.descriptors,
  });
}

/// A service on a remote device (DTO for platform channel).
class ServiceDto {
  final String uuid;
  final bool isPrimary;
  final List<CharacteristicDto> characteristics;
  final List<ServiceDto> includedServices;

  ServiceDto({
    required this.uuid,
    required this.isPrimary,
    required this.characteristics,
    required this.includedServices,
  });
}

/// Notification event (DTO for platform channel).
class NotificationEventDto {
  final String deviceId;
  final String characteristicUuid;
  final Uint8List value;

  NotificationEventDto({
    required this.deviceId,
    required this.characteristicUuid,
    required this.value,
  });
}

/// MTU changed event (DTO for platform channel).
class MtuChangedEventDto {
  final String deviceId;
  final int mtu;

  MtuChangedEventDto({
    required this.deviceId,
    required this.mtu,
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

  // === GATT Operations ===

  /// Discover services on a connected device.
  /// Services are cached after first discovery.
  @async
  List<ServiceDto> discoverServices(String deviceId);

  /// Read a characteristic value.
  @async
  Uint8List readCharacteristic(String deviceId, String characteristicUuid);

  /// Write a characteristic value.
  @async
  void writeCharacteristic(
    String deviceId,
    String characteristicUuid,
    Uint8List value,
    bool withResponse,
  );

  /// Enable or disable notifications for a characteristic.
  @async
  void setNotification(
    String deviceId,
    String characteristicUuid,
    bool enable,
  );

  /// Read a descriptor value.
  @async
  Uint8List readDescriptor(String deviceId, String descriptorUuid);

  /// Write a descriptor value.
  @async
  void writeDescriptor(String deviceId, String descriptorUuid, Uint8List value);

  /// Request a specific MTU.
  /// Returns the negotiated MTU.
  @async
  int requestMtu(String deviceId, int mtu);

  /// Read the current RSSI for a connected device.
  @async
  int readRssi(String deviceId);
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

  /// Characteristic notification received.
  void onNotification(NotificationEventDto event);

  /// MTU changed for a connection.
  void onMtuChanged(MtuChangedEventDto event);
}
