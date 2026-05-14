import 'dart:async';
import 'dart:typed_data';

import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;

import '../event_bus.dart';
import '../events.dart';
import '../platform/bluetooth_state.dart';
import '../shared/error_translation.dart';
import '../shared/exceptions.dart';
import '../shared/manufacturer_data.dart';
import '../shared/uuid.dart';
import 'advertisement.dart';
import 'device.dart';
import 'scan_result.dart';
import 'scanner.dart';

/// Concrete implementation of [Scanner] that delegates to the platform.
class BlueyScanner implements Scanner {
  final platform.BlueyPlatform _platform;
  final EventPublisher _eventBus;
  bool _isScanning = false;
  Timer? _timeoutTimer;
  StreamSubscription<platform.PlatformDevice>? _platformSubscription;

  // I333: adapter-state invalidation. The scanner subscribes to
  // platform.stateStream at construction; any non-`on` emission flips
  // [_invalidated] to true and tears down the active scan stream(s).
  // Subsequent [scan] calls throw [StaleHandleException].
  bool _invalidated = false;
  BluetoothState? _invalidationState;
  StreamSubscription<platform.BluetoothState>? _stateSubscription;

  /// Active scan controllers — typically zero or one but the API doesn't
  /// forbid overlapping `scan()` calls so we track a list. Closed and
  /// cleared on invalidation so consumers see `onDone` instead of a
  /// silent hang.
  final List<StreamController<ScanResult>> _activeScanControllers = [];

  BlueyScanner(this._platform, this._eventBus) {
    // I333: mirror BlueyServer / BlueyConnection — invalidate on any
    // non-`on` adapter state. Map the platform-interface enum to the
    // domain enum before deciding so [triggeringState] surfaces as the
    // domain type.
    _stateSubscription = _platform.stateStream.listen((platformState) {
      final domainState = _mapPlatformState(platformState);
      if (domainState != BluetoothState.on) {
        _invalidate(domainState);
      }
    });
  }

  /// Maps the platform-interface [platform.BluetoothState] to the
  /// domain [BluetoothState]. Mirrors `BlueyServer._mapPlatformState`
  /// and `BlueyConnection._mapPlatformState`; kept local so the scanner
  /// doesn't reach across bounded contexts.
  BluetoothState _mapPlatformState(platform.BluetoothState s) {
    switch (s) {
      case platform.BluetoothState.unknown:
        return BluetoothState.unknown;
      case platform.BluetoothState.unsupported:
        return BluetoothState.unsupported;
      case platform.BluetoothState.unauthorized:
        return BluetoothState.unauthorized;
      case platform.BluetoothState.off:
        return BluetoothState.off;
      case platform.BluetoothState.on:
        return BluetoothState.on;
    }
  }

  /// Marks this scanner as terminal-failed. Idempotent — re-entry is a
  /// no-op. Cancels the state subscription, cancels the in-flight
  /// platform scan subscription, closes every active scan controller,
  /// and fails subsequent [scan] calls with [StaleHandleException].
  void _invalidate(BluetoothState triggeringState) {
    if (_invalidated) return;
    _invalidated = true;
    _invalidationState = triggeringState;

    _stateSubscription?.cancel();
    _stateSubscription = null;

    // Cancel the platform-side scan subscription so it can't call
    // .add(...) on a closed controller — mirrors the lesson from
    // BlueyServer / BlueyConnection where surviving subscriptions
    // crashed with StateError after invalidation.
    _platformSubscription?.cancel();
    _platformSubscription = null;
    _timeoutTimer?.cancel();
    _timeoutTimer = null;

    // Close every owned scan controller so consumers see onDone.
    for (final c in List.of(_activeScanControllers)) {
      if (!c.isClosed) c.close();
    }
    _activeScanControllers.clear();
    _isScanning = false;
  }

  /// Throws [StaleHandleException] if this scanner has been invalidated
  /// by a prior adapter-state transition.
  void _ensureValid() {
    if (_invalidated) {
      throw StaleHandleException(
        triggeringState: _invalidationState!,
        instanceType: InvalidatedInstance.scanner,
      );
    }
  }

