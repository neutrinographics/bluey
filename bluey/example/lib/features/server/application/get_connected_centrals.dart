import 'package:bluey/bluey.dart';

import '../domain/server_repository.dart';

/// Use case for getting the currently connected centrals.
class GetConnectedCentrals {
  final ServerRepository _repository;

  GetConnectedCentrals(this._repository);

  /// Returns the list of currently connected centrals.
  List<Central> call() {
    return _repository.connectedCentrals;
  }
}
