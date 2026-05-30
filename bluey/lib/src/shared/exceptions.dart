import '../discovery/device_address.dart';
import '../gatt_server/client_address.dart';
import '../peer/server_id.dart';
import '../platform/bluetooth_state.dart';
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
  final DeviceAddress deviceAddress;
  final ConnectionFailureReason reason;

  const ConnectionException(this.deviceAddress, this.reason)
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

/// Connection was lost unexpectedly. [address] is the raw platform
/// identifier of the endpoint that disconnected (device or client) — a
/// leaf diagnostic value, opaque, do not parse.
class DisconnectedException extends BlueyException {
  final String address;
  final DisconnectReason reason;

  const DisconnectedException(this.address, this.reason)
    : super('Device disconnected: $reason', action: 'Reconnect if needed');
}

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

/// Two or more attributes share the same UUID, so a singular accessor
/// (`Connection.service`, `RemoteService.characteristic`, or
/// `RemoteCharacteristic.descriptor`) cannot pick a unique target.
///
/// Thrown instead of silently returning the first match — a peripheral
/// that legitimately exposes multiple services or characteristics with
/// the same UUID would otherwise cause every read/write/notify on the
/// "wrong" instance, with no signal to the caller. The disambiguation
/// path is the plural accessor: `service.characteristics(uuid: ...)`,
/// `characteristic.descriptors(uuid: ...)`, or
/// `(await connection.services()).where((s) => s.uuid == uuid)`. From
/// there, pick the intended attribute by its `handle` (which is
/// guaranteed unique within the connection).
class AmbiguousAttributeException extends BlueyException {
  /// The UUID that resolved to more than one attribute.
  final UUID uuid;

  /// How many attributes share this UUID.
  final int matchCount;

  /// The kind of attribute that was ambiguous: `'service'`,
  /// `'characteristic'`, or `'descriptor'`. Drives the recommended
  /// plural accessor in [BlueyException.action].
  final String attributeKind;

  AmbiguousAttributeException(
    this.uuid,
    this.matchCount, {
    required this.attributeKind,
  }) : super(
         '$matchCount $attributeKind'
         's share UUID $uuid; '
         'singular accessor cannot disambiguate. '
         '${_actionFor(attributeKind)}',
         action: _actionFor(attributeKind),
       );

  static String _actionFor(String kind) {
    switch (kind) {
      case 'service':
        return 'Use (await connection.services()).where((s) => s.uuid == uuid) '
            'and pick by handle.';
      case 'characteristic':
        return 'Use service.characteristics(uuid: uuid) and pick by handle.';
      case 'descriptor':
        return 'Use characteristic.descriptors(uuid: uuid) and pick by handle.';
      default:
        return 'Use the plural accessor and pick by handle.';
    }
  }
}

/// A GATT operation was issued with an attribute handle that the
/// platform side no longer recognises because the peer fired a
/// Service Changed event (Android `onServiceChanged`; iOS
/// `peripheral(_, didModifyServices:)`) and the handle table that
/// minted the handle has since been cleared.
///
/// The connection itself is still live — only the discovered service
/// tree is stale. Recovery: call `connection.services()` again to
/// re-discover and acquire fresh handles, then reissue the op against
/// the new attribute references.
///
/// Distinct from [AttributeNotFoundException] (handle never existed
/// or refers to a different connection) and [DisconnectedException]
/// (the link itself is gone).
class AttributeHandleInvalidatedException extends BlueyException {
  AttributeHandleInvalidatedException()
    : super(
        'GATT attribute handle invalidated by Service Changed; '
        're-discover services to obtain fresh handles.',
        action:
            'Call connection.services() to re-discover, then '
            'reissue the op against the new attribute references.',
      );
}

