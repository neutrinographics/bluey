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
      other is GattOperationDisconnectedException && other.operation == operation;

  @override
  int get hashCode => operation.hashCode;
}
