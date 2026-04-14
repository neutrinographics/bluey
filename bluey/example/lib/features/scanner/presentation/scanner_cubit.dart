import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:bluey/bluey.dart';

import '../application/scan_for_devices.dart';
import '../application/stop_scan.dart';
import '../application/get_bluetooth_state.dart';
import '../application/request_permissions.dart';
import '../application/request_enable.dart';
import 'scanner_state.dart';

/// Cubit for managing scanner state.
class ScannerCubit extends Cubit<ScannerState> {
  final ScanForDevices _scanForDevices;
  final StopScan _stopScan;
  final GetBluetoothState _getBluetoothState;
  final RequestPermissions _requestPermissions;
  final RequestEnable _requestEnable;

  StreamSubscription<BluetoothState>? _stateSubscription;
  StreamSubscription<ScanResult>? _scanSubscription;

  ScannerCubit({
    required ScanForDevices scanForDevices,
    required StopScan stopScan,
    required GetBluetoothState getBluetoothState,
    required RequestPermissions requestPermissions,
    required RequestEnable requestEnable,
  }) : _scanForDevices = scanForDevices,
       _stopScan = stopScan,
       _getBluetoothState = getBluetoothState,
       _requestPermissions = requestPermissions,
       _requestEnable = requestEnable,
       super(const ScannerState());

  /// Initializes the cubit by getting the current Bluetooth state
  /// and subscribing to state changes.
  void initialize() {
    // Get initial state
    emit(state.copyWith(bluetoothState: _getBluetoothState.current));

    // Listen to state changes
    _stateSubscription = _getBluetoothState().listen(
      (bluetoothState) {
        emit(state.copyWith(bluetoothState: bluetoothState));
      },
      onError: (error) {
        emit(state.copyWith(error: 'Bluetooth state error: $error'));
      },
    );
  }

  /// Starts scanning for BLE devices.
  void startScan({Duration timeout = const Duration(seconds: 15)}) {
    if (!state.bluetoothState.isReady) {
      emit(
        state.copyWith(
          error:
              'Bluetooth is not ready. Current state: ${state.bluetoothState}',
        ),
      );
      return;
    }

    emit(state.copyWith(scanResults: [], isScanning: true, error: null));

    final results = <ScanResult>[];

    _scanSubscription = _scanForDevices(timeout: timeout).listen(
      (result) {
        // Update existing result or add new one
        final index = results.indexWhere(
          (r) => r.device.id == result.device.id,
        );
        if (index >= 0) {
          results[index] = result;
        } else {
          results.add(result);
        }
        // Sort by RSSI (strongest first)
        results.sort((a, b) => b.rssi.compareTo(a.rssi));
        emit(state.copyWith(scanResults: List.from(results)));
      },
      onDone: () {
        emit(state.copyWith(isScanning: false));
      },
      onError: (error) {
        emit(state.copyWith(isScanning: false, error: 'Scan error: $error'));
      },
    );
  }

  /// Stops the current scan.
  Future<void> stopScan() async {
    try {
      await _stopScan();
      await _scanSubscription?.cancel();
      _scanSubscription = null;
      emit(state.copyWith(isScanning: false));
    } catch (e) {
      emit(state.copyWith(isScanning: false, error: 'Failed to stop scan: $e'));
    }
  }

  /// Requests Bluetooth permissions.
  Future<bool> requestPermissions() async {
    try {
      final granted = await _requestPermissions();
      if (!granted) {
        emit(
          state.copyWith(
            error: 'Permission denied. Please grant permission in Settings.',
          ),
        );
      }
      return granted;
    } catch (e) {
      emit(state.copyWith(error: 'Failed to request permissions: $e'));
      return false;
    }
  }

  /// Requests the user to enable Bluetooth.
  Future<void> requestEnable() async {
    try {
      await _requestEnable();
    } catch (e) {
      emit(state.copyWith(error: 'Failed to enable Bluetooth: $e'));
    }
  }

  /// Opens the system Bluetooth settings.
  Future<void> openSettings() async {
    try {
      await _requestEnable.openSettings();
    } catch (e) {
      emit(state.copyWith(error: 'Failed to open settings: $e'));
    }
  }

  /// Clears any error message.
  void clearError() {
    emit(state.copyWith(error: null));
  }

  @override
  Future<void> close() {
    _stateSubscription?.cancel();
    _scanSubscription?.cancel();
    return super.close();
  }
}
