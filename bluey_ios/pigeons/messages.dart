import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/messages.g.dart',
    dartOptions: DartOptions(),
    swiftOut: 'ios/Classes/Messages.g.swift',
    swiftOptions: SwiftOptions(),
  ),
)
/// Bluetooth adapter state (DTO for platform channel).
enum BluetoothStateDto { unknown, unsupported, unauthorized, off, on }

/// Connection state (DTO for platform channel).
enum ConnectionStateDto { disconnected, connecting, connected, disconnecting }

/// Scan configuration (DTO for platform channel).
class ScanConfigDto {
  /// Service UUIDs to filter by.
  final List<String> serviceUuids;

  /// Timeout in milliseconds (null for no timeout).
  final int? timeoutMs;

  ScanConfigDto({required this.serviceUuids, this.timeoutMs});
}

/// Connect configuration (DTO for platform channel).
class ConnectConfigDto {
  /// Connection timeout in milliseconds.
  final int? timeoutMs;

  /// Requested MTU (ignored on iOS - automatically negotiated).
  final int? mtu;

  ConnectConfigDto({this.timeoutMs, this.mtu});
}

/// A discovered device (DTO for platform channel).
class DeviceDto {
  /// Device ID (UUID on iOS).
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

  ConnectionStateEventDto({required this.deviceId, required this.state});
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
  final int handle;

  DescriptorDto({required this.uuid, required this.handle});
}

/// A characteristic on a remote device (DTO for platform channel).
class CharacteristicDto {
  final String uuid;
  final CharacteristicPropertiesDto properties;
  final List<DescriptorDto> descriptors;
  final int handle;

