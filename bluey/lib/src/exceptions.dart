import 'uuid.dart';

/// Base class for all Bluey exceptions.
///
/// This is a sealed class following DDD principles. All Bluey exceptions
/// extend this base to enable exhaustive pattern matching.
sealed class BlueyException implements Exception {
  final String message;
  final String? action;
  final Object? cause;

  const BlueyException(this.message, {this.action, this.cause});

  @override
  String toString() => 'BlueyException: $message';
}

// === State Exceptions ===

/// Bluetooth is not available on this device.
class BluetoothUnavailableException extends BlueyException {
  const BluetoothUnavailableException()
    : super(
        'Bluetooth is not available on this device',
        action: 'This device does not support Bluetooth LE',
      );
}

/// Bluetooth is turned off.
class BluetoothDisabledException extends BlueyException {
  const BluetoothDisabledException()
    : super(
        'Bluetooth is turned off',
        action: 'Call bluey.requestEnable() or direct user to Settings',
      );
}

/// Required permissions not granted.
class PermissionDeniedException extends BlueyException {
  final List<String> permissions;

  PermissionDeniedException(this.permissions)
    : super(
        'Required permissions not granted: ${permissions.join(", ")}',
        action: 'Request permissions or direct user to Settings',
      );
}

// === Connection Exceptions ===

/// Reasons why a connection attempt might fail.
enum ConnectionFailureReason {
  timeout,
  deviceNotFound,
  deviceNotConnectable,
  pairingFailed,
  connectionLimitReached,
  unknown,
}

/// Failed to connect to device.
class ConnectionException extends BlueyException {
  final UUID deviceId;
  final ConnectionFailureReason reason;

  const ConnectionException(this.deviceId, this.reason)
    : super(
        'Failed to connect to device: $reason',
        action: 'Check device is in range and advertising',
      );
}

/// Reasons why a device might disconnect.
enum DisconnectReason {
  requested, // disconnect() was called
  remoteDisconnect, // Remote device disconnected
  linkLoss, // Connection lost (out of range, etc.)
  timeout, // Operation timeout
  unknown,
}

/// Connection was lost unexpectedly.
class DisconnectedException extends BlueyException {
  final UUID deviceId;
  final DisconnectReason reason;

  const DisconnectedException(this.deviceId, this.reason)
    : super('Device disconnected: $reason', action: 'Reconnect if needed');
}

// === GATT Exceptions ===

/// Service not found on device.
class ServiceNotFoundException extends BlueyException {
  final UUID serviceUuid;

  const ServiceNotFoundException(this.serviceUuid)
    : super(
        'Service not found: $serviceUuid',
        action: 'Verify device supports this service',
      );
}

/// Characteristic not found in service.
class CharacteristicNotFoundException extends BlueyException {
  final UUID characteristicUuid;

  const CharacteristicNotFoundException(this.characteristicUuid)
    : super(
        'Characteristic not found: $characteristicUuid',
        action: 'Verify service contains this characteristic',
      );
}

/// GATT operation status codes.
enum GattStatus {
  success,
  readNotPermitted,
  writeNotPermitted,
  invalidOffset,
  invalidAttributeLength,
  insufficientAuthentication,
  insufficientEncryption,
  requestNotSupported,
}

/// GATT operation failed.
class GattException extends BlueyException {
  final GattStatus status;

  const GattException(this.status)
    : super(
        'GATT operation failed: $status',
        action: 'Retry operation or check permissions',
      );
}

/// Operation not supported by this characteristic.
class OperationNotSupportedException extends BlueyException {
  final String operation; // 'read', 'write', 'notify'

  const OperationNotSupportedException(this.operation)
    : super(
        'Operation "$operation" not supported by this characteristic',
        action: 'Check characteristic properties before calling',
      );
}

// === Server Exceptions ===

/// Reasons why advertising might fail.
enum AdvertisingFailureReason {
  alreadyAdvertising,
  dataTooBig,
  notSupported,
  hardwareError,
  unknown,
}

/// Failed to start advertising.
class AdvertisingException extends BlueyException {
  final AdvertisingFailureReason reason;

  const AdvertisingException(this.reason)
    : super(
        'Failed to start advertising: $reason',
        action: 'Check advertising data size and hardware support',
      );
}

// === Platform Exceptions ===

/// Operation not supported on this platform.
class UnsupportedOperationException extends BlueyException {
  final String operation;
  final String platform;

  const UnsupportedOperationException(this.operation, this.platform)
    : super(
        'Operation "$operation" is not supported on $platform',
        action: 'Check bluey.capabilities before calling',
      );
}

/// Generic platform exception for errors that don't fit other categories.
class BlueyPlatformException extends BlueyException {
  BlueyPlatformException(String message, {Object? cause})
    : super(message, cause: cause);
}
