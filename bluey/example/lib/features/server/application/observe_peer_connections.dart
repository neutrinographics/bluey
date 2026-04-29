import 'package:bluey/bluey.dart';

import '../domain/server_repository.dart';

/// Use case for observing clients that have identified themselves as
/// Bluey peers (i.e. sent at least one lifecycle heartbeat).
class ObservePeerConnections {
  final ServerRepository _repository;

  ObservePeerConnections(this._repository);

  /// Returns a stream of [PeerClient] emissions, one per identification.
  /// A reconnect-then-heartbeat re-identifies and produces a fresh
  /// emission.
  Stream<PeerClient> call() {
    return _repository.peerConnections;
  }
}
