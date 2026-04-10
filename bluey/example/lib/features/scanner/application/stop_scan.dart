import '../domain/scanner_repository.dart';

/// Use case for stopping a BLE scan.
class StopScan {
  final ScannerRepository _repository;

  StopScan(this._repository);

  /// Stops the current BLE scan.
  Future<void> call() async {
    await _repository.stopScan();
  }
}
