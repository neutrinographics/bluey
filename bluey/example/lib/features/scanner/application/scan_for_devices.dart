import 'package:bluey/bluey.dart';

import '../domain/scanner_repository.dart';

/// Use case for scanning for BLE devices.
class ScanForDevices {
  final ScannerRepository _repository;

  ScanForDevices(this._repository);

  /// Starts scanning for BLE devices.
  ///
  /// Returns a stream of discovered [Device] objects.
  /// The scan will automatically stop after [timeout] if provided.
  Stream<Device> call({Duration? timeout}) {
    return _repository.scan(timeout: timeout);
  }
}
