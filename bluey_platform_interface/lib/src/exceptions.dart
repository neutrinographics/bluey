/// A GATT operation (read, write, descriptor read/write, discoverServices,
/// MTU/PHY/connection-parameter request, etc.) did not complete within its
/// configured timeout.
///
/// This is distinct from synchronous platform errors (e.g. "no operation in
/// progress" rejections) which signal a transient ordering issue rather than
/// an unreachable peer. Callers that monitor liveness — most notably
/// `LifecycleClient` — should only treat instances of this exception as
/// evidence that the remote device is gone.
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
