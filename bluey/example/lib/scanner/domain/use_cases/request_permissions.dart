import '../scanner_repository.dart';

/// Use case for requesting Bluetooth permissions.
class RequestPermissions {
  final ScannerRepository _repository;

  RequestPermissions(this._repository);

  /// Requests Bluetooth permissions from the user.
  ///
  /// Returns true if permission was granted, false otherwise.
  Future<bool> call() async {
    return await _repository.authorize();
  }
}
