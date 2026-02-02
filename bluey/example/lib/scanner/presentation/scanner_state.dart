import 'package:bluey/bluey.dart';

/// State for the scanner feature.
class ScannerState {
  final BluetoothState bluetoothState;
  final List<Device> devices;
  final bool isScanning;
  final String? error;

  const ScannerState({
    this.bluetoothState = BluetoothState.unknown,
    this.devices = const [],
    this.isScanning = false,
    this.error,
  });

  ScannerState copyWith({
    BluetoothState? bluetoothState,
    List<Device>? devices,
    bool? isScanning,
    String? error,
  }) {
    return ScannerState(
      bluetoothState: bluetoothState ?? this.bluetoothState,
      devices: devices ?? this.devices,
      isScanning: isScanning ?? this.isScanning,
      error: error,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ScannerState &&
        other.bluetoothState == bluetoothState &&
        _listEquals(other.devices, devices) &&
        other.isScanning == isScanning &&
        other.error == error;
  }

  @override
  int get hashCode {
    return Object.hash(
      bluetoothState,
      Object.hashAll(devices),
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
