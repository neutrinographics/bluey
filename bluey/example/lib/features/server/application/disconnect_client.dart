import 'package:bluey/bluey.dart';

import '../domain/server_repository.dart';

/// Use case for disconnecting a connected client device.
class DisconnectClient {
  final ServerRepository _repository;

  DisconnectClient(this._repository);

  /// Disconnects the specified [central] from the server.
  Future<void> call(Client central) async {
    await _repository.disconnectClient(central);
  }
}
