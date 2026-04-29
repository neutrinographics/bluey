import 'package:bluey/bluey.dart';

import '../domain/connection_repository.dart';

/// Use case for watching peer-status across a connection's lifetime.
/// Emits the result of `tryUpgrade` on subscription, then re-attempts on
/// every `servicesChanges` emission until upgrade succeeds. Stream
/// completes after the first non-null peer or when the connection
/// disconnects. See [Bluey.watchPeer].
class WatchPeer {
  final ConnectionRepository _repository;

  WatchPeer(this._repository);

  Stream<PeerConnection?> call(Connection connection) {
    return _repository.watchPeer(connection);
  }
}
