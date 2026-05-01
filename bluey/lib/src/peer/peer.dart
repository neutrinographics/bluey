import 'peer_connection.dart';
import 'server_id.dart';

/// A stable handle to a Bluey server identified by its [ServerId].
///
/// A `BlueyPeer` represents a logical peer — "the specific Bluey
/// server you want to talk to" — independent of the platform's
/// transient device identifiers (iOS `CBPeripheral.identifier`,
/// Android MAC). Construct one via `bluey.peer(...)` (if you already
/// have a [ServerId]) or obtain one from `bluey.discoverPeers()`.
///
/// Calling [connect] performs a targeted scan for the peer,
/// establishes a GATT connection, verifies the server's [serverId]
/// matches the expected value, starts the lifecycle heartbeat, and
/// returns a live [PeerConnection] — the peer-protocol surface
/// (filtered service tree, lifecycle disconnect). Use
/// `peerConnection.connection` to drop down to the raw GATT handle
/// when needed.
abstract class BlueyPeer {
  /// The stable Bluey identifier of the remote server.
  ServerId get serverId;

  /// Connect to this peer.
  ///
  /// Performs a targeted scan (filtered by the Bluey control service
  /// UUID), connects to each matching candidate in turn, and returns
  /// the connection to the first one whose `serverId` matches.
  ///
  /// [scanTimeout] bounds the discovery phase. [probeTimeout] bounds
  /// each individual probe-connect attempt — see I056. When omitted,
  /// `PeerDiscovery.defaultProbeTimeout` (3 s) is used.
  ///
  /// Returns a [PeerConnection] — a peer-protocol wrapper around the
  /// raw GATT [Connection] that hides the lifecycle control service
  /// from the service tree and forwards disconnect through the
  /// lifecycle protocol. Access the underlying raw connection via
  /// `peerConnection.connection`.
  ///
  /// Throws [PeerNotFoundException] if no matching server is found
  /// within [scanTimeout]. Throws [ConnectionException] for BLE-level
  /// connection failures.
  Future<PeerConnection> connect({
    Duration? scanTimeout,
    Duration? probeTimeout,
  });
}
