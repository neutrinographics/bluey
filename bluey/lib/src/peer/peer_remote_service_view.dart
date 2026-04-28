import '../connection/connection.dart' show Connection;
import '../gatt_client/gatt.dart' show RemoteService;
import '../lifecycle.dart' as lifecycle;
import '../shared/exceptions.dart' show ServiceNotFoundException;
import '../shared/uuid.dart';

/// A view of a [Connection]'s service tree with the lifecycle control
/// service hidden.
///
/// Peer-protocol consumers see only the user-facing services exposed by
/// the peer; the lifecycle control service used internally for heartbeat
/// and disconnect-command signaling is filtered out at this view layer.
///
/// Used by `PeerConnection` (via `_BlueyPeerConnection` post-C.3) to
/// expose its services / service / hasService surface. Raw access via
/// the underlying [Connection] is unchanged — the full tree is still
/// reachable through `PeerConnection.connection`.
class PeerRemoteServiceView {
  /// Wraps [connection] and presents a service tree with the lifecycle
  /// control service excluded.
  const PeerRemoteServiceView(this._connection);

  final Connection _connection;

  /// Service tree with the lifecycle control service excluded.
  ///
  /// Forwards [cache] to the underlying [Connection.services].
  Future<List<RemoteService>> services({bool cache = false}) async {
    final all = await _connection.services(cache: cache);
    return all
        .where((s) => !lifecycle.isControlService(s.uuid.toString()))
        .toList();
  }

  /// Lookup a service by UUID.
  ///
  /// Throws [ServiceNotFoundException] when [uuid] is the lifecycle
  /// control service (which is hidden by this view) — the same
  /// exception shape the underlying [Connection] throws for genuinely
  /// missing services.
  RemoteService service(UUID uuid) {
    if (lifecycle.isControlService(uuid.toString())) {
      throw ServiceNotFoundException(uuid);
    }
    return _connection.service(uuid);
  }

  /// Whether the user-facing tree contains the given service [uuid].
  ///
  /// Returns false for the lifecycle control service even if the peer
  /// hosts it.
  Future<bool> hasService(UUID uuid) async {
    if (lifecycle.isControlService(uuid.toString())) return false;
    return _connection.hasService(uuid);
  }
}
