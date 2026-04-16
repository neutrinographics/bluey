import 'dart:typed_data';

import 'package:bluey_platform_interface/bluey_platform_interface.dart';

import 'peer/server_id.dart';

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
const _serverIdCharUuidString = 'b1e70004-0000-1000-8000-00805f9b34fb';

/// UUID of the internal Bluey lifecycle control service.
final controlServiceUuid = _controlServiceUuidString;

/// UUID of the heartbeat characteristic (write-with-response).
final heartbeatCharUuid = _heartbeatCharUuidString;

/// UUID of the interval characteristic (readable, returns server interval).
final intervalCharUuid = _intervalCharUuidString;

/// UUID of the serverId characteristic (readable, returns the server's
/// stable [ServerId] as 16 raw bytes).
final serverIdCharUuid = _serverIdCharUuidString;

/// Value written by the client as a periodic heartbeat.
final heartbeatValue = Uint8List.fromList([0x01]);

/// Value written by the client before disconnecting.
final disconnectValue = Uint8List.fromList([0x00]);

/// Default lifecycle interval.
const defaultLifecycleInterval = Duration(seconds: 10);

/// BLE company ID used in the Bluey advertisement marker.
/// 0xFFFF is reserved for testing/internal use per the Bluetooth spec.
const blueyCompanyId = 0xFFFF;

/// Magic bytes identifying a Bluey server in manufacturer data.
/// Spells "bley" in hex (b1e7).
final blueyMarkerData = Uint8List.fromList([0xB1, 0xE7]);

/// Returns true if the given manufacturer data identifies a Bluey server.
bool isBlueyManufacturerData(int? companyId, List<int>? data) {
  if (companyId != blueyCompanyId) return false;
  if (data == null || data.length < 2) return false;
  return data[0] == 0xB1 && data[1] == 0xE7;
}

/// Checks whether a characteristic UUID belongs to the control service.
bool isControlServiceCharacteristic(String characteristicUuid) {
  final normalized = characteristicUuid.toLowerCase();
  return normalized == _heartbeatCharUuidString ||
      normalized == _intervalCharUuidString ||
      normalized == _serverIdCharUuidString;
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

/// Encodes a [ServerId] as 16 raw bytes for the serverId characteristic.
Uint8List encodeServerId(ServerId id) => id.toBytes();

/// Decodes a 16-byte serverId characteristic value.
ServerId decodeServerId(Uint8List bytes) => ServerId.fromBytes(bytes);

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
          canWriteWithoutResponse: false,
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
      PlatformLocalCharacteristic(
        uuid: _serverIdCharUuidString,
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
