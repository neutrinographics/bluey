import 'package:bluey/bluey.dart';

import '../domain/scanner_repository.dart';

/// Implementation of [ScannerRepository] using the Bluey library.
class BlueyScannerRepository implements ScannerRepository {
  final Bluey _bluey;
  Scanner? _scanner;

  BlueyScannerRepository(this._bluey);

  @override
  BluetoothState get currentState => _bluey.currentState;

  @override
  Stream<BluetoothState> get stateStream => _bluey.stateStream;

  @override
  Stream<ScanResult> scan({Duration? timeout}) {
    _scanner?.dispose();
    _scanner = _bluey.scanner();
    return _scanner!.scan(timeout: timeout);
  }

  @override
  Future<void> stopScan() async {
    await _scanner?.stop();
    _scanner?.dispose();
    _scanner = null;
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
