import 'dart:typed_data';

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

  const PlatformConnectConfig({required this.timeoutMs, required this.mtu});

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

/// Characteristic properties from the platform layer.
@immutable
class PlatformCharacteristicProperties {
  final bool canRead;
  final bool canWrite;
  final bool canWriteWithoutResponse;
  final bool canNotify;
  final bool canIndicate;

  const PlatformCharacteristicProperties({
    required this.canRead,
    required this.canWrite,
    required this.canWriteWithoutResponse,
    required this.canNotify,
    required this.canIndicate,
  });
}

/// A descriptor from the platform layer.
@immutable
class PlatformDescriptor {
  final String uuid;

  const PlatformDescriptor({required this.uuid});
}

/// A characteristic from the platform layer.
@immutable
class PlatformCharacteristic {
  final String uuid;
  final PlatformCharacteristicProperties properties;
  final List<PlatformDescriptor> descriptors;

  const PlatformCharacteristic({
    required this.uuid,
    required this.properties,
    required this.descriptors,
  });
}

/// A service from the platform layer.
@immutable
class PlatformService {
  final String uuid;
  final bool isPrimary;
  final List<PlatformCharacteristic> characteristics;
  final List<PlatformService> includedServices;

  const PlatformService({
    required this.uuid,
    required this.isPrimary,
    required this.characteristics,
    required this.includedServices,
  });
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

/// Configuration options for the Bluey plugin.
///
/// Use this class to customize plugin behavior on platforms that support it.
@immutable
class BlueyConfig {
  /// Whether to automatically clean up BLE resources when the activity is destroyed.
  ///
  /// When enabled (default), the plugin will automatically:
  /// - Stop advertising
  /// - Close the GATT server
  /// - Disconnect all connected centrals
  ///
  /// This prevents "zombie" BLE connections that persist after the app is closed.
  ///
  /// Set to `false` if you want to manage cleanup manually by calling
  /// [BlueyPlatform.closeServer] yourself. This is useful if you need more
  /// control over when cleanup happens, such as keeping connections alive
  /// during configuration changes.
  ///
  /// **Note:** This option only affects Android. On iOS, the OS handles
  /// BLE cleanup automatically when the app is terminated.
  ///
  /// Default: `true`
  final bool cleanupOnActivityDestroy;

  /// Creates a configuration for the Bluey plugin.
  ///
  /// All parameters have sensible defaults and are optional.
  const BlueyConfig({this.cleanupOnActivityDestroy = true});

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BlueyConfig &&
        other.cleanupOnActivityDestroy == cleanupOnActivityDestroy;
  }

  @override
  int get hashCode => cleanupOnActivityDestroy.hashCode;
}

