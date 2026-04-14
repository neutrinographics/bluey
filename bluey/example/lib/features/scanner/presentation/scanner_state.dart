import 'package:bluey/bluey.dart';

/// How the scan results list is sorted.
enum SortMode { signalStrength, name, deviceId }

/// State for the scanner feature.
class ScannerState {
  final BluetoothState bluetoothState;
  final List<ScanResult> scanResults;
  final bool isScanning;
  final SortMode sortMode;
  final String? error;

  const ScannerState({
    this.bluetoothState = BluetoothState.unknown,
    this.scanResults = const [],
    this.isScanning = false,
    this.sortMode = SortMode.signalStrength,
    this.error,
  });

  ScannerState copyWith({
    BluetoothState? bluetoothState,
    List<ScanResult>? scanResults,
    bool? isScanning,
    SortMode? sortMode,
    String? error,
  }) {
    return ScannerState(
      bluetoothState: bluetoothState ?? this.bluetoothState,
      scanResults: scanResults ?? this.scanResults,
      isScanning: isScanning ?? this.isScanning,
      sortMode: sortMode ?? this.sortMode,
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
        other.sortMode == sortMode &&
        other.error == error;
  }

  @override
  int get hashCode {
    return Object.hash(
      bluetoothState,
      Object.hashAll(scanResults),
      isScanning,
      sortMode,
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
