import 'package:bluey/bluey.dart';

import '../server_repository.dart';

/// Use case for observing central device connections to the server.
class ObserveConnections {
  final ServerRepository _repository;

  ObserveConnections(this._repository);

  /// Returns a stream of central devices that connect to the server.
  Stream<Central> call() {
    return _repository.connections;
  }
}
