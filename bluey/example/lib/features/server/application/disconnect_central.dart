import 'package:bluey/bluey.dart';

import '../domain/server_repository.dart';

/// Use case for disconnecting a connected central device.
class DisconnectCentral {
  final ServerRepository _repository;

  DisconnectCentral(this._repository);

  /// Disconnects the specified [central] from the server.
  Future<void> call(Central central) async {
    await _repository.disconnectCentral(central);
  }
}
