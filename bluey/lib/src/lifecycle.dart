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

/// Default lifecycle interval.
const defaultLifecycleInterval = Duration(seconds: 10);

/// Default peer-silence timeout for the death watch in `LifecycleClient`.
///
/// Chosen to be strictly longer than the typical OS link-supervision
/// timeout (~20 seconds on Android per AOSP defaults, comparable on
/// iOS) so that on genuine link loss the platform's own disconnect
/// path fires first and the application-level silence detector
/// converges via the queue-drain rather than racing the OS. See
/// Bluetooth Core Spec 5.4 Vol 6 Part B §4.5.2 (Link Supervision
/// Timeout) for the upstream constraint.
const defaultPeerSilenceTimeout = Duration(seconds: 30);

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

/// Current wire-format version for all lifecycle protocol payloads
/// (heartbeat / disconnect writes and the advertised-identity read).
///
/// Bump this when an incompatible change is made; decoders reject payloads
/// whose leading byte does not equal the version they understand.
const protocolVersion = 0x01;

const _markerHeartbeat = 0x01;
const _markerCourtesyDisconnect = 0x00;

/// A message exchanged on the lifecycle control characteristic.
///
/// The published-language type for the Bluey peer protocol's heartbeat
/// channel: a sealed family with one variant per wire intent. The
/// [senderId] field carries the writer's stable [ServerId] so the
/// receiver learns who is on the other end of the link.
sealed class LifecycleMessage {
  const LifecycleMessage(this.senderId);

  /// The stable [ServerId] of the sender — i.e., the central writing
  /// the heartbeat or disconnect.
  final ServerId senderId;
}

/// Periodic liveness write from a connected central.
class Heartbeat extends LifecycleMessage {
  const Heartbeat(super.senderId);
}

/// Cooperative shutdown write sent by a central before tearing down
/// the link, so the server can release resources without waiting for
/// the heartbeat-silence timeout.
class CourtesyDisconnect extends LifecycleMessage {
  const CourtesyDisconnect(super.senderId);
}

/// Thrown when a lifecycle payload cannot be parsed (wrong length,
/// unknown marker, etc.). Distinct from [UnsupportedLifecycleProtocolVersion]
/// so callers can decide whether to log-and-drop or surface the error.
class MalformedLifecycleMessage implements Exception {
  const MalformedLifecycleMessage(this.reason);
  final String reason;

  @override
  String toString() => 'MalformedLifecycleMessage: $reason';
}

/// Thrown when a lifecycle payload's version byte does not match the
/// version this build understands.
class UnsupportedLifecycleProtocolVersion implements Exception {
  const UnsupportedLifecycleProtocolVersion(this.version);
  final int version;

  @override
  String toString() =>
      'UnsupportedLifecycleProtocolVersion: 0x'
      '${version.toRadixString(16).padLeft(2, '0')}';
}

/// Encoder/decoder for the lifecycle protocol's wire format.
///
/// Stateless. Keep encoding/decoding co-located so wire-format changes
/// are a single-file edit and unit-tested in one place.
class LifecycleCodec {
  const LifecycleCodec();

  /// Encodes a [LifecycleMessage] as `version | marker | senderId(16)`
  /// (18 bytes total). Suitable for writing to the heartbeat
  /// characteristic.
  Uint8List encodeMessage(LifecycleMessage message) {
    final buf = Uint8List(18);
    buf[0] = protocolVersion;
    buf[1] = switch (message) {
      Heartbeat _ => _markerHeartbeat,
      CourtesyDisconnect _ => _markerCourtesyDisconnect,
    };
    buf.setRange(2, 18, message.senderId.toBytes());
    return buf;
  }

  /// Decodes an 18-byte heartbeat-channel write into a [LifecycleMessage].
  ///
  /// Throws [MalformedLifecycleMessage] for wrong-length or unknown-marker
  /// payloads, [UnsupportedLifecycleProtocolVersion] for an unrecognized
  /// version byte.
  LifecycleMessage decodeMessage(Uint8List bytes) {
    if (bytes.length != 18) {
      throw MalformedLifecycleMessage('expected 18 bytes, got ${bytes.length}');
    }
    if (bytes[0] != protocolVersion) {
      throw UnsupportedLifecycleProtocolVersion(bytes[0]);
    }
    final senderId = ServerId.fromBytes(
      Uint8List.fromList(bytes.sublist(2, 18)),
    );
    return switch (bytes[1]) {
      _markerHeartbeat => Heartbeat(senderId),
      _markerCourtesyDisconnect => CourtesyDisconnect(senderId),
      final m =>
        throw MalformedLifecycleMessage(
          'unknown marker 0x${m.toRadixString(16).padLeft(2, '0')}',
        ),
    };
  }

  /// Encodes a server's stable identity as `version | serverId(16)`
  /// (17 bytes total). Returned from the advertised-identity read
  /// characteristic.
  Uint8List encodeAdvertisedIdentity(ServerId id) {
    final buf = Uint8List(17);
    buf[0] = protocolVersion;
    buf.setRange(1, 17, id.toBytes());
    return buf;
  }

  /// Decodes a 17-byte advertised-identity payload into a [ServerId].
  ///
  /// Throws [MalformedLifecycleMessage] for wrong-length payloads,
  /// [UnsupportedLifecycleProtocolVersion] for an unrecognized version byte.
  ServerId decodeAdvertisedIdentity(Uint8List bytes) {
    if (bytes.length != 17) {
      throw MalformedLifecycleMessage('expected 17 bytes, got ${bytes.length}');
    }
    if (bytes[0] != protocolVersion) {
      throw UnsupportedLifecycleProtocolVersion(bytes[0]);
    }
    return ServerId.fromBytes(Uint8List.fromList(bytes.sublist(1, 17)));
  }
}

/// Default singleton codec instance. The codec is stateless; reuse
/// this rather than constructing your own.
const lifecycleCodec = LifecycleCodec();

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
        permissions: const [PlatformGattPermission.write],
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
        permissions: const [PlatformGattPermission.read],
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
        permissions: const [PlatformGattPermission.read],
        descriptors: const [],
      ),
    ],
    includedServices: const [],
  );
}