/// A GATT operation referenced an attribute handle the platform side
/// could not resolve, but it was not invalidated by a Service Changed
/// event. Indicates a programmer error — for example, passing a handle
/// minted on connection A to an op issued on connection B, or holding
/// an attribute reference past disconnect.
///
/// Distinct from [AttributeHandleInvalidatedException], which carries
/// the specific "Service Changed cleared the handle table" semantics
/// and points the caller at re-discovery as the recovery path.
class AttributeNotFoundException extends BlueyException {
  AttributeNotFoundException()
    : super(
        'GATT attribute handle not found on the platform side.',
        action:
            'Verify the handle was obtained from this connection '
            'and has not outlived its parent service tree.',
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

/// A GATT operation (read, write, discoverServices, descriptor read/write,
/// MTU/RSSI request, or notification subscribe) did not complete within its
/// configured timeout.
///
/// Indicates the remote device may be unreachable. Callers should check
/// [Connection.state] before retrying; in many cases the remote has gone
/// out of range or stopped responding and the connection will tear down
/// shortly via the lifecycle heartbeat.
class GattTimeoutException extends BlueyException {
  /// Name of the GATT operation that timed out, e.g. `'writeCharacteristic'`.
  final String operation;

  const GattTimeoutException(this.operation)
    : super(
        'GATT operation "$operation" timed out',
        action: 'Check Connection.state; the remote device may be unreachable.',
      );
}

/// A GATT operation completed but the peer returned a non-success status
/// code — the request reached the peer and a response came back, but the
/// response was a protocol-level error.
///
/// Distinct from [GattTimeoutException] (no response) and [DisconnectedException]
/// with [DisconnectReason.linkLoss] (link dropped before response).
///
/// The [status] is the native GATT status code (e.g. Android's
/// `BluetoothGatt.GATT_*` constants: `0x01` = invalid handle, `0x03` =
/// write not permitted, `0x05` = insufficient authentication, `0x08` =
/// connection timeout). Callers can use it to distinguish recoverable
/// errors (bonding required) from terminal ones (peer removed the
/// characteristic via Service Changed and is no longer responding).
class GattOperationFailedException extends BlueyException {
  /// Name of the GATT operation that failed, e.g. `'writeCharacteristic'`.
  final String operation;

  /// Native GATT status code returned by the peer.
  final int status;

  const GattOperationFailedException(this.operation, this.status)
    : super(
        'GATT operation "$operation" failed with status $status',
        action:
            'Inspect status; retry, request bonding, or disconnect depending on the code.',
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

/// Server-side respond to a [ReadRequest] or [WriteRequest] failed at the
/// platform layer.
///
/// Most common cause: the central disconnected after sending the request
/// but before the server-side handler called `respondToRead` /
/// `respondToWrite`, so the platform has no pending request matching the
/// supplied id. Android surfaces this as ATT status `0x0A` (NoPendingRequest).
///
/// Distinct from [GattOperationFailedException], which is a *client-side*
/// failure (peer rejected our write with a non-success ATT status).
/// `ServerRespondFailedException` is *server-side*: we tried to reply and
/// the platform refused. Typical caller response is "log it and move on" —
/// there's no recipient left to retry against.
class ServerRespondFailedException extends BlueyException {
  /// Which respond method failed: `'respondToRead'` or `'respondToWrite'`.
  final String operation;

  /// Native ATT status code returned by the platform. Android uses ATT
  /// codes directly (e.g. `0x0A` NoPendingRequest after a central drops
  /// mid-transaction). iOS adapts CoreBluetooth errors to ATT-like codes
  /// in the same range.
  final int status;

  /// Address of the central ([Client.address]) whose request could not be
  /// responded to. The client may already be disconnected; consumers
  /// should not assume it is still live.
  final ClientAddress clientAddress;

  /// UUID of the characteristic the original request targeted. Useful
  /// for correlating with consumer-side request tracking.
  final UUID characteristicId;

  ServerRespondFailedException({
    required this.operation,
    required this.status,
    required this.clientAddress,
    required this.characteristicId,
  }) : super(
         'Server "$operation" failed for client $clientAddress on '
         'characteristic $characteristicId (ATT status $status)',
         action:
             'The central likely disconnected before the response '
             'could be delivered; safe to log and move on.',
       );
}

/// The platform plugin no longer has the `requestId` referenced in a
/// `respondToReadRequest` / `respondToWriteRequest` call.
///
/// Indicates an *expected race*: the most likely cause is a duplicate
/// response on the Dart side (e.g. the platform's broadcast
/// `readRequests` stream had two subscribers, both invoked
/// `respondToReadRequest` with the same id; the second one hits "not
/// found"). The lifecycle server logs this at warn level and continues.
/// Apps should not need to react to it directly. See I322 for the
/// duplicate-response root-cause investigation.
class RespondNotFoundException extends BlueyException {
  const RespondNotFoundException(String message)
    : super(
        'Server respond failed: $message',
        action:
            'Likely a duplicate response on the Dart side (broadcast '
            'stream multi-subscription); safe to log and continue.',
      );

  @override
  String toString() => 'RespondNotFoundException: $message';
}

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

/// No peer with the expected [ServerId] was found within the timeout.
class PeerNotFoundException extends BlueyException {
  final ServerId expected;
  final Duration timeout;

  PeerNotFoundException(this.expected, this.timeout)
    : super('No peer with id $expected found within $timeout.');
}

/// The connected device is not a Bluey peer — it does not host the
/// lifecycle control service required to participate in the peer
/// protocol.
///
/// Thrown by `Bluey.connectAsPeer` when a connection completes but the
/// remote device does not advertise the Bluey control service. The
/// underlying GATT connection is closed before this exception is
/// raised, so callers do not need to perform additional cleanup.
class NotABlueyPeerException extends BlueyException {
  /// Address of the device that connected but turned out not to be
  /// a Bluey peer.
  final DeviceAddress deviceAddress;

  NotABlueyPeerException(this.deviceAddress)
    : super(
        'Device $deviceAddress is not a Bluey peer '
        '(no lifecycle control service)',
        action:
            'Use Bluey.connect for non-Bluey devices, or '
            'Bluey.tryUpgrade if you already hold a Connection.',
      );

  @override
  String toString() =>
      'NotABlueyPeerException: device $deviceAddress is not a '
      'Bluey peer (no lifecycle control service)';
}

/// Thrown when a peer-protocol API is called on a [Bluey] instance
/// that was constructed without a `localIdentity`.
///
/// The lifecycle protocol requires both sides of a connection to
/// announce their stable [ServerId]; a [Bluey] without a configured
/// identity cannot participate. Construct
/// `Bluey.create(localIdentity: ...)` to fix.
class LocalIdentityRequiredException extends BlueyException {
  const LocalIdentityRequiredException(String operation)
    : super(
        'Bluey was constructed without a localIdentity but $operation '
        'requires one.',
        action:
            'Construct Bluey.create(localIdentity: ServerId.generate()) — '
            'or a persisted ServerId — and reuse it across sessions.',
      );
}

/// The peer's [ServerId] did not match the expected value.
class PeerIdentityMismatchException extends BlueyException {
  final ServerId expected;
  final ServerId actual;

  PeerIdentityMismatchException(this.expected, this.actual)
    : super('Peer identity mismatch: expected $expected but got $actual.');
}

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
///
/// [code] is the platform-originated error code (e.g. a Pigeon error code
/// like `'bluey-unknown'`, or an iOS `NSError`/`PlatformException` code
/// pass-through from the defensive catch-all in `_runGattOp`). Null when
/// the exception is constructed without a known code.
class BlueyPlatformException extends BlueyException {
  final String? code;

  BlueyPlatformException(String message, {this.code, Object? cause})
    : super(message, cause: cause);
}

/// The kind of instance that was invalidated. Used by
/// [StaleHandleException] to surface the right type in messages and
/// diagnostics without primitive-obsession on a free-form string.
enum InvalidatedInstance {
  server('Server'),
  connection('Connection'),
  scanner('Scanner');

  /// Display name used in user-facing exception messages.
  final String displayName;

  const InvalidatedInstance(this.displayName);
}

/// A method was called on a [Server], [Connection], or [Scanner]
/// instance that was invalidated by a prior Bluetooth-adapter state
/// transition (e.g. the user toggled Bluetooth off).
///
/// Invalidation is **terminal**: the instance is dead and will not
/// recover even if the adapter returns to [BluetoothState.on]. Construct
/// a fresh instance from [Bluey] to proceed:
///
/// ```dart
/// try {
///   await server.addService(...);
/// } on StaleHandleException {
///   server = bluey.server();
///   await server!.addService(...);
/// }
/// ```
///
/// [triggeringState] is the adapter state that caused invalidation.
/// It does **not** reflect the adapter's current state, which may have
/// returned to [BluetoothState.on] since invalidation.
class StaleHandleException extends BlueyException {
  /// The adapter state that caused this instance to be invalidated.
  final BluetoothState triggeringState;

  /// The instance type that was invalidated.
  final InvalidatedInstance instanceType;

  // Note: `const` cannot be added here because Dart's const evaluator
  // forbids string interpolation of instance-property getters (`.displayName`,
  // `.name`) on constructor parameters, even when those parameters are
  // compile-time constants. The constructor is intentionally non-const to
  // preserve readable, human-friendly messages.
  StaleHandleException({
    required this.triggeringState,
    required this.instanceType,
  }) : super(
         '${instanceType.displayName} was invalidated by adapter '
         'transition to ${triggeringState.name}; the instance is dead '
         'even if the adapter has since returned to BluetoothState.on.',
         action:
             'Construct a fresh ${instanceType.displayName} from Bluey '
             'rather than reusing this one.',
       );
}
