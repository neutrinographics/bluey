import 'package:bluey/bluey.dart';

import '../domain/scanner_repository.dart';

/// Implementation of [ScannerRepository] using the Bluey library.
///
/// A single [Scanner] is created lazily on first access to [scanner] and
/// reused for the lifetime of this repository. All scan operations — both
/// the [scan] stream and the [Scanner.stateChanges] subscription — share
/// the same instance, so state changes are always coherent with the
/// active scan.
///
/// Note: `scan()` returns the platform-backed stream directly. Consumers
/// stop the radio by cancelling their subscription — the `Scanner.scan()`
/// stream is wired with `onCancel: () => stop()` in bluey since PR #32
/// (Convention 5 of the stream-conventions design). No explicit stop()
/// method is needed.
class BlueyScannerRepository implements ScannerRepository {
  final Bluey _bluey;

  Scanner? _scanner;

  BlueyScannerRepository(this._bluey);

  @override
  BluetoothState get currentState => _bluey.currentState;

  @override
  Stream<BluetoothState> get stateStream => _bluey.stateStream;

  @override
  Scanner get scanner => _scanner ??= _bluey.scanner();

  @override
  Stream<ScanResult> scan({Duration? timeout}) {
    return scanner.scan(timeout: timeout);
  }

  @override
  Future<bool> authorize() => _bluey.authorize();

  @override
  Future<bool> requestEnable() => _bluey.requestEnable();

  @override
  Future<void> openSettings() => _bluey.openSettings();

  @override
  void dispose() {
    _scanner?.dispose();
    _scanner = null;
  }
}
