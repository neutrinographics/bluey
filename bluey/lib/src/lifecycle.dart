import 'dart:typed_data';

import 'package:bluey_platform_interface/bluey_platform_interface.dart';

/// Internal lifecycle management for Bluey peer-to-peer connections.
///
/// When two Bluey devices connect, the server hosts a hidden control service
/// that the client automatically discovers. The client sends periodic heartbeat
/// writes, and the server uses timeouts to detect disconnection. Before
/// disconnecting, the client writes a disconnect command for immediate cleanup.
///
/// This solves the iOS disconnect detection problem: CoreBluetooth's
/// `CBPeripheralManager` has no callback for client disconnections, and
/// `cancelPeripheralConnection` may not terminate the physical BLE link
/// because iOS treats connections as shared resources across apps and system
/// services. The control service provides reliable, cross-platform disconnect
/// detection without exposing complexity to library consumers.

// UUIDs use the b1e7xxxx prefix ("bley") to avoid collisions with
// Bluetooth SIG assigned UUIDs (which use 0000xxxx).
const _controlServiceUuidString = 'b1e70001-0000-1000-8000-00805f9b34fb';
const _heartbeatCharUuidString = 'b1e70002-0000-1000-8000-00805f9b34fb';
const _intervalCharUuidString = 'b1e70003-0000-1000-8000-00805f9b34fb';

/// UUID of the internal Bluey lifecycle control service.
final controlServiceUuid = _controlServiceUuidString;

/// UUID of the heartbeat characteristic (write-without-response).
final heartbeatCharUuid = _heartbeatCharUuidString;

/// UUID of the interval characteristic (readable, returns server interval).
final intervalCharUuid = _intervalCharUuidString;

/// Value written by the client as a periodic heartbeat.
final heartbeatValue = Uint8List.fromList([0x01]);

/// Value written by the client before disconnecting.
final disconnectValue = Uint8List.fromList([0x00]);

/// Default lifecycle interval.
const defaultLifecycleInterval = Duration(seconds: 10);

/// Checks whether a characteristic UUID belongs to the control service.
bool isControlServiceCharacteristic(String characteristicUuid) {
  final normalized = characteristicUuid.toLowerCase();
  return normalized == _heartbeatCharUuidString ||
      normalized == _intervalCharUuidString;
}

/// Checks whether a service UUID is the control service.
bool isControlService(String serviceUuid) {
  return serviceUuid.toLowerCase() == _controlServiceUuidString;
}

/// Encodes a lifecycle interval as a 4-byte little-endian value in
/// milliseconds, suitable for the interval characteristic response.
Uint8List encodeInterval(Duration interval) {
  final ms = interval.inMilliseconds;
  final bytes = ByteData(4);
  bytes.setInt32(0, ms, Endian.little);
  return bytes.buffer.asUint8List();
}

/// Decodes a 4-byte little-endian interval value (in milliseconds) from the
/// interval characteristic.
Duration decodeInterval(Uint8List bytes) {
  if (bytes.length < 4) {
    return defaultLifecycleInterval;
  }
  final byteData = ByteData.sublistView(bytes);
  final ms = byteData.getInt32(0, Endian.little);
  return Duration(milliseconds: ms);
}

/// Builds the platform-level control service definition.
PlatformLocalService buildControlService() {
  return PlatformLocalService(
    uuid: _controlServiceUuidString,
    isPrimary: true,
    characteristics: [
      PlatformLocalCharacteristic(
        uuid: _heartbeatCharUuidString,
        properties: const PlatformCharacteristicProperties(
          canRead: false,
          canWrite: true,
          canWriteWithoutResponse: true,
          canNotify: false,
          canIndicate: false,
        ),
        permissions: const [
          PlatformGattPermission.write,
        ],
        descriptors: const [],
      ),
      PlatformLocalCharacteristic(
        uuid: _intervalCharUuidString,
        properties: const PlatformCharacteristicProperties(
          canRead: true,
          canWrite: false,
          canWriteWithoutResponse: false,
          canNotify: false,
          canIndicate: false,
        ),
        permissions: const [
          PlatformGattPermission.read,
        ],
        descriptors: const [],
      ),
    ],
    includedServices: const [],
  );
}
