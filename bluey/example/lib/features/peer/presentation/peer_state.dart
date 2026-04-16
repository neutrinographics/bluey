import 'package:bluey/bluey.dart';

/// The status of the peer screen's lifecycle.
enum PeerScreenStatus {
  /// No activity yet.
  initial,

  /// Trying to reconnect to a saved peer.
  restoring,

  /// Scanning for nearby Bluey servers.
  discovering,

  /// Peer list available.
  discovered,

  /// Connecting to a selected peer.
  connecting,

  /// Connection established.
  connected,

  /// Something went wrong.
  error,
}

/// Immutable state for the peer screen.
class PeerState {
  final PeerScreenStatus status;
  final List<BlueyPeer> peers;
  final ServerId? savedPeerId;
  final Connection? connection;
  final String? error;

  const PeerState({
    this.status = PeerScreenStatus.initial,
    this.peers = const [],
    this.savedPeerId,
    this.connection,
    this.error,
  });

  PeerState copyWith({
    PeerScreenStatus? status,
    List<BlueyPeer>? peers,
    ServerId? savedPeerId,
    Connection? connection,
    String? error,
  }) {
    return PeerState(
      status: status ?? this.status,
      peers: peers ?? this.peers,
      savedPeerId: savedPeerId ?? this.savedPeerId,
      connection: connection ?? this.connection,
      error: error,
    );
  }

  /// Returns a copy with the connection cleared.
  PeerState withoutConnection() {
    return PeerState(
      status: status,
      peers: peers,
      savedPeerId: savedPeerId,
      connection: null,
      error: error,
    );
  }
}
