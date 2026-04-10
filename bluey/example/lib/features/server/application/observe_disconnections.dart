import '../domain/server_repository.dart';

/// Use case for observing client device disconnections from the server.
class ObserveDisconnections {
  final ServerRepository _repository;

  ObserveDisconnections(this._repository);

  /// Returns a stream of client device IDs that disconnect from the server.
  Stream<String> call() {
    return _repository.disconnections;
  }
}
