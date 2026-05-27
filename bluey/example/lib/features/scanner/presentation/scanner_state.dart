import 'package:bluey/bluey.dart';

enum SortMode { signalStrength, name, deviceId }

class ScannerState {
  final BluetoothState bluetoothState;
  final List<ScanResult> scanResults;
  final ScanState scanState;
  final List<BlueyEvent> scanLog;
  final SortMode sortMode;
  final String? error;

  const ScannerState({
    this.bluetoothState = BluetoothState.unknown,
    this.scanResults = const [],
    this.scanState = ScanState.stopped,
    this.scanLog = const [],
    this.sortMode = SortMode.name,
    this.error,
  });

  bool get isScanning => scanState == ScanState.scanning;
  bool get isInvalidated => scanState == ScanState.invalidated;

  ScannerState copyWith({
    BluetoothState? bluetoothState,
    List<ScanResult>? scanResults,
    ScanState? scanState,
    List<BlueyEvent>? scanLog,
    SortMode? sortMode,
    String? error,
  }) {
    return ScannerState(
      bluetoothState: bluetoothState ?? this.bluetoothState,
      scanResults: scanResults ?? this.scanResults,
      scanState: scanState ?? this.scanState,
      scanLog: scanLog ?? this.scanLog,
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
        other.scanState == scanState &&
        _listEquals(other.scanLog, scanLog) &&
        other.sortMode == sortMode &&
        other.error == error;
  }

  @override
  int get hashCode {
    return Object.hash(
      bluetoothState,
      Object.hashAll(scanResults),
      scanState,
      Object.hashAll(scanLog),
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