/// Platform-specific implementation interface.
///
/// This follows the Clean Architecture pattern. Each platform
/// (Android, iOS, etc.) implements this interface.
abstract base class BlueyPlatform extends PlatformInterface {
  static final Object _token = Object();

  /// Constructs a [BlueyPlatform].
  BlueyPlatform.impl() : super(token: _token);

  static BlueyPlatform? _instance;

  /// The default instance of [BlueyPlatform] to use.
  static BlueyPlatform get instance {
    final instance = _instance;
    if (instance == null) {
      throw UnimplementedError(
        'bluey is not implemented on this platform. '
        'Did you forget to add bluey_android or bluey_ios to your dependencies?',
      );
    }
    return instance;
  }

  /// Platform-specific implementations should set this with their own
  /// instance when they register themselves.
  static set instance(BlueyPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Configure the Bluey plugin behavior.
  ///
  /// Call this early in your app lifecycle to customize plugin behavior.
  /// See [BlueyConfig] for available options.
  ///
  /// Example:
  /// ```dart
  /// await BlueyPlatform.instance.configure(
  ///   const BlueyConfig(cleanupOnActivityDestroy: false),
  /// );
  /// ```
  Future<void> configure(BlueyConfig config);

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

  /// Request Bluetooth permissions from the user.
  /// Returns true if all required permissions were granted, false otherwise.
  Future<bool> authorize();

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

  // === GATT Operations ===

  /// Discover services on a connected device.
  Future<List<PlatformService>> discoverServices(String deviceId);

  /// Read a characteristic value.
  Future<Uint8List> readCharacteristic(
    String deviceId,
    String characteristicUuid,
  );

  /// Write a characteristic value.
  Future<void> writeCharacteristic(
    String deviceId,
    String characteristicUuid,
    Uint8List value,
    bool withResponse,
  );

  /// Enable or disable notifications for a characteristic.
  Future<void> setNotification(
    String deviceId,
    String characteristicUuid,
    bool enable,
  );

  /// Stream of characteristic notifications.
  Stream<PlatformNotification> notificationStream(String deviceId);

  /// Read a descriptor value.
  Future<Uint8List> readDescriptor(String deviceId, String descriptorUuid);

  /// Write a descriptor value.
  Future<void> writeDescriptor(
    String deviceId,
    String descriptorUuid,
    Uint8List value,
  );

  /// Request a specific MTU.
  Future<int> requestMtu(String deviceId, int mtu);

  /// Read the current RSSI for a connected device.
  Future<int> readRssi(String deviceId);

  // === Server (Peripheral) Operations ===

  /// Add a service to the GATT server.
  Future<void> addService(PlatformLocalService service);

  /// Remove a service from the GATT server.
  Future<void> removeService(String serviceUuid);

  /// Start advertising.
  Future<void> startAdvertising(PlatformAdvertiseConfig config);

  /// Stop advertising.
  Future<void> stopAdvertising();

  /// Send a notification to all subscribed centrals.
  Future<void> notifyCharacteristic(String characteristicUuid, Uint8List value);

  /// Send a notification to a specific central.
  Future<void> notifyCharacteristicTo(
    String centralId,
    String characteristicUuid,
    Uint8List value,
  );

  /// Stream of connected centrals.
  Stream<PlatformCentral> get centralConnections;

  /// Stream of central disconnections.
  Stream<String> get centralDisconnections;

  /// Stream of read requests from centrals.
  Stream<PlatformReadRequest> get readRequests;

  /// Stream of write requests from centrals.
  Stream<PlatformWriteRequest> get writeRequests;

  /// Respond to a read request.
  Future<void> respondToReadRequest(
    int requestId,
    PlatformGattStatus status,
    Uint8List? value,
  );

  /// Respond to a write request.
  Future<void> respondToWriteRequest(int requestId, PlatformGattStatus status);

  /// Disconnect a central from the server.
  Future<void> disconnectCentral(String centralId);

  /// Close the GATT server and disconnect all centrals.
  ///
  /// Call this when the server is no longer needed to release resources
  /// and properly terminate BLE connections. This is especially important
  /// on Android where BLE connections can persist after the app closes.
  ///
  /// After calling this, the server instance should not be reused.
  Future<void> closeServer();
}

/// A notification from a characteristic.
@immutable
class PlatformNotification {
  final String deviceId;
  final String characteristicUuid;
  final Uint8List value;

  const PlatformNotification({
    required this.deviceId,
    required this.characteristicUuid,
    required this.value,
  });
}

// === Server (Peripheral) Platform Types ===

/// GATT permission flags for the platform layer.
enum PlatformGattPermission { read, readEncrypted, write, writeEncrypted }

/// A local descriptor for GATT server (platform layer).
@immutable
class PlatformLocalDescriptor {
  final String uuid;
  final List<PlatformGattPermission> permissions;
  final Uint8List? value;

  const PlatformLocalDescriptor({
    required this.uuid,
    required this.permissions,
    this.value,
  });
}

/// A local characteristic for GATT server (platform layer).
@immutable
class PlatformLocalCharacteristic {
  final String uuid;
  final PlatformCharacteristicProperties properties;
  final List<PlatformGattPermission> permissions;
  final List<PlatformLocalDescriptor> descriptors;

  const PlatformLocalCharacteristic({
    required this.uuid,
    required this.properties,
    required this.permissions,
    required this.descriptors,
  });
}

/// A local service for GATT server (platform layer).
@immutable
class PlatformLocalService {
  final String uuid;
  final bool isPrimary;
  final List<PlatformLocalCharacteristic> characteristics;
  final List<PlatformLocalService> includedServices;

  const PlatformLocalService({
    required this.uuid,
    required this.isPrimary,
    required this.characteristics,
    required this.includedServices,
  });
}

/// Advertising configuration (platform layer).
@immutable
class PlatformAdvertiseConfig {
  final String? name;
  final List<String> serviceUuids;
  final int? manufacturerDataCompanyId;
  final Uint8List? manufacturerData;
  final int? timeoutMs;

  const PlatformAdvertiseConfig({
    this.name,
    required this.serviceUuids,
    this.manufacturerDataCompanyId,
    this.manufacturerData,
    this.timeoutMs,
  });
}

/// A connected central device (platform layer).
@immutable
class PlatformCentral {
  final String id;
  final int mtu;

  const PlatformCentral({required this.id, required this.mtu});
}

/// Read request from a central (platform layer).
@immutable
class PlatformReadRequest {
  final int requestId;
  final String centralId;
  final String characteristicUuid;
  final int offset;

  const PlatformReadRequest({
    required this.requestId,
    required this.centralId,
    required this.characteristicUuid,
    required this.offset,
  });
}

/// Write request from a central (platform layer).
@immutable
class PlatformWriteRequest {
  final int requestId;
  final String centralId;
  final String characteristicUuid;
  final Uint8List value;
  final int offset;
  final bool responseNeeded;

  const PlatformWriteRequest({
    required this.requestId,
    required this.centralId,
    required this.characteristicUuid,
    required this.value,
    required this.offset,
    required this.responseNeeded,
  });
}

/// GATT status code for responses (platform layer).
enum PlatformGattStatus {
  success,
  readNotPermitted,
  writeNotPermitted,
  invalidOffset,
  invalidAttributeLength,
  insufficientAuthentication,
  insufficientEncryption,
  requestNotSupported,
}
