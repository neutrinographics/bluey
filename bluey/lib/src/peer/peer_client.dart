import '../gatt_server/server.dart' show Client;
import 'server_id.dart';

/// A connected client that has identified itself as a Bluey peer.
///
/// `PeerClient` is the server-side analog of `PeerConnection`: a
/// composition wrapper around a raw [Client] enriched with the central's
/// stable [ServerId] (sent in the lifecycle heartbeat write).
///
/// The underlying [Client] is exposed via [client] for any GATT-level
/// operation (notify, disconnect, etc.) — those work the same for peer
/// and non-peer clients.
///
/// Obtain instances via `Server.peerConnections`. The stream emits a
/// `PeerClient` exactly once per identification — on the first valid
/// heartbeat that decodes successfully — and does not re-emit on
/// subsequent heartbeats from the same client. On disconnect the
/// identification is reset; a reconnect-then-heartbeat produces a
/// fresh emission.
abstract class PeerClient {
  /// Construct a [PeerClient] wrapping the given [client] with its
  /// stable [serverId].
  ///
  /// Internal use; consumers obtain instances via `Server.peerConnections`.
  factory PeerClient.create({
    required Client client,
    required ServerId serverId,
  }) = _BlueyPeerClient;

  /// The underlying raw GATT [Client].
  ///
  /// Use this for any operation that doesn't require knowledge of the
  /// peer protocol (`disconnect()`, `mtu`, `id`).
  Client get client;

  /// The remote central's stable [ServerId], decoded from the lifecycle
  /// heartbeat. Survives platform-level identifier rotation (iOS session
  /// rotation, Android MAC randomization).
  ServerId get serverId;
}

/// Default [PeerClient] implementation. Private to this file —
/// consumers construct via [PeerClient.create].
class _BlueyPeerClient implements PeerClient {
  _BlueyPeerClient({required this.client, required this.serverId});

  @override
  final Client client;

  @override
  final ServerId serverId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _BlueyPeerClient &&
          identical(other.client, client) &&
          other.serverId == serverId;

  @override
  int get hashCode => Object.hash(identityHashCode(client), serverId);
}
