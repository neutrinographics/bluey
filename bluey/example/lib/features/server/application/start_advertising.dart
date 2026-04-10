import 'package:bluey/bluey.dart';

import '../domain/server_repository.dart';

/// Use case for starting BLE advertising.
class StartAdvertising {
  final ServerRepository _repository;

  StartAdvertising(this._repository);

  /// Starts advertising with the given parameters.
  ///
  /// [name] is the advertised device name.
  /// [services] is a list of service UUIDs to advertise.
  Future<void> call({String? name, List<UUID>? services}) async {
    await _repository.startAdvertising(name: name, services: services);
  }
}