  CharacteristicDto({
    required this.uuid,
    required this.properties,
    required this.descriptors,
    required this.handle,
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

  MtuChangedEventDto({required this.deviceId, required this.mtu});
}

// === Server (Peripheral) DTOs ===

/// GATT permission flags (DTO for platform channel).
enum GattPermissionDto { read, readEncrypted, write, writeEncrypted }

/// A local descriptor for GATT server (DTO for platform channel).
class LocalDescriptorDto {
  final String uuid;
  final List<GattPermissionDto> permissions;
  final Uint8List? value;
  final int handle;

  LocalDescriptorDto({
    required this.uuid,
    required this.permissions,
    this.value,
    required this.handle,
  });
}

/// A local characteristic for GATT server (DTO for platform channel).
class LocalCharacteristicDto {
  final String uuid;
  final CharacteristicPropertiesDto properties;
  final List<GattPermissionDto> permissions;
  final List<LocalDescriptorDto> descriptors;
  final int handle;

  LocalCharacteristicDto({
    required this.uuid,
    required this.properties,
    required this.permissions,
    required this.descriptors,
    required this.handle,
  });
}

/// A local service for GATT server (DTO for platform channel).
class LocalServiceDto {
  final String uuid;
  final bool isPrimary;
  final List<LocalCharacteristicDto> characteristics;
  final List<LocalServiceDto> includedServices;

  LocalServiceDto({
    required this.uuid,
    required this.isPrimary,
    required this.characteristics,
    required this.includedServices,
  });
}

/// Advertising configuration (DTO for platform channel).
/// Note: iOS has limited advertising support compared to Android.
/// Only name and serviceUuids are supported; manufacturer data is ignored.
class AdvertiseConfigDto {
  final String? name;
  final List<String> serviceUuids;
  final int? manufacturerDataCompanyId;
  final Uint8List? manufacturerData;
  final int? timeoutMs;

  AdvertiseConfigDto({
    this.name,
    required this.serviceUuids,
    this.manufacturerDataCompanyId,
    this.manufacturerData,
    this.timeoutMs,
  });
}

/// A connected central device (DTO for platform channel).
class CentralDto {
  final String id;
  final int mtu;

  CentralDto({required this.id, required this.mtu});
}

/// Read request from a central (DTO for platform channel).
class ReadRequestDto {
  final int requestId;
  final String centralId;
  final String characteristicUuid;
  final int offset;
  final int characteristicHandle;

  ReadRequestDto({
    required this.requestId,
    required this.centralId,
    required this.characteristicUuid,
    required this.offset,
    required this.characteristicHandle,
  });
}

/// Write request from a central (DTO for platform channel).
class WriteRequestDto {
  final int requestId;
  final String centralId;
  final String characteristicUuid;
  final Uint8List value;
  final int offset;
  final bool responseNeeded;
  final int characteristicHandle;

  WriteRequestDto({
    required this.requestId,
    required this.centralId,
    required this.characteristicUuid,
    required this.value,
    required this.offset,
    required this.responseNeeded,
    required this.characteristicHandle,
  });
}

/// GATT status code for responses (DTO for platform channel).
enum GattStatusDto {
  success,
  readNotPermitted,
  writeNotPermitted,
  invalidOffset,
  invalidAttributeLength,
  insufficientAuthentication,
  insufficientEncryption,
  requestNotSupported,
}

/// Severity for a structured log event (DTO for platform channel).
enum LogLevelDto { trace, debug, info, warn, error }

/// A structured log event emitted by the native platform implementation
/// (DTO for platform channel).
class LogEventDto {
  /// Coarse subsystem tag (e.g. `"connection"`, `"gatt_client"`).
  final String context;

  /// Severity of the event.
  final LogLevelDto level;

  /// Human-readable message.
  final String message;

  /// Optional structured key/value context. Values are nullable to allow
  /// callers to mix scalar types without forcing stringification at the
  /// call site.
  final Map<String?, Object?> data;

  /// Optional stable error code (e.g. `"GATT_133"`).
  final String? errorCode;

  /// When the event was produced, as microseconds since Unix epoch.
  final int timestampMicros;

  LogEventDto({
    required this.context,
    required this.level,
    required this.message,
    required this.data,
    this.errorCode,
    required this.timestampMicros,
  });
}

/// Configuration options for the Bluey plugin.
/// Note: Most options are Android-specific and ignored on iOS.
class BlueyConfigDto {
  /// Ignored on iOS (cleanup is handled automatically by the OS).
  final bool cleanupOnActivityDestroy;
  final int? discoverServicesTimeoutMs;
  final int? readCharacteristicTimeoutMs;
  final int? writeCharacteristicTimeoutMs;
  final int? readDescriptorTimeoutMs;
  final int? writeDescriptorTimeoutMs;
  final int? readRssiTimeoutMs;

  BlueyConfigDto({
    this.cleanupOnActivityDestroy = true,
    this.discoverServicesTimeoutMs,
    this.readCharacteristicTimeoutMs,
    this.writeCharacteristicTimeoutMs,
    this.readDescriptorTimeoutMs,
    this.writeDescriptorTimeoutMs,
    this.readRssiTimeoutMs,
  });
}

/// Host API - called from Dart to platform (iOS).
@HostApi()
abstract class BlueyHostApi {
  /// Configure the Bluey plugin behavior.
  @async
  void configure(BlueyConfigDto config);

  /// Get current Bluetooth state.
  @async
  BluetoothStateDto getState();

  /// Request Bluetooth permissions from the user.
  /// Returns true if all required permissions were granted, false otherwise.
  @async
  bool authorize();

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
  @async
  List<ServiceDto> discoverServices(String deviceId);

  /// Read a characteristic value by platform-minted handle.
  @async
  Uint8List readCharacteristic(String deviceId, int characteristicHandle);

  /// Write a characteristic value by platform-minted handle.
  @async
  void writeCharacteristic(
    String deviceId,
    int characteristicHandle,
    Uint8List value,
    bool withResponse,
  );

  /// Enable or disable notifications for a characteristic by handle.
  @async
  void setNotification(
    String deviceId,
    int characteristicHandle,
    bool enable,
  );

  /// Read a descriptor value by platform-minted handle.
  @async
  Uint8List readDescriptor(
    String deviceId,
    int characteristicHandle,
    int descriptorHandle,
  );

  /// Write a descriptor value by platform-minted handle.
  @async
  void writeDescriptor(
    String deviceId,
    int characteristicHandle,
    int descriptorHandle,
    Uint8List value,
  );

  /// Get the maximum write length for a characteristic.
  /// iOS automatically negotiates MTU, so this returns the current negotiated value.
  int getMaximumWriteLength(String deviceId, bool withResponse);

  /// Read the current RSSI for a connected device.
  @async
  int readRssi(String deviceId);

  // === Server (Peripheral) Operations ===

  /// Add a service to the GATT server. Returns the service with all
  /// characteristic and descriptor handles populated.
  @async
  LocalServiceDto addService(LocalServiceDto service);

  /// Remove a service from the GATT server.
  @async
  void removeService(String serviceUuid);

  /// Start advertising.
  @async
  void startAdvertising(AdvertiseConfigDto config);

  /// Stop advertising.
  @async
  void stopAdvertising();

  /// Send a notification to all subscribed centrals, addressed by the
  /// platform-minted handle of a local characteristic.
  @async
  void notifyCharacteristic(int characteristicHandle, Uint8List value);

  /// Send a notification to a specific central, addressed by the
  /// platform-minted handle of a local characteristic.
  @async
  void notifyCharacteristicTo(
    String centralId,
    int characteristicHandle,
    Uint8List value,
  );

  /// Respond to a read request.
  @async
  void respondToReadRequest(
    int requestId,
    GattStatusDto status,
    Uint8List? value,
  );

  /// Respond to a write request.
  @async
  void respondToWriteRequest(int requestId, GattStatusDto status);

  /// Close the GATT server and disconnect all centrals.
  @async
  void closeServer();

  /// Set the minimum severity level for native log events forwarded to Dart.
  ///
  /// Events strictly below [level] are dropped on the native side before
  /// being marshalled across the platform channel.
  @async
  void setLogLevel(LogLevelDto level);
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

  /// MTU changed for a connection (iOS reports this after connection).
  void onMtuChanged(MtuChangedEventDto event);

  // === Server (Peripheral) Callbacks ===

  /// A central device connected to the server.
  void onCentralConnected(CentralDto central);

  /// A central device disconnected from the server.
  void onCentralDisconnected(String centralId);

  /// A read request was received from a central.
  void onReadRequest(ReadRequestDto request);

  /// A write request was received from a central.
  void onWriteRequest(WriteRequestDto request);

  /// A central subscribed to notifications for a characteristic.
  void onCharacteristicSubscribed(String centralId, String characteristicUuid);

  /// A central unsubscribed from notifications for a characteristic.
  void onCharacteristicUnsubscribed(
    String centralId,
    String characteristicUuid,
  );

  /// Remote device's GATT services changed (service added/removed on the server).
  void onServicesChanged(String deviceId);

  /// A structured log event was emitted by the native platform.
  void onLog(LogEventDto event);
}
