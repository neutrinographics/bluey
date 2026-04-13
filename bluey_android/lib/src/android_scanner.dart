import 'dart:async';
import 'package:bluey_platform_interface/bluey_platform_interface.dart';
import 'messages.g.dart';

/// Handles BLE scanning operations for the Android platform.
///
/// Delegates to [BlueyHostApi] for native communication and manages
/// the scan result stream.
class AndroidScanner {
  final BlueyHostApi _hostApi;
  final StreamController<PlatformDevice> _scanController =
      StreamController<PlatformDevice>.broadcast();

  AndroidScanner(this._hostApi);

  /// Starts a BLE scan with the given [config] and returns a stream
  /// of discovered devices.
  Stream<PlatformDevice> scan(PlatformScanConfig config) {
    final dto = ScanConfigDto(
      serviceUuids: config.serviceUuids,
      timeoutMs: config.timeoutMs,
    );

    // Start scan (async, doesn't block)
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
      serviceUuids: dto.serviceUuids,
      manufacturerDataCompanyId: dto.manufacturerDataCompanyId,
      manufacturerData: dto.manufacturerData,
    );
  }
}
