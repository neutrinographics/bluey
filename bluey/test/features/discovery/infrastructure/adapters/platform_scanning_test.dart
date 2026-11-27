import 'dart:async';

import 'package:bluey/bluey.dart' show DeviceAddress, UUID;
import 'package:bluey/src/features/discovery/application/ports/scanning.dart';
import 'package:bluey/src/features/discovery/domain/scan_ask.dart';
import 'package:bluey/src/features/discovery/domain/scan_failure.dart';
import 'package:bluey/src/features/discovery/domain/scan_filter.dart';
import 'package:bluey/src/features/discovery/domain/scan_mode.dart';
import 'package:bluey/src/features/discovery/domain/scan_result.dart';
import 'package:bluey/src/features/discovery/infrastructure/adapters/platform_scanning.dart';
import 'package:bluey/src/shared/application/log_level.dart';
import 'package:bluey/src/shared/domain/radio_outage.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';

import '../../../../fakes/fake_platform.dart';
import '../../../../fixtures/features/discovery/application/ports/scanning_contract.dart';
import '../../../../fixtures/shared/application/recording_log.dart';

final _heardAt = DateTime.utc(2026, 11, 27);

void main() {
  scanningContract(
    'PlatformScanning over FakeBlueyPlatform',
    () => _FakePlatformHarness(),
  );

  late FakeBlueyPlatform fake;
  late RecordingLog log;
  late PlatformScanning scanning;
  late List<ScanReport> heard;
  late List<Object> errors;
  late StreamSubscription<ScanReport> subscription;

  setUp(() {
    fake = FakeBlueyPlatform();
    log = RecordingLog();
    scanning = PlatformScanning(fake, log: log, now: () => _heardAt);
    heard = [];
    errors = [];
    subscription = scanning.reports.listen(heard.add, onError: errors.add);
  });

  tearDown(() => subscription.cancel());

  group('what the platform is asked', () {
    for (final coverage in [
      const ScanCoverage(filter: Everything()),
      ScanCoverage(filter: ScanFilter.of([UUID.short(0x180D)])),
      const ScanCoverage(filter: Everything(), mode: ScanMode.lowPower),
    ]) {
      test('a scan sets no time limit for $coverage', () {
        // act
        scanning.scan(coverage);

        // assert
        expect(fake.lastScanConfig!.timeoutMs, isNull);
      });
    }

    test('everything asks for no service', () {
      // act
      scanning.scan(const ScanCoverage(filter: Everything()));

      // assert
      expect(fake.lastScanConfig!.serviceUuids, isEmpty);
    });

    test('services are asked for as their text', () {
      // arrange
      final service = UUID.short(0x180D);

      // act
      scanning.scan(ScanCoverage(filter: ScanFilter.of([service])));

      // assert
      expect(fake.lastScanConfig!.serviceUuids, [service.toString()]);
    });

    for (final (mode, expected) in [
      (ScanMode.lowPower, platform.PlatformScanMode.lowPower),
      (ScanMode.balanced, platform.PlatformScanMode.balanced),
      (ScanMode.lowLatency, platform.PlatformScanMode.lowLatency),
      (null, null),
    ]) {
      test('mode $mode asks for $expected', () {
        // act
        scanning.scan(ScanCoverage(filter: const Everything(), mode: mode));

        // assert
        expect(fake.lastScanConfig!.scanMode, expected);
      });
    }
  });

  group('what is heard', () {
    test('a device becomes a result with its address, name, signal, services '
        'and manufacturer data', () async {
      // arrange
      scanning.scan(const ScanCoverage(filter: Everything()));

      // act
      fake.simulateScanResult(
        const platform.PlatformDevice(
          id: 'AA:BB:CC:DD:EE:01',
          name: 'Thermometer',
          rssi: -71,
          serviceUuids: ['180d'],
          manufacturerDataCompanyId: 0x004C,
          manufacturerData: [1, 2, 3],
        ),
      );
      await pumpEventQueue();

      // assert
      final result = (heard.single as Heard).result;
      expect(result.device.address, const DeviceAddress('AA:BB:CC:DD:EE:01'));
      expect(result.device.name, 'Thermometer');
      expect(result.rssi, -71);
      expect(result.advertisement.serviceUuids, [UUID.short(0x180D)]);
      expect(result.advertisement.manufacturerData!.companyId, 0x004C);
      expect(result.advertisement.manufacturerData!.data, [1, 2, 3]);
      expect(result.advertisement.serviceData, isEmpty);
      expect(result.advertisement.isConnectable, isTrue);
      expect(result.lastSeen, _heardAt);
    });

    test(
      'a company id without bytes is heard with no manufacturer data',
      () async {
        // arrange
        scanning.scan(const ScanCoverage(filter: Everything()));

        // act
        fake.simulateScanResult(
          const platform.PlatformDevice(
            id: 'AA:BB:CC:DD:EE:01',
            name: null,
            rssi: -60,
            serviceUuids: [],
            manufacturerDataCompanyId: 0x004C,
            manufacturerData: null,
          ),
        );
        await pumpEventQueue();

        // assert
        expect(
          (heard.single as Heard).result.advertisement.manufacturerData,
          isNull,
        );
      },
    );

    test('a device with a malformed service is dropped with one warn line and '
        'the next device is still heard', () async {
      // arrange
      scanning.scan(const ScanCoverage(filter: Everything()));

      // act
      fake.simulateScanResult(_device('AA:BB:CC:DD:EE:01', ['not-a-uuid']));
      fake.simulateScanResult(_device('AA:BB:CC:DD:EE:02', []));
      await pumpEventQueue();

      // assert
      expect(heard.map((report) => (report as Heard).result.device.address), [
        const DeviceAddress('AA:BB:CC:DD:EE:02'),
      ]);
      expect(log.records, hasLength(1));
      expect(log.records.single.level, BlueyLogLevel.warn);
      expect(log.records.single.data['device'], 'AA:BB:CC:DD:EE:01');
      expect(log.records.single.errorCode, 'MalformedUuid');
      expect(log.records.single.data['error'], 'Not a UUID: "not-a-uuid"');
      expect(errors, isEmpty);
    });

    test('a device with manufacturer bytes but no company id is dropped with '
        'one warn line and the next device is still heard', () async {
      // arrange
      scanning.scan(const ScanCoverage(filter: Everything()));

      // act
      fake.simulateScanResult(
        const platform.PlatformDevice(
          id: 'AA:BB:CC:DD:EE:01',
          name: null,
          rssi: -60,
          serviceUuids: [],
          manufacturerDataCompanyId: null,
          manufacturerData: [1],
        ),
      );
      fake.simulateScanResult(_device('AA:BB:CC:DD:EE:02', []));
      await pumpEventQueue();

      // assert
      expect(heard, hasLength(1));
      expect(log.records, hasLength(1));
      expect(log.records.single.level, BlueyLogLevel.warn);
      expect(log.records.single.errorCode, 'UnreadableAdvertisement');
      expect(
        log.records.single.data['error'],
        'Manufacturer data came without a company id',
      );
      expect(errors, isEmpty);
    });
  });

  group('what the platform reports wrong', () {
    test('a stream error is a refusal in Discovery\'s words and is logged '
        'nowhere as an error on reports', () async {
      // arrange
      fake.simulateScanFailure(PlatformException(code: 'E1', message: 'boom'));

      // act
      scanning.scan(const ScanCoverage(filter: Everything()));
      await pumpEventQueue();

      // assert
      expect(heard.single, isA<Refused>());
      expect((heard.single as Refused).failure, isA<UnexpectedScanFailure>());
      expect(errors, isEmpty);
    });

    test('a stop the platform fails answers the failure in Discovery\'s '
        'words', () async {
      // arrange
      scanning.scan(const ScanCoverage(filter: Everything()));
      fake.enqueueFault(
        FakeOp.stopScan,
        const platform.PlatformPermissionDeniedException(
          'stopScan',
          permission: 'BLUETOOTH_SCAN',
        ),
      );

      // act
      final answer = await scanning.stop();

      // assert
      expect(
        answer.fold((failure) => failure, (_) => null),
        const ScanPermissionMissing('BLUETOOTH_SCAN'),
      );
    });
  });
}

