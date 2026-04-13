import 'dart:typed_data';

import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;

import '../event_bus.dart';
import '../events.dart';
import '../shared/manufacturer_data.dart';
import '../shared/uuid.dart';
import 'advertisement.dart';
import 'device.dart';
import 'scan_result.dart';
import 'scanner.dart';

/// Concrete implementation of [Scanner] that delegates to the platform.
class BlueyScanner implements Scanner {
  final platform.BlueyPlatform _platform;
  final BlueyEventBus _eventBus;
  bool _isScanning = false;

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

    return _platform
        .scan(config)
        .map((platformDevice) {
          final result = _mapScanResult(platformDevice);
          _eventBus.emit(
            DeviceDiscoveredEvent(
              deviceId: result.device.id,
              name: result.device.name,
              rssi: result.rssi,
            ),
          );
          return result;
        });
  }

  @override
  Future<void> stop() async {
    if (!_isScanning) return;
    await _platform.stopScan();
    _isScanning = false;
    _eventBus.emit(ScanStoppedEvent());
  }

  @override
  void dispose() {
    _isScanning = false;
  }

  // === Private mapping methods ===

  ScanResult _mapScanResult(platform.PlatformDevice platformDevice) {
    // Convert manufacturer data
    ManufacturerData? manufacturerData;
    if (platformDevice.manufacturerDataCompanyId != null &&
        platformDevice.manufacturerData != null) {
      manufacturerData = ManufacturerData(
        platformDevice.manufacturerDataCompanyId!,
        Uint8List.fromList(platformDevice.manufacturerData!),
      );
    }

    // Convert service UUIDs
    final serviceUuids =
        platformDevice.serviceUuids.map((s) => UUID(s)).toList();

    // Create advertisement
    final advertisement = Advertisement(
      serviceUuids: serviceUuids,
      serviceData: {},
      manufacturerData: manufacturerData,
      isConnectable: true,
    );

    // Create device (identity only)
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
    // Check if it's already a UUID format
    if (id.length == 36 && id.contains('-')) {
      return UUID(id);
    }

    // Convert MAC address to UUID format
    final clean = id.replaceAll(':', '').toLowerCase();
    final padded = clean.padLeft(32, '0');
    return UUID(padded);
  }
}
