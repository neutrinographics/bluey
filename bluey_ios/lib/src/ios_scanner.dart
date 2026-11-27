import 'dart:async';
import 'package:bluey_platform_interface/bluey_platform_interface.dart';
import 'package:flutter/services.dart' show PlatformException;
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

  /// Raised by every [scan] and [stopScan], so a rejected start that a later
  /// call replaced is not reported against a scan nobody asks for any more.
  int _generation = 0;

  IosScanner(this._hostApi);

  /// Starts a BLE scan with the given [config] and returns a stream
  /// of discovered devices.
  Stream<PlatformDevice> scan(PlatformScanConfig config) {
    final dto = ScanConfigDto(
      serviceUuids: config.serviceUuids,
      timeoutMs: config.timeoutMs,
    );

    final generation = ++_generation;
    _hostApi.startScan(dto).catchError((Object error) {
      if (generation != _generation) return;
      _scanController.addError(_translate(error));
    });

    return _scanController.stream;
  }

  /// Stops the current BLE scan.
  Future<void> stopScan() async {
    _generation++;
    await _hostApi.stopScan();
  }

  /// Gives a start the platform rejected the same typed error every other
  /// iOS call gives an adapter that is not ready.
  Object _translate(Object error) {
    if (error is PlatformException && error.code == 'bluetooth-unavailable') {
      return PlatformBluetoothUnavailableException(message: error.message);
    }
    return error;
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
