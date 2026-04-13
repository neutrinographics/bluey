import 'package:bluey/bluey.dart';

/// State for the scanner feature.
class ScannerState {
  final BluetoothState bluetoothState;
  final List<ScanResult> scanResults;
  final bool isScanning;
  final String? error;

  const ScannerState({
    this.bluetoothState = BluetoothState.unknown,
    this.scanResults = const [],
    this.isScanning = false,
    this.error,
  });

  ScannerState copyWith({
    BluetoothState? bluetoothState,
    List<ScanResult>? scanResults,
    bool? isScanning,
    String? error,
  }) {
    return ScannerState(
      bluetoothState: bluetoothState ?? this.bluetoothState,
      scanResults: scanResults ?? this.scanResults,
      isScanning: isScanning ?? this.isScanning,
      error: error,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ScannerState &&
        other.bluetoothState == bluetoothState &&
        _listEquals(other.scanResults, scanResults) &&
        other.isScanning == isScanning &&
        other.error == error;
  }

  @override
  int get hashCode {
    return Object.hash(
      bluetoothState,
      Object.hashAll(scanResults),
      isScanning,
      error,
    );
  }

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
