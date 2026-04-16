import 'package:bluey/bluey.dart';

import '../infrastructure/peer_storage.dart';

/// Use case for reconnecting to a previously saved peer.
///
/// Loads the saved [ServerId] from storage, constructs a [BlueyPeer]
/// handle, and attempts to connect. Returns `null` if no peer was saved.
class ConnectSavedPeer {
  final Bluey _bluey;
  final PeerStorage _storage;

  ConnectSavedPeer(this._bluey, this._storage);

  /// Attempts to reconnect to the saved peer.
  ///
  /// Returns the live [Connection] on success, or `null` if no peer
  /// was saved. Throws [PeerNotFoundException] if the saved peer is
  /// not reachable.
  Future<Connection?> call() async {
    final id = await _storage.load();
    if (id == null) return null;
    return _bluey.peer(id).connect();
  }
}
