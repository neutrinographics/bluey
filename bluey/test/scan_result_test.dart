import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:bluey/bluey.dart';

void main() {
  group('ScanResult', () {
    final testUuid = UUID.short(0x1234);
    final testAdvertisement = Advertisement(
      serviceUuids: [Services.heartRate],
      serviceData: {},
      isConnectable: true,
    );
    final testDevice = Device(id: testUuid, name: 'Test Device');

    group('Construction', () {
      test('creates with required fields', () {
        final result = ScanResult(
          device: testDevice,
          rssi: -60,
          advertisement: testAdvertisement,
        );

        expect(result.device, equals(testDevice));
        expect(result.rssi, equals(-60));
        expect(result.advertisement, equals(testAdvertisement));
        expect(result.lastSeen, isNotNull);
      });

      test('lastSeen defaults to now', () {
        final before = DateTime.now();
        final result = ScanResult(
          device: testDevice,
          rssi: -60,
          advertisement: testAdvertisement,
        );
        final after = DateTime.now();

        expect(
          result.lastSeen.isAfter(before.subtract(Duration(seconds: 1))),
          isTrue,
        );
        expect(
          result.lastSeen.isBefore(after.add(Duration(seconds: 1))),
          isTrue,
        );
      });

      test('accepts custom lastSeen', () {
        final customTime = DateTime(2024, 1, 1, 12, 0, 0);
        final result = ScanResult(
          device: testDevice,
          rssi: -60,
          advertisement: testAdvertisement,
          lastSeen: customTime,
        );

        expect(result.lastSeen, equals(customTime));
      });
    });

    group('Equality', () {
      test('same fields are equal', () {
        final time = DateTime(2024, 1, 1);
        final result1 = ScanResult(
          device: testDevice,
          rssi: -60,
          advertisement: testAdvertisement,
          lastSeen: time,
        );
        final result2 = ScanResult(
          device: testDevice,
          rssi: -60,
          advertisement: testAdvertisement,
          lastSeen: time,
        );

        expect(result1, equals(result2));
        expect(result1.hashCode, equals(result2.hashCode));
      });

      test('different rssi are not equal', () {
        final time = DateTime(2024, 1, 1);
        final result1 = ScanResult(
          device: testDevice,
          rssi: -60,
          advertisement: testAdvertisement,
          lastSeen: time,
        );
        final result2 = ScanResult(
          device: testDevice,
          rssi: -70,
          advertisement: testAdvertisement,
          lastSeen: time,
        );

        expect(result1, isNot(equals(result2)));
      });

      test('different advertisement are not equal', () {
        final time = DateTime(2024, 1, 1);
        final result1 = ScanResult(
          device: testDevice,
          rssi: -60,
          advertisement: testAdvertisement,
          lastSeen: time,
        );
        final result2 = ScanResult(
          device: testDevice,
          rssi: -60,
          advertisement: Advertisement.empty(),
          lastSeen: time,
        );

        expect(result1, isNot(equals(result2)));
      });

      test('different device are not equal', () {
        final time = DateTime(2024, 1, 1);
        final otherDevice = Device(id: UUID.short(0x5678), name: 'Other');
        final result1 = ScanResult(
          device: testDevice,
          rssi: -60,
          advertisement: testAdvertisement,
          lastSeen: time,
        );
        final result2 = ScanResult(
          device: otherDevice,
          rssi: -60,
          advertisement: testAdvertisement,
          lastSeen: time,
        );

        expect(result1, isNot(equals(result2)));
      });
    });

    group('isBlueyServer', () {
      test('returns true when Bluey manufacturer data is present', () {
        final result = ScanResult(
          device: testDevice,
          rssi: -50,
          advertisement: Advertisement(
            serviceUuids: [],
            serviceData: {},
            manufacturerData: ManufacturerData(
              0xFFFF,
              Uint8List.fromList([0xB1, 0xE7]),
            ),
            isConnectable: true,
          ),
        );
        expect(result.isBlueyServer, isTrue);
      });

      test('returns false without Bluey manufacturer data', () {
        final result = ScanResult(
          device: testDevice,
          rssi: -50,
          advertisement: Advertisement(
            serviceUuids: [],
            serviceData: {},
            isConnectable: true,
          ),
        );
        expect(result.isBlueyServer, isFalse);
      });

      test('returns false with different company ID', () {
        final result = ScanResult(
          device: testDevice,
          rssi: -50,
          advertisement: Advertisement(
            serviceUuids: [],
            serviceData: {},
            manufacturerData: ManufacturerData(
              0x004C,
              Uint8List.fromList([0xB1, 0xE7]),
            ),
            isConnectable: true,
          ),
        );
        expect(result.isBlueyServer, isFalse);
      });

      test('returns false with wrong marker bytes', () {
        final result = ScanResult(
          device: testDevice,
          rssi: -50,
          advertisement: Advertisement(
            serviceUuids: [],
            serviceData: {},
            manufacturerData: ManufacturerData(
              0xFFFF,
              Uint8List.fromList([0x00, 0x00]),
            ),
            isConnectable: true,
          ),
        );
        expect(result.isBlueyServer, isFalse);
      });
    });

    group('toString', () {
      test('includes key fields', () {
        final result = ScanResult(
          device: testDevice,
          rssi: -60,
          advertisement: testAdvertisement,
        );

        final str = result.toString();
        expect(str, contains('ScanResult'));
        expect(str, contains('-60 dBm'));
        expect(str, contains('advertisement'));
      });
    });
  });
}
