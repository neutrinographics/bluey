import 'package:bluey/bluey.dart';

import '../domain/connection_repository.dart';

/// Use case for getting the services on a connected device.
class GetServices {
  final ConnectionRepository _repository;

  GetServices(this._repository);

  /// Returns the list of services available on the connected device.
  Future<List<RemoteService>> call(Connection connection) async {
    return await _repository.getServices(connection);
  }
}
