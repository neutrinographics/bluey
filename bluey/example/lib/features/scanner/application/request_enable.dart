import '../domain/scanner_repository.dart';

/// Use case for requesting the user to enable Bluetooth.
class RequestEnable {
  final ScannerRepository _repository;

  RequestEnable(this._repository);

  /// Requests the user to enable Bluetooth.
  ///
  /// Returns true if Bluetooth was enabled, false otherwise.
  Future<bool> call() async {
    return await _repository.requestEnable();
  }

  /// Opens the system Bluetooth settings.
  Future<void> openSettings() async {
    await _repository.openSettings();
  }
}
