import 'package:bluey/bluey.dart';

/// Abstract repository interface for BLE scanning operations.
abstract class ScannerRepository {
  /// Returns the current Bluetooth state.
  BluetoothState get currentState;

  /// Stream of Bluetooth state changes.
  Stream<BluetoothState> get stateStream;

  /// Starts scanning for BLE devices.
  /// Returns a stream of discovered scan results.
  Stream<ScanResult> scan({Duration? timeout});

  /// Stops the current scan.
  Future<void> stopScan();

  /// Requests Bluetooth permissions from the user.
  /// Returns true if permission was granted.
  Future<bool> authorize();

  /// Requests the user to enable Bluetooth.
  /// Returns true if Bluetooth was enabled.
  Future<bool> requestEnable();

  /// Opens the system Bluetooth settings.
  Future<void> openSettings();
}