  @override
  bool get isScanning => _isScanning;

  @override
  Stream<ScanResult> scan({List<UUID>? services, Duration? timeout}) {
    _ensureValid();
    final config = platform.PlatformScanConfig(
      serviceUuids: services?.map((u) => u.toString()).toList() ?? [],
      timeoutMs: timeout?.inMilliseconds,
    );

    _isScanning = true;
    _eventBus.emit(ScanStartedEvent(serviceFilter: services, timeout: timeout));

    final controller = StreamController<ScanResult>();
    _activeScanControllers.add(controller);

    _platformSubscription = _platform
        .scan(config)
        .listen(
          (platformDevice) {
            final result = _mapScanResult(platformDevice);
            _eventBus.emit(
              DeviceDiscoveredEvent(
                deviceId: result.device.id,
                name: result.device.name,
                rssi: result.rssi,
              ),
            );
            if (!controller.isClosed) controller.add(result);
          },
          onDone: () {
            _timeoutTimer?.cancel();
            _finishScan(controller);
          },
          onError: (Object error) {
            _timeoutTimer?.cancel();
            if (!controller.isClosed) {
              controller.addError(
                translatePlatformException(error, operation: 'scan'),
              );
            }
            _finishScan(controller);
          },
        );

    if (timeout != null) {
      _timeoutTimer = Timer(
        timeout,
        () => stop().then((_) {
          if (!controller.isClosed) {
            controller.close();
          }
          _activeScanControllers.remove(controller);
        }),
      );
    }

    return controller.stream;
  }

  void _finishScan(StreamController<ScanResult> controller) {
    _isScanning = false;
    _eventBus.emit(ScanStoppedEvent());
    if (!controller.isClosed) {
      controller.close();
    }
    _activeScanControllers.remove(controller);
  }

  @override
  Future<void> stop() async {
    _timeoutTimer?.cancel();
    if (!_isScanning) return;
    await _platform.stopScan();
    _platformSubscription?.cancel();
    _platformSubscription = null;
    _isScanning = false;
    _eventBus.emit(ScanStoppedEvent());
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _platformSubscription?.cancel();
    _platformSubscription = null;
    // I333: cancel the adapter-state subscription on normal dispose so
    // it doesn't fire post-disposal and call _invalidate on already-
    // cleaned-up state.
    _stateSubscription?.cancel();
    _stateSubscription = null;
    // Close every owned scan controller. close() is a no-op on an
    // already-closed controller (e.g. if _invalidate ran first).
    for (final c in List.of(_activeScanControllers)) {
      if (!c.isClosed) c.close();
    }
    _activeScanControllers.clear();
    _isScanning = false;
  }

  ScanResult _mapScanResult(platform.PlatformDevice platformDevice) {
    ManufacturerData? manufacturerData;
    if (platformDevice.manufacturerDataCompanyId != null &&
        platformDevice.manufacturerData != null) {
      manufacturerData = ManufacturerData(
        platformDevice.manufacturerDataCompanyId!,
        Uint8List.fromList(platformDevice.manufacturerData!),
      );
    }

    final serviceUuids =
        platformDevice.serviceUuids.map((s) => UUID(s)).toList();

    final advertisement = Advertisement(
      serviceUuids: serviceUuids,
      serviceData: {},
      manufacturerData: manufacturerData,
      isConnectable: true,
    );

    final device = Device(
      id: _deviceIdToUuid(platformDevice.id),
      address: platformDevice.id,
      name: platformDevice.name,
    );

    return ScanResult(
      device: device,
      rssi: platformDevice.rssi,
      advertisement: advertisement,
    );
  }

  /// Converts a platform device ID to a UUID.
  ///
  /// On Android, the ID is a MAC address (e.g., "AA:BB:CC:DD:EE:FF").
  /// On iOS, the ID is already a UUID.
  UUID _deviceIdToUuid(String id) {
    if (id.length == 36 && id.contains('-')) {
      return UUID(id);
    }
    final clean = id.replaceAll(':', '').toLowerCase();
    final padded = clean.padLeft(32, '0');
    return UUID(padded);
  }
}
