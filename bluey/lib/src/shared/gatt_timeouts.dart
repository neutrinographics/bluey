import 'package:meta/meta.dart';

/// Configurable timeouts for GATT operations.
///
/// All parameters are optional with sensible defaults. Pass to
/// [Bluey.configure] to customize timeout behavior.
///
/// Note: [requestMtu] only applies on Android. iOS auto-negotiates MTU.
@immutable
class GattTimeouts {
  /// Timeout for service discovery.
  final Duration discoverServices;

  /// Timeout for reading a characteristic value.
  final Duration readCharacteristic;

  /// Timeout for writing a characteristic value (with response).
  final Duration writeCharacteristic;

  /// Timeout for reading a descriptor value.
  final Duration readDescriptor;

  /// Timeout for writing a descriptor value.
  final Duration writeDescriptor;

  /// Timeout for MTU negotiation (Android only).
  final Duration requestMtu;

  /// Timeout for reading RSSI.
  final Duration readRssi;

  const GattTimeouts({
    this.discoverServices = const Duration(seconds: 15),
    this.readCharacteristic = const Duration(seconds: 10),
    this.writeCharacteristic = const Duration(seconds: 10),
    this.readDescriptor = const Duration(seconds: 10),
    this.writeDescriptor = const Duration(seconds: 10),
    this.requestMtu = const Duration(seconds: 10),
    this.readRssi = const Duration(seconds: 5),
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GattTimeouts &&
        other.discoverServices == discoverServices &&
        other.readCharacteristic == readCharacteristic &&
        other.writeCharacteristic == writeCharacteristic &&
        other.readDescriptor == readDescriptor &&
        other.writeDescriptor == writeDescriptor &&
        other.requestMtu == requestMtu &&
        other.readRssi == readRssi;
  }

  @override
  int get hashCode => Object.hash(
    discoverServices,
    readCharacteristic,
    writeCharacteristic,
    readDescriptor,
    writeDescriptor,
    requestMtu,
    readRssi,
  );
}