platform.PlatformDevice _device(String id, List<String> services) =>
    platform.PlatformDevice(
      id: id,
      name: 'Device',
      rssi: -60,
      serviceUuids: services,
      manufacturerDataCompanyId: null,
      manufacturerData: null,
    );

class _FakePlatformHarness implements ScanningHarness {
  _FakePlatformHarness() {
    scanning = PlatformScanning(fake, log: RecordingLog(), now: () => _heardAt);
  }

  final fake = FakeBlueyPlatform();

  @override
  late final PlatformScanning scanning;

  @override
  void hear(ScanResult result) => fake.simulateScanResult(
    platform.PlatformDevice(
      id: result.device.address.value,
      name: result.device.name,
      rssi: result.rssi,
      serviceUuids: const [],
      manufacturerDataCompanyId: null,
      manufacturerData: null,
    ),
  );

  @override
  void refuse(ScanRefusalReason reason) => fake.simulateScanRefusal(
    platform.PlatformScanFailureReason.values.byName(reason.name),
  );

  @override
  void failNextStop() =>
      fake.enqueueFault(FakeOp.stopScan, PlatformException(code: 'E1'));

  @override
  void holdNextStop() => fake.holdNextStopScan();

  @override
  void releaseStop() => fake.releaseHeldStopScan();

  @override
  void outage(RadioOutage outage) => fake.setBluetoothState(switch (outage) {
    RadioOutage.off => platform.BluetoothState.off,
    RadioOutage.unauthorized => platform.BluetoothState.unauthorized,
    RadioOutage.unsupported => platform.BluetoothState.unsupported,
    RadioOutage.unknown => platform.BluetoothState.unknown,
  });

  @override
  ScanCoverage? get scanningFor {
    if (!fake.isScanning) return null;
    final config = fake.lastScanConfig!;
    return ScanCoverage(
      filter: ScanFilter.of(config.serviceUuids.map(UUID.new)),
      mode: switch (config.scanMode) {
        platform.PlatformScanMode.lowPower => ScanMode.lowPower,
        platform.PlatformScanMode.balanced => ScanMode.balanced,
        platform.PlatformScanMode.lowLatency => ScanMode.lowLatency,
        null => null,
      },
    );
  }
}
