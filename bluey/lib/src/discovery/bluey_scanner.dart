import 'dart:async';
import 'dart:typed_data';

import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;

import '../event_bus.dart';
import '../events.dart';
import '../shared/error_translation.dart';
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

  BlueyScanner(this._platform, this._eventBus);

  @override
  bool get isScanning => _isScanning;

  @override
  Stream<ScanResult> scan({List<UUID>? services, Duration? timeout}) {
    final config = platform.PlatformScanConfig(
      serviceUuids: services?.map((u) => u.toString()).toList() ?? [],
      timeoutMs: timeout?.inMilliseconds,
    );

    _isScanning = true;
    _eventBus.emit(ScanStartedEvent(serviceFilter: services, timeout: timeout));

    final controller = StreamController<ScanResult>();

    _platformSubscription = _platform.scan(config).listen(
      (platformDevice) {
        final result = _mapScanResult(platformDevice);
        _eventBus.emit(
          DeviceDiscoveredEvent(
            deviceId: result.device.id,
            name: result.device.name,
            rssi: result.rssi,
          ),
        );
        controller.add(result);
      },
      onDone: () {
        _timeoutTimer?.cancel();
        _finishScan(controller);
      },
      onError: (Object error) {
        _timeoutTimer?.cancel();
        controller.addError(translatePlatformException(
          error,
          operation: 'scan',
        ));
        _finishScan(controller);
      },
    );

    if (timeout != null) {
      _timeoutTimer = Timer(timeout, () => stop().then((_) {
        if (!controller.isClosed) {
          controller.close();
        }
      }));
    }

    return controller.stream;
  }

  void _finishScan(StreamController<ScanResult> controller) {
    _isScanning = false;
    _eventBus.emit(ScanStoppedEvent());
    if (!controller.isClosed) {
      controller.close();
    }
  }

  @override
  Future<void> stop() async {
    _timeoutTimer?.cancel();
    if (!_isScanning) return;
    await _platform.stopScan();
    _platformSubscription?.cancel();
    _isScanning = false;
    _eventBus.emit(ScanStoppedEvent());
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _platformSubscription?.cancel();
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
