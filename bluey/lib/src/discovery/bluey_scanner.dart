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
import 'scan_state.dart';
import 'scanner.dart';

/// Concrete implementation of [Scanner] that delegates to the platform.
class BlueyScanner implements Scanner {
  final platform.BlueyPlatform _platform;
  final EventPublisher _eventBus;

  // I333/stream-conv: state machine replaces the previous boolean
  // `_isScanning`. The public `isScanning` getter remains, derived from
  // `_state == ScanState.scanning`.
  ScanState _state = ScanState.stopped;

  /// Broadcast controller for state-change deltas. `stateChanges`
  /// wraps this in a `Stream.multi` per the Task 6/7 convention so
  /// every new subscriber gets the current state replayed before
  /// receiving subsequent deltas.
  final StreamController<ScanState> _stateController =
      StreamController<ScanState>.broadcast();

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

    // Transition to invalidated terminal state and close the
    // stateChanges stream (Convention 3 — terminal close on
    // invalidation). Re-entry into _setState is guarded against by
    // the `if (_state == newState) return` short-circuit.
    _setState(ScanState.invalidated);
    if (!_stateController.isClosed) {
      _stateController.close();
    }
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
  ScanState get state => _state;

  @override
  Stream<ScanState> get stateChanges => Stream.multi(
    (controller) {
      if (!controller.isClosed) {
        controller.add(_state);
      }
      // If the underlying broadcast controller is already closed (we've
      // been invalidated and torn down), close the per-subscriber
      // controller after delivering the replay so consumers see the
      // terminal `onDone`.
      if (_stateController.isClosed) {
        controller.close();
        return;
      }
      final sub = _stateController.stream.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      controller.onCancel = sub.cancel;
    },
    isBroadcast: true,
  );

  @override
  bool get isScanning => _state == ScanState.scanning;

  /// Transition helper. Pushes the new state onto [_stateController] and
  /// emits the corresponding lifecycle event on [_eventBus] when one is
  /// defined for the transition. Idempotent for same-state writes.
  void _setState(ScanState newState) {
    if (_state == newState) return;
    final old = _state;
    _state = newState;
    if (!_stateController.isClosed) {
      _stateController.add(newState);
    }
    switch (newState) {
      case ScanState.starting:
        _eventBus.emit(ScanStartingEvent(source: 'BlueyScanner'));
      case ScanState.scanning:
        _eventBus.emit(ScanStartedEvent(source: 'BlueyScanner'));
      case ScanState.stopping:
        _eventBus.emit(ScanStoppingEvent(source: 'BlueyScanner'));
      case ScanState.stopped:
        if (old != ScanState.stopped) {
          _eventBus.emit(ScanStoppedEvent(source: 'BlueyScanner'));
        }
      case ScanState.invalidated:
        // No event — the stateChanges terminal close and I333 instance
        // invalidation are sufficient signals.
        break;
    }
  }

  @override
  Stream<ScanResult> scan({List<UUID>? services, Duration? timeout}) {
    _ensureValid();
    final config = platform.PlatformScanConfig(
      serviceUuids: services?.map((u) => u.toString()).toList() ?? [],
      timeoutMs: timeout?.inMilliseconds,
    );

    // stopped -> starting. Emits ScanStartingEvent via _setState.
    _setState(ScanState.starting);

    final controller = StreamController<ScanResult>(
      onCancel: () {
        // Convention 5 — last-subscriber cancel stops the platform
        // resource. stop() is idempotent: returns early if we are
        // already stopped/stopping.
        return stop();
      },
    );
    _activeScanControllers.add(controller);

    _platformSubscription = _platform
        .scan(config)
        .listen(
          (platformDevice) {
            // Real platforms don't fire a discrete "scan started" event
            // distinct from the subscription succeeding, so we treat
            // the first device emission as confirmation. The post-listen
            // microtask below covers the no-devices case.
            if (_state == ScanState.starting) {
              _setState(ScanState.scanning);
            }
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

    // The platform `scan()` call has returned a stream and we've
    // subscribed; treat that as confirmation that scanning is now
    // active. Done in a microtask so the `starting` transition is
    // observable on `stateChanges` before `scanning` overwrites it.
    scheduleMicrotask(() {
      if (_state == ScanState.starting) {
        _setState(ScanState.scanning);
      }
    });

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
    if (!controller.isClosed) {
      controller.close();
    }
    _activeScanControllers.remove(controller);
    // If the platform stream completed on its own (e.g. timeout-driven
    // close from the platform side) we still need to land in `stopped`.
    // Guard against the invalidated terminal — _setState already no-ops
    // for same-state writes but invalidated must remain terminal.
    if (_state != ScanState.invalidated && _state != ScanState.stopped) {
      _setState(ScanState.stopped);
    }
  }

  @override
  Future<void> stop() async {
    _timeoutTimer?.cancel();
    // Idempotent: nothing to do if we're already stopped/stopping or if
    // the scanner has been invalidated.
    if (_state == ScanState.stopped ||
        _state == ScanState.stopping ||
        _state == ScanState.invalidated) {
      return;
    }
    _setState(ScanState.stopping);
    await _platform.stopScan();
    _platformSubscription?.cancel();
    _platformSubscription = null;
    _setState(ScanState.stopped);
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
    // Land the state machine in `stopped` so `isScanning` flips back to
    // false. Skip if we're already in a terminal/rest state to avoid
    // emitting stale events. `invalidated` remains terminal.
    if (_state != ScanState.invalidated && _state != ScanState.stopped) {
      _setState(ScanState.stopped);
    }
    // Close the state controller if dispose ran without prior
    // invalidation. Safe to call on an already-closed controller.
    if (!_stateController.isClosed) {
      _stateController.close();
    }
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
