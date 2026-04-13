import 'dart:async';

import 'package:bluey/bluey.dart';
import 'package:bluey/src/scanner.dart';
import 'package:bluey/src/well_known_uuids.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_platform.dart';

void main() {
  late FakeBlueyPlatform fakePlatform;
  late Bluey bluey;

  setUp(() {
    fakePlatform = FakeBlueyPlatform();
    platform.BlueyPlatform.instance = fakePlatform;
    bluey = Bluey();
  });

  tearDown(() async {
    await bluey.dispose();
    await fakePlatform.dispose();
  });

  group('Scanner', () {
    test('scanner() returns a Scanner', () {
      final scanner = bluey.scanner();
      expect(scanner, isA<Scanner>());
      scanner.dispose();
    });

    test('isScanning is false initially', () {
      final scanner = bluey.scanner();
      expect(scanner.isScanning, isFalse);
      scanner.dispose();
    });

    test('scan emits ScanResults', () async {
      fakePlatform.simulatePeripheral(
        id: 'AA:BB:CC:DD:EE:FF',
        name: 'Test Device',
        rssi: -60,
        serviceUuids: ['0000180d-0000-1000-8000-00805f9b34fb'],
        manufacturerDataCompanyId: 0x004C,
        manufacturerData: [1, 2, 3],
      );

      final scanner = bluey.scanner();

      final results = <ScanResult>[];
      final subscription = scanner.scan().listen(results.add);

      await Future.delayed(Duration(milliseconds: 50));
      await subscription.cancel();
      scanner.dispose();

      expect(results, hasLength(1));
      expect(results.first.device.name, equals('Test Device'));
      expect(results.first.rssi, equals(-60));
    });

    test('isScanning is true during scan', () async {
      fakePlatform.simulatePeripheral(
        id: 'AA:BB:CC:DD:EE:FF',
        name: 'Test Device',
      );

      final scanner = bluey.scanner();

      expect(scanner.isScanning, isFalse);

      final subscription = scanner.scan().listen((_) {});

      // isScanning should be true after scan() is called
      expect(scanner.isScanning, isTrue);

      await subscription.cancel();
      scanner.dispose();
    });

    test('stop is idempotent', () async {
      final scanner = bluey.scanner();

      // Stopping when not scanning should not throw
      await scanner.stop();
      await scanner.stop();

      scanner.dispose();
    });

    test('stop sets isScanning to false', () async {
      fakePlatform.simulatePeripheral(
        id: 'AA:BB:CC:DD:EE:FF',
        name: 'Test Device',
      );

      final scanner = bluey.scanner();

      final subscription = scanner.scan().listen((_) {});
      expect(scanner.isScanning, isTrue);

      await scanner.stop();
      expect(scanner.isScanning, isFalse);

      await subscription.cancel();
      scanner.dispose();
    });

    test('scan with service filter', () async {
      fakePlatform.simulatePeripheral(
        id: 'AA:BB:CC:DD:EE:01',
        name: 'Heart Rate Monitor',
        serviceUuids: ['0000180d-0000-1000-8000-00805f9b34fb'],
      );
      fakePlatform.simulatePeripheral(
        id: 'AA:BB:CC:DD:EE:02',
        name: 'Battery Device',
        serviceUuids: ['0000180f-0000-1000-8000-00805f9b34fb'],
      );

      final scanner = bluey.scanner();

      final results = <ScanResult>[];
      final subscription = scanner
          .scan(services: [Services.heartRate])
          .listen(results.add);

      await Future.delayed(Duration(milliseconds: 50));
      await subscription.cancel();
      scanner.dispose();

      expect(results, hasLength(1));
      expect(results.first.device.name, equals('Heart Rate Monitor'));
    });

    test('scan with timeout', () async {
      fakePlatform.simulatePeripheral(
        id: 'AA:BB:CC:DD:EE:FF',
        name: 'Test Device',
      );

      final scanner = bluey.scanner();

      // Verify scan accepts timeout parameter without error
      final results = <ScanResult>[];
      final subscription = scanner
          .scan(timeout: Duration(seconds: 10))
          .listen(results.add);

      await Future.delayed(Duration(milliseconds: 50));
      await subscription.cancel();
      scanner.dispose();

      expect(results, hasLength(1));
    });

    test('dispose cleans up', () {
      final scanner = bluey.scanner();

      scanner.dispose();
      expect(scanner.isScanning, isFalse);
    });

    test('dispose sets isScanning to false when scanning', () async {
      fakePlatform.simulatePeripheral(
        id: 'AA:BB:CC:DD:EE:FF',
        name: 'Test Device',
      );

      final scanner = bluey.scanner();

      final subscription = scanner.scan().listen((_) {});
      expect(scanner.isScanning, isTrue);

      scanner.dispose();
      expect(scanner.isScanning, isFalse);

      await subscription.cancel();
    });

    test('converts manufacturer data correctly', () async {
      fakePlatform.simulatePeripheral(
        id: 'AA:BB:CC:DD:EE:FF',
        name: null,
        rssi: -50,
        manufacturerDataCompanyId: 0x004C,
        manufacturerData: [10, 20, 30],
      );

      final scanner = bluey.scanner();

      final results = <ScanResult>[];
      final subscription = scanner.scan().listen(results.add);

      await Future.delayed(Duration(milliseconds: 50));
      await subscription.cancel();
      scanner.dispose();

      final manufacturerData = results.first.advertisement.manufacturerData;
      expect(manufacturerData, isNotNull);
      expect(manufacturerData!.companyId, equals(0x004C));
      expect(manufacturerData.data, equals([10, 20, 30]));
    });

    test('converts service UUIDs correctly', () async {
      fakePlatform.simulatePeripheral(
        id: 'AA:BB:CC:DD:EE:FF',
        name: null,
        rssi: -50,
        serviceUuids: [
          '0000180d-0000-1000-8000-00805f9b34fb',
          '0000180f-0000-1000-8000-00805f9b34fb',
        ],
      );

      final scanner = bluey.scanner();

      final results = <ScanResult>[];
      final subscription = scanner.scan().listen(results.add);

      await Future.delayed(Duration(milliseconds: 50));
      await subscription.cancel();
      scanner.dispose();

      final serviceUuids = results.first.advertisement.serviceUuids;
      expect(serviceUuids, hasLength(2));
      expect(serviceUuids[0], equals(Services.heartRate));
      expect(serviceUuids[1], equals(Services.battery));
    });

    test('emits ScanStartedEvent on scan', () async {
      fakePlatform.simulatePeripheral(
        id: 'AA:BB:CC:DD:EE:FF',
        name: 'Test Device',
      );

      final events = <BlueyEvent>[];
      final eventSub = bluey.events.listen(events.add);

      final scanner = bluey.scanner();

      final subscription = scanner.scan().listen((_) {});
      await Future.delayed(Duration(milliseconds: 50));
      await subscription.cancel();
      scanner.dispose();

      await eventSub.cancel();

      expect(events.whereType<ScanStartedEvent>(), hasLength(1));
    });

    test('emits DeviceDiscoveredEvent for each result', () async {
      fakePlatform.simulatePeripheral(
        id: 'AA:BB:CC:DD:EE:01',
        name: 'Device 1',
      );
      fakePlatform.simulatePeripheral(
        id: 'AA:BB:CC:DD:EE:02',
        name: 'Device 2',
      );

      final events = <BlueyEvent>[];
      final eventSub = bluey.events.listen(events.add);

      final scanner = bluey.scanner();

      final subscription = scanner.scan().listen((_) {});
      await Future.delayed(Duration(milliseconds: 50));
      await subscription.cancel();
      scanner.dispose();

      await eventSub.cancel();

      expect(events.whereType<DeviceDiscoveredEvent>(), hasLength(2));
    });

    test('emits ScanStoppedEvent on stop', () async {
      final events = <BlueyEvent>[];
      final eventSub = bluey.events.listen(events.add);

      final scanner = bluey.scanner();

      final subscription = scanner.scan().listen((_) {});
      await scanner.stop();
      await subscription.cancel();
      scanner.dispose();

      await eventSub.cancel();

      expect(events.whereType<ScanStoppedEvent>(), hasLength(1));
    });
  });
}
