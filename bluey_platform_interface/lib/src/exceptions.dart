/// A GATT operation (read, write, descriptor read/write, discoverServices,
/// MTU/PHY/connection-parameter request, etc.) did not complete within its
/// configured timeout.
///
/// This is distinct from synchronous platform errors (e.g. "no operation in
/// progress" rejections) which signal a transient ordering issue rather than
/// an unreachable peer. Callers that monitor liveness — most notably
/// `LifecycleClient` — should only treat instances of this exception as
/// evidence that the remote device is gone.
///
/// Internal platform-interface signal. Not part of the `BlueyException`
/// sealed hierarchy in the `bluey` package; `BlueyConnection` translates
/// this into a user-facing exception at the public API boundary.
class GattOperationTimeoutException implements Exception {
  /// Name of the platform interface method that timed out, e.g.
  /// `'writeCharacteristic'`. Used for diagnostics; not parsed by callers.
  final String operation;

  const GattOperationTimeoutException(this.operation);

  @override
  String toString() => 'GattOperationTimeoutException: $operation timed out';

  @override
  bool operator ==(Object other) =>
      other is GattOperationTimeoutException && other.operation == operation;

  @override
  int get hashCode => operation.hashCode;
}

/// A GATT operation (read, write, etc.) could not complete because the
/// underlying connection was torn down before the operation's response
/// was received.
///
/// Distinct from [GattOperationTimeoutException]: the peer didn't just stop
/// responding — the link itself is gone. Consumers that monitor liveness
/// (e.g. `LifecycleClient`) can use the presence of this exception to
/// distinguish "timeout" from "connection loss" when deciding how to react.
///
/// Internal platform-interface signal. Not part of the `BlueyException`
/// sealed hierarchy in the `bluey` package; `BlueyConnection` translates
/// this into a user-facing exception at the public API boundary.
class GattOperationDisconnectedException implements Exception {
  /// Name of the platform interface method whose operation was aborted,
  /// e.g. `'writeCharacteristic'`. Used for diagnostics; not parsed by
  /// callers.
  final String operation;

  const GattOperationDisconnectedException(this.operation);

  @override
  String toString() =>
      'GattOperationDisconnectedException: $operation aborted due to disconnect';

  @override
  bool operator ==(Object other) =>
      other is GattOperationDisconnectedException &&
      other.operation == operation;

  @override
  int get hashCode => operation.hashCode;
}

/// A GATT operation completed but the peer returned a non-success status
/// code — the request reached the peer and a response came back, but the
/// response was a protocol-level error (invalid handle, insufficient
/// authentication, write-not-permitted, etc.).
///
/// Distinct from [GattOperationTimeoutException] (no response arrived) and
/// from [GattOperationDisconnectedException] (the link dropped before a
/// response could arrive). Carries the native [status] code so callers can
/// distinguish recoverable errors (e.g. bonding required) from terminal
/// ones (e.g. invalid handle after a Service Changed event where the peer
/// has removed the characteristic).
///
/// Internal platform-interface signal. Not part of the `BlueyException`
/// sealed hierarchy in the `bluey` package; `BlueyConnection` translates
/// this into a user-facing exception at the public API boundary.
class GattOperationStatusFailedException implements Exception {
  /// Name of the platform interface method whose operation failed, e.g.
  /// `'writeCharacteristic'`. Used for diagnostics; not parsed by callers.
  final String operation;

  /// Native GATT status code returned by the peer. On Android this is the
  /// `BluetoothGatt.GATT_*` constant (e.g. `GATT_INVALID_HANDLE = 0x01`);
  /// on iOS the translation to a comparable code is platform-specific.
  final int status;

  const GattOperationStatusFailedException(this.operation, this.status);

  @override
  String toString() =>
      'GattOperationStatusFailedException: $operation failed with status $status';

  @override
  bool operator ==(Object other) =>
      other is GattOperationStatusFailedException &&
      other.operation == operation &&
      other.status == status;

  @override
  int get hashCode => Object.hash(operation, status);
}

/// A platform operation failed with a code we couldn't translate into a
/// specific typed GATT exception (e.g. `BlueyError.unknown` on iOS, or
/// any `NSError` whose domain/code we haven't mapped). Carries the
/// wire-level [code] and [message] for diagnostics.
///
/// Internal platform-interface signal. Not part of the `BlueyException`
/// sealed hierarchy in the `bluey` package; `BlueyConnection` translates
/// this into [BlueyPlatformException] at the public API boundary.
class GattOperationUnknownPlatformException implements Exception {
  /// Name of the platform interface method that failed, e.g.
  /// `'writeCharacteristic'`. Used for diagnostics; not parsed by callers.
  final String operation;

