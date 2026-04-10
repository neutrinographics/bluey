import '../server_repository.dart';

/// Use case for stopping BLE advertising.
class StopAdvertising {
  final ServerRepository _repository;

  StopAdvertising(this._repository);

  /// Stops advertising.
  Future<void> call() async {
    await _repository.stopAdvertising();
  }
}
