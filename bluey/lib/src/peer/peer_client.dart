import '../gatt_server/server.dart' show Client;

/// A connected client that has identified itself as a Bluey peer (i.e.
/// has sent at least one lifecycle heartbeat write).
///
/// `PeerClient` is the server-side analog of `PeerConnection`: a
/// composition wrapper around a raw [Client] that adds a single piece
/// of metadata — "this central speaks the lifecycle protocol." The
/// underlying [Client] is exposed via [client] for any GATT-level
/// operation (notify, disconnect, etc.) — those work the same for
/// peer and non-peer clients.
///
/// Obtain instances via `Server.peerConnections`. The stream emits a
/// `PeerClient` the first time a connected central sends a heartbeat;
/// it does not re-emit on subsequent heartbeats from the same client.
/// On disconnect the identification is reset; a reconnect-then-heartbeat
/// produces a fresh emission.
abstract class PeerClient {
  /// Construct a [PeerClient] wrapping the given [client].
  ///
  /// Internal use; consumers obtain instances via `Server.peerConnections`.
  factory PeerClient.create({required Client client}) = _BlueyPeerClient;

  /// The underlying raw GATT [Client].
  ///
  /// Use this for any operation that doesn't require knowledge of the
  /// peer protocol (`disconnect()`, `mtu`, `id`).
  Client get client;
}

/// Default [PeerClient] implementation. Private to this file —
/// consumers construct via [PeerClient.create].
class _BlueyPeerClient implements PeerClient {
  _BlueyPeerClient({required this.client});

  @override
  final Client client;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _BlueyPeerClient && identical(other.client, client);

  @override
  int get hashCode => identityHashCode(client);
}