  /// The wire-level error code emitted by the platform adapter (e.g.
  /// `'bluey-unknown'`). Preserved as-is so the public-API boundary can
  /// surface it without further lossy translation.
  final String code;

  /// Human-readable message from the platform layer, if available.
  final String? message;

  const GattOperationUnknownPlatformException(
    this.operation, {
    required this.code,
    this.message,
  });

  @override
  String toString() =>
      'GattOperationUnknownPlatformException: $operation failed with code "$code"'
      '${message != null ? ' - $message' : ''}';

  @override
  bool operator ==(Object other) =>
      other is GattOperationUnknownPlatformException &&
      other.operation == operation &&
      other.code == code &&
      other.message == message;

  @override
  int get hashCode => Object.hash(operation, code, message);
}

/// A platform operation failed because a required runtime permission was
/// denied. Currently Android-specific — iOS has no runtime-permission
/// equivalent that can fire mid-op (the CBManagerState.unauthorized case
/// is handled via `Bluey.state`).
///
/// Internal platform-interface signal. Not part of the `BlueyException`
/// sealed hierarchy in the `bluey` package; `BlueyConnection` translates
/// this into [PermissionDeniedException] at the public API boundary.
class PlatformPermissionDeniedException implements Exception {
  /// Name of the platform interface method that triggered the check,
  /// e.g. `'writeCharacteristic'`. Used for diagnostics.
  final String operation;

  /// The single missing permission name, e.g. `'BLUETOOTH_CONNECT'`,
  /// as reported by the native layer.
  final String permission;

  /// Optional human-readable message from the native layer.
  final String? message;

  const PlatformPermissionDeniedException(
    this.operation, {
    required this.permission,
    this.message,
  });

  @override
  String toString() =>
      'PlatformPermissionDeniedException: $operation denied '
      '(permission: $permission)${message != null ? ' - $message' : ''}';

  @override
  bool operator ==(Object other) =>
      other is PlatformPermissionDeniedException &&
      other.operation == operation &&
      other.permission == permission &&
      other.message == message;

  @override
  int get hashCode => Object.hash(operation, permission, message);
}

/// Raised when the platform's advertising stack rejects an advertisement
/// because it exceeds the legacy 31-byte primary-AD budget (Android's
/// `ADVERTISE_FAILED_DATA_TOO_LARGE`, error code 1).
///
/// The domain layer translates this to `AdvertisingException(
/// AdvertisingFailureReason.dataTooBig)`. Surface this typed form
/// instead of generic `bluey-unknown` so apps can react (e.g., shorten
/// the device name, drop a UUID, or move it to scan response).
class PlatformAdvertiseDataTooLargeException implements Exception {
  /// Human-readable description of why the advertisement was rejected.
  final String message;

  const PlatformAdvertiseDataTooLargeException(this.message);

  @override
  String toString() =>
      'PlatformAdvertiseDataTooLargeException: $message';

  @override
  bool operator ==(Object other) =>
      other is PlatformAdvertiseDataTooLargeException &&
          other.message == message;

  @override
  int get hashCode => message.hashCode;
}

/// Raised when a server-side `respondToReadRequest` or
/// `respondToWriteRequest` call references a `requestId` the platform
/// plugin no longer has on file.
///
/// On iOS this is the surface of `BlueyError.notFound` from
/// `PeripheralManagerImpl.respondToReadRequest` (or `respondToWriteRequest`)
/// when the corresponding entry has already been removed from
/// `pendingReadRequests` / `pendingWriteRequests`. Common cause: a
/// duplicate response on the Dart side (a request was emitted on
/// the platform's broadcast `readRequests` stream, two subscribers
/// both responded; the second one hits "not found"). Less commonly,
/// a `closeServer` raced an in-flight respond.
///
/// The domain layer translates this to `RespondNotFoundException`. Surface
/// this typed form instead of generic `bluey-unknown` so the lifecycle
/// server can distinguish the *expected race* (warn-and-move-on) from
/// *unexpected respond failures* (error-level, surface for triage).
class PlatformRespondToRequestNotFoundException implements Exception {
  /// Human-readable description of the missing request id, if the
  /// underlying platform plugin provided one.
  final String message;

  const PlatformRespondToRequestNotFoundException(this.message);

  @override
  String toString() =>
      'PlatformRespondToRequestNotFoundException: $message';

  @override
  bool operator ==(Object other) =>
      other is PlatformRespondToRequestNotFoundException &&
          other.message == message;

  @override
  int get hashCode => message.hashCode;
}
