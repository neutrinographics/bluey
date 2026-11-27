import 'dart:async';
import 'dart:typed_data';

import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;

import '../../../../shared/application/log.dart';
import '../../../../shared/application/log_level.dart';
import '../../../../shared/application/now.dart';
import '../../../../shared/domain/device_address.dart';
import '../../../../shared/domain/either.dart';
import '../../../../shared/domain/failure.dart';
import '../../../../shared/domain/manufacturer_data.dart';
import '../../../../shared/domain/radio_outage.dart';
import '../../../../shared/domain/uuid.dart';
import '../../../../shared/domain/uuid_parsing.dart';
import '../../../../shared/infrastructure/radio_outages.dart';
import '../../application/ports/scanning.dart';
import '../../domain/advertisement.dart';
import '../../domain/device.dart';
import '../../domain/scan_ask.dart';
import '../../domain/scan_failure.dart';
import '../../domain/scan_filter.dart';
import '../../domain/scan_mode.dart';
import '../../domain/scan_result.dart';
import 'platform_scan_failures.dart';

/// Discovery's [Scanning] over [platform.BlueyPlatform], so the scan session
/// runs on a phone exactly as it runs over the in-memory double.
///
/// A device the platform reports that cannot be read is dropped with a warn
/// line rather than failing the scan, since one odd advertisement must not
/// end discovery of the others. The platform's own time limit is never used:
/// the session ends scans on its own clock.
final class PlatformScanning implements Scanning {
  /// [now] stamps each result with when it was heard.
  PlatformScanning(
    platform.BlueyPlatform platform, {
    required Log log,
    Now now = DateTime.now,
  }) : _platform = platform,
       _log = log,
       _now = now;

  final platform.BlueyPlatform _platform;
  final Log _log;
  final Now _now;
  final StreamController<ScanReport> _reports = StreamController<ScanReport>();
  StreamSubscription<platform.PlatformDevice>? _listening;

  @override
  void scan(ScanCoverage coverage) {
    unawaited(_listening?.cancel());
    _listening = _platform
        .scan(
          platform.PlatformScanConfig(
            serviceUuids: [
              for (final service in _servicesOf(coverage.filter))
                service.toString(),
            ],
            timeoutMs: null,
            scanMode: _platformModeOf(coverage.mode),
          ),
        )
        .listen(_hear, onError: _refused);
  }

  @override
  Future<Either<ScanFailure, void>> stop() async {
    try {
      await _platform.stopScan();
    } on Object catch (error) {
      return Left(scanFailureFrom(error));
    }
    unawaited(_listening?.cancel());
    _listening = null;
    return const Right(null);
  }

  @override
  Stream<ScanReport> get reports => _reports.stream;

  @override
  Stream<RadioOutage> get outages => radioOutagesOf(_platform);

  void _hear(platform.PlatformDevice device) {
    _resultFrom(device, _now()).fold(
      (failure) => _log.log(
        BlueyLogLevel.warn,
        'bluey',
        'scan result dropped',
        data: {'device': device.id, 'error': failure.message},
        errorCode: failure.runtimeType.toString(),
      ),
      (result) => _reports.add(Heard(result)),
    );
  }

  void _refused(Object error) {
    unawaited(_listening?.cancel());
    _listening = null;
    _reports.add(Refused(scanFailureFrom(error)));
  }
}

/// A device whose advertisement cannot be read as one, kept whole so the log
/// line can say why it was dropped.
final class UnreadableAdvertisement implements Failure {
  const UnreadableAdvertisement(this.message);

  @override
  final String message;
}

Iterable<UUID> _servicesOf(ScanFilter filter) => switch (filter) {
  Everything() => const [],
  ServicesOnly(:final services) => services,
};

platform.PlatformScanMode? _platformModeOf(ScanMode? mode) => switch (mode) {
  ScanMode.lowPower => platform.PlatformScanMode.lowPower,
  ScanMode.balanced => platform.PlatformScanMode.balanced,
  ScanMode.lowLatency => platform.PlatformScanMode.lowLatency,
  null => null,
};

Either<Failure, ScanResult> _resultFrom(
  platform.PlatformDevice device,
  DateTime heardAt,
) => _servicesFrom(device.serviceUuids).flatMap(
  (services) => _manufacturerDataFrom(device).map(
    (manufacturerData) => ScanResult(
      device: Device(address: DeviceAddress(device.id), name: device.name),
      rssi: device.rssi,
      advertisement: Advertisement(
        serviceUuids: services,
        serviceData: const {},
        manufacturerData: manufacturerData,
        isConnectable: true,
      ),
      lastSeen: heardAt,
    ),
  ),
);

Either<Failure, List<UUID>> _servicesFrom(List<String> raw) {
  final services = <UUID>[];
  for (final text in raw) {
    final parsed = uuidFrom(text);
    if (parsed case Left(:final value)) return Left(value);
    services.add((parsed as Right<Failure, UUID>).value);
  }
  return Right(services);
}

Either<Failure, ManufacturerData?> _manufacturerDataFrom(
  platform.PlatformDevice device,
) {
  final companyId = device.manufacturerDataCompanyId;
  final bytes = device.manufacturerData;
  if (bytes == null) return const Right(null);
  if (companyId == null) {
    return const Left(
      UnreadableAdvertisement('Manufacturer data came without a company id'),
    );
  }
  return Right(ManufacturerData(companyId, Uint8List.fromList(bytes)));
}
