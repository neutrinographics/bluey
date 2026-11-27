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

  /// Raised by every [scan] and [stopScan], so a rejected start that a later
  /// call replaced is not reported against a scan nobody asks for any more.
  int _generation = 0;

  AndroidScanner(this._hostApi);

  /// Starts a BLE scan with the given [config] and returns a stream
  /// of discovered devices.
  Stream<PlatformDevice> scan(PlatformScanConfig config) {
    final dto = ScanConfigDto(
      serviceUuids: config.serviceUuids,
      timeoutMs: config.timeoutMs,
      mode: _mapScanModeToDto(config.scanMode),
    );

    final generation = ++_generation;
    _hostApi.startScan(dto).catchError((Object error) {
      if (generation == _generation) _scanController.addError(error);
    });

    return _scanController.stream;
  }

  ScanModeDto? _mapScanModeToDto(PlatformScanMode? mode) {
    if (mode == null) return null;
    switch (mode) {
      case PlatformScanMode.lowPower:
        return ScanModeDto.lowPower;
      case PlatformScanMode.balanced:
        return ScanModeDto.balanced;
      case PlatformScanMode.lowLatency:
        return ScanModeDto.lowLatency;
    }
  }

  /// Stops the current BLE scan.
  Future<void> stopScan() async {
    _generation++;
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

  /// Callback handler invoked when the platform refuses or loses the scan.
  void onScanFailed(int errorCode) {
    _scanController.addError(
      PlatformScanFailedException(_reasonOf(errorCode), code: errorCode),
    );
  }

  PlatformScanFailureReason _reasonOf(int errorCode) {
    switch (errorCode) {
      case 1:
        return PlatformScanFailureReason.alreadyStarted;
      case 2:
        return PlatformScanFailureReason.registrationFailed;
      case 3:
        return PlatformScanFailureReason.internalError;
      case 4:
        return PlatformScanFailureReason.unsupported;
      case 5:
        return PlatformScanFailureReason.outOfHardwareResources;
      case 6:
        return PlatformScanFailureReason.startedTooOften;
      default:
        return PlatformScanFailureReason.unknown;
    }
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
