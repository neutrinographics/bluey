import 'dart:async';
import 'package:bluey_platform_interface/bluey_platform_interface.dart';
import 'messages.g.dart';
import 'uuid_utils.dart';

/// Handles BLE scanning operations for the iOS platform.
///
/// Delegates to [BlueyHostApi] for native communication and manages
/// the scan result stream. Unlike Android, iOS (CoreBluetooth) may return
/// short UUIDs that must be expanded to full 128-bit format.
class IosScanner {
  final BlueyHostApi _hostApi;
  final StreamController<PlatformDevice> _scanController =
      StreamController<PlatformDevice>.broadcast();

  IosScanner(this._hostApi);

  /// Starts a BLE scan with the given [config] and returns a stream
  /// of discovered devices.
  Stream<PlatformDevice> scan(PlatformScanConfig config) {
    final dto = ScanConfigDto(
      serviceUuids: config.serviceUuids,
      timeoutMs: config.timeoutMs,
    );

    _hostApi.startScan(dto);

    return _scanController.stream;
  }

  /// Stops the current BLE scan.
  Future<void> stopScan() async {
    await _hostApi.stopScan();
  }

  /// Callback handler invoked when a device is discovered during scanning.
  void onDeviceDiscovered(DeviceDto device) {
    _scanController.add(_mapDevice(device));
  }

  /// Callback handler invoked when a scan completes.
  void onScanComplete() {
    // No-op for now
  }

  PlatformDevice _mapDevice(DeviceDto dto) {
    return PlatformDevice(
      id: dto.id,
      name: dto.name,
      rssi: dto.rssi,
      // Expand short UUIDs from CoreBluetooth to full 128-bit format
      serviceUuids: dto.serviceUuids.map(expandUuid).toList(),
      manufacturerDataCompanyId: dto.manufacturerDataCompanyId,
      manufacturerData: dto.manufacturerData,
    );
  }
}
