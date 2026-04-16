import '../infrastructure/peer_storage.dart';

/// Use case for clearing the saved peer identity.
class ForgetSavedPeer {
  final PeerStorage _storage;

  ForgetSavedPeer(this._storage);

  /// Removes the saved peer from storage.
  Future<void> call() => _storage.clear();
}
