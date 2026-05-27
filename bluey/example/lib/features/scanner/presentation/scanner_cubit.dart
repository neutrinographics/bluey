import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:bluey/bluey.dart';

import '../application/scan_for_devices.dart';
import '../application/get_bluetooth_state.dart';
import '../application/request_permissions.dart';
import '../application/request_enable.dart';
import 'scanner_state.dart';

/// Cubit for managing scanner state.
class ScannerCubit extends Cubit<ScannerState> {
  final ScanForDevices _scanForDevices;
  final GetBluetoothState _getBluetoothState;
  final RequestPermissions _requestPermissions;
  final RequestEnable _requestEnable;
  final Bluey _bluey;

  StreamSubscription<BluetoothState>? _stateSubscription;
  StreamSubscription<ScanResult>? _scanSubscription;
  StreamSubscription<ScanState>? _scanStateSubscription;
  StreamSubscription<BlueyEvent>? _eventsSubscription;

  Scanner? _scanner;

  ScannerCubit({
    required ScanForDevices scanForDevices,
    required GetBluetoothState getBluetoothState,
    required RequestPermissions requestPermissions,
    required RequestEnable requestEnable,
    required Bluey bluey,
  }) : _scanForDevices = scanForDevices,
       _getBluetoothState = getBluetoothState,
       _requestPermissions = requestPermissions,
       _requestEnable = requestEnable,
       _bluey = bluey,
       super(const ScannerState());

  /// Initializes the cubit by subscribing to Bluetooth state changes,
  /// scanner state transitions, and Bluey lifecycle events.
  void initialize() {
    // Listen to Bluetooth state changes (replays current on subscribe
    // per Convention 2).
    _stateSubscription = _getBluetoothState().listen(
      (bluetoothState) {
        emit(state.copyWith(bluetoothState: bluetoothState));
      },
      onError: (error) {
        emit(state.copyWith(error: 'Bluetooth state error: $error'));
      },
    );

    // Hold one Scanner for this cubit's lifetime and subscribe to its
    // state transitions (replays current state on subscribe).
    _scanner = _bluey.scanner();
    _scanStateSubscription = _scanner!.stateChanges.listen(
      (scanState) {
        emit(state.copyWith(scanState: scanState));
      },
    );

    // Ingest scan lifecycle events into the scanLog (capped at 100).
    _eventsSubscription = _bluey.events.listen(
      (event) {
        if (event is ScanStartingEvent ||
            event is ScanStartedEvent ||
            event is ScanStoppingEvent ||
            event is ScanStoppedEvent) {
          final updated = [...state.scanLog, event];
          final capped =
              updated.length > 100
                  ? updated.sublist(updated.length - 100)
                  : updated;
          emit(state.copyWith(scanLog: capped));
        }
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

    emit(state.copyWith(scanResults: [], error: null));

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
        emit(state.copyWith(scanResults: _sorted(results)));
      },
    );
  }

  /// Stops the current scan.
  ///
  /// Cancelling the subscription triggers bluey's onCancel → stop()
  /// so the platform scan stops automatically.
  Future<void> stopScan() async {
    await _scanSubscription?.cancel();
    _scanSubscription = null;
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

  /// Changes the sort order of scan results.
  void setSortMode(SortMode mode) {
    emit(
      state.copyWith(
        sortMode: mode,
        scanResults: _sorted(state.scanResults, mode),
      ),
    );
  }

  List<ScanResult> _sorted(List<ScanResult> results, [SortMode? override]) {
    final mode = override ?? state.sortMode;
    final sorted = List<ScanResult>.from(results);
    switch (mode) {
      case SortMode.signalStrength:
        sorted.sort((a, b) => b.rssi.compareTo(a.rssi));
      case SortMode.name:
        sorted.sort((a, b) {
          final aName = a.device.name;
          final bName = b.device.name;
          if (aName == null && bName == null) return 0;
          if (aName == null) return 1;
          if (bName == null) return -1;
          return aName.compareTo(bName);
        });
      case SortMode.deviceId:
        sorted.sort(
          (a, b) => a.device.id.toString().compareTo(b.device.id.toString()),
        );
    }
    return sorted;
  }

  /// Clears any error message.
  void clearError() {
    emit(state.copyWith(error: null));
  }

  @override
  Future<void> close() {
    _stateSubscription?.cancel();
    _scanSubscription?.cancel();
    _scanStateSubscription?.cancel();
    _eventsSubscription?.cancel();
    return super.close();
  }
}
