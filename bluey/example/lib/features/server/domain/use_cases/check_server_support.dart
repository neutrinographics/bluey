import '../server_repository.dart';

/// Use case for checking if the BLE peripheral role is supported.
class CheckServerSupport {
  final ServerRepository _repository;

  CheckServerSupport(this._repository);

  /// Returns true if the platform supports the BLE peripheral role.
  bool call() {
    return _repository.getServer() != null;
  }
}
