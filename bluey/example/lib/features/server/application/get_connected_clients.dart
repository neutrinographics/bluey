import 'package:bluey/bluey.dart';

import '../domain/server_repository.dart';

/// Use case for getting the currently connected clients.
class GetConnectedClients {
  final ServerRepository _repository;

  GetConnectedClients(this._repository);

  /// Returns the list of currently connected clients.
  List<Client> call() {
    return _repository.connectedClients;
  }
}
