import 'package:bluey/bluey.dart';

import '../scanner_repository.dart';

/// Use case for getting the current Bluetooth state and listening to changes.
class GetBluetoothState {
  final ScannerRepository _repository;

  GetBluetoothState(this._repository);

  /// Returns the current Bluetooth state synchronously.
  BluetoothState get current => _repository.currentState;

  /// Returns a stream of Bluetooth state changes.
  Stream<BluetoothState> call() {
    return _repository.stateStream;
  }
}
