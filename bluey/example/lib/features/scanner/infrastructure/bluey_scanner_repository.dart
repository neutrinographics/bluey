import 'package:bluey/bluey.dart';

import '../domain/scanner_repository.dart';

/// Implementation of [ScannerRepository] using the Bluey library.
///
/// Note: `scan()` returns the platform-backed stream directly. Consumers
/// stop the radio by cancelling their subscription — the `Scanner.scan()`
/// stream is wired with `onCancel: () => stop()` in bluey since PR #32
/// (Convention 5 of the stream-conventions design). No explicit stop()
/// method is needed.
class BlueyScannerRepository implements ScannerRepository {
  final Bluey _bluey;

  BlueyScannerRepository(this._bluey);

  @override
  BluetoothState get currentState => _bluey.currentState;

  @override
  Stream<BluetoothState> get stateStream => _bluey.stateStream;

  @override
  Stream<ScanResult> scan({Duration? timeout}) {
    return _bluey.scanner().scan(timeout: timeout);
  }

  @override
  Future<bool> authorize() => _bluey.authorize();

  @override
  Future<bool> requestEnable() => _bluey.requestEnable();

  @override
  Future<void> openSettings() => _bluey.openSettings();
}
