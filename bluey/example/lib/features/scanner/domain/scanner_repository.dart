import 'package:bluey/bluey.dart';

/// Abstract repository interface for BLE scanning operations.
abstract class ScannerRepository {
  /// Returns the current Bluetooth state.
  BluetoothState get currentState;

  /// Stream of Bluetooth state changes.
  Stream<BluetoothState> get stateStream;

  /// The shared [Scanner] instance. Created lazily and cached; the same
  /// object is returned on every call. Callers must not call
  /// [Scanner.dispose] directly — use [dispose] on the repository.
  Scanner get scanner;

  /// Starts scanning for BLE devices.
  /// Returns a stream of discovered scan results.
  Stream<ScanResult> scan({Duration? timeout});

  /// Requests Bluetooth permissions from the user.
  /// Returns true if permission was granted.
  Future<bool> authorize();

  /// Requests the user to enable Bluetooth.
  /// Returns true if Bluetooth was enabled.
  Future<bool> requestEnable();

  /// Opens the system Bluetooth settings.
  Future<void> openSettings();

  /// Releases the cached [Scanner] and any other resources held by this
  /// repository. Must be called when the repository is no longer needed.
  void dispose();
}
