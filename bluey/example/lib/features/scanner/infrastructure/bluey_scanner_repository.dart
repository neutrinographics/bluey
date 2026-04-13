import 'package:bluey/bluey.dart';

import '../domain/scanner_repository.dart';

/// Implementation of [ScannerRepository] using the Bluey library.
class BlueyScannerRepository implements ScannerRepository {
  final Bluey _bluey;

  BlueyScannerRepository(this._bluey);

  @override
  BluetoothState get currentState => _bluey.currentState;

  @override
  Stream<BluetoothState> get stateStream => _bluey.stateStream;

  @override
  Stream<ScanResult> scan({Duration? timeout}) {
    return _bluey.scan(timeout: timeout);
  }

  @override
  Future<void> stopScan() async {
    await _bluey.stopScan();
  }

  @override
  Future<bool> authorize() async {
    return await _bluey.authorize();
  }

  @override
  Future<bool> requestEnable() async {
    return await _bluey.requestEnable();
  }

  @override
  Future<void> openSettings() async {
    await _bluey.openSettings();
  }
}
