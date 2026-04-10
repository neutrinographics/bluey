import 'package:bluey/bluey.dart';

import '../domain/server_repository.dart';

/// Use case for observing client device connections to the server.
class ObserveConnections {
  final ServerRepository _repository;

  ObserveConnections(this._repository);

  /// Returns a stream of client devices that connect to the server.
  Stream<Client> call() {
    return _repository.connections;
  }
}
