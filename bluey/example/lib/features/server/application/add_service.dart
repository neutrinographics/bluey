import 'package:bluey/bluey.dart';

import '../domain/server_repository.dart';

/// Use case for adding a hosted service to the BLE server.
class AddService {
  final ServerRepository _repository;

  AddService(this._repository);

  /// Adds a [HostedService] to the server.
  Future<void> call(HostedService service) async {
    await _repository.addService(service);
  }
}
