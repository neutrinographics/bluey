import 'package:bluey/bluey.dart';

import '../domain/server_repository.dart';

/// Use case for observing client device disconnections from the server.
class ObserveDisconnections {
  final ServerRepository _repository;

  ObserveDisconnections(this._repository);

  /// Returns a stream of [ClientAddress] values for clients that disconnect
  /// from the server.
  Stream<ClientAddress> call() {
    return _repository.disconnections;
  }
}
