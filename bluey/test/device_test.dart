import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:bluey/src/device.dart';
import 'package:bluey/src/uuid.dart';
import 'package:bluey/src/well_known_uuids.dart';

void main() {
  group('Advertisement', () {
    group('Construction', () {
      test('creates with all fields', () {
        final advertisement = Advertisement(
          serviceUuids: [Services.heartRate, Services.battery],
          serviceData: {
            Services.heartRate: Uint8List.fromList([1, 2, 3]),
          },
          manufacturerData: ManufacturerData(
            0x004C,
            Uint8List.fromList([10, 20]),
          ),
          txPowerLevel: -10,
          isConnectable: true,
        );

        expect(advertisement.serviceUuids, hasLength(2));
        expect(advertisement.serviceData, hasLength(1));
        expect(advertisement.manufacturerData, isNotNull);
        expect(advertisement.txPowerLevel, equals(-10));
        expect(advertisement.isConnectable, isTrue);
      });

      test('creates with minimal fields', () {
        final advertisement = Advertisement(
          serviceUuids: [],
          serviceData: {},
          isConnectable: true,
        );

        expect(advertisement.serviceUuids, isEmpty);
        expect(advertisement.serviceData, isEmpty);
        expect(advertisement.manufacturerData, isNull);
        expect(advertisement.txPowerLevel, isNull);
        expect(advertisement.isConnectable, isTrue);
      });

      test('creates empty advertisement', () {
        final advertisement = Advertisement.empty();

        expect(advertisement.serviceUuids, isEmpty);
        expect(advertisement.serviceData, isEmpty);
        expect(advertisement.manufacturerData, isNull);
        expect(advertisement.txPowerLevel, isNull);
        expect(advertisement.isConnectable, isFalse);
      });
    });

    group('Immutability', () {
      test('serviceUuids list is unmodifiable', () {
        final advertisement = Advertisement(
          serviceUuids: [Services.heartRate],
          serviceData: {},
          isConnectable: true,
        );

        expect(
          () => advertisement.serviceUuids.add(Services.battery),
          throwsUnsupportedError,
        );
      });

      test('serviceData map is unmodifiable', () {
        final advertisement = Advertisement(
          serviceUuids: [],
          serviceData: {
            Services.heartRate: Uint8List.fromList([1, 2]),
          },
          isConnectable: true,
        );

        expect(
          () =>
              advertisement.serviceData[Services.battery] = Uint8List.fromList([
                3,
                4,
              ]),
          throwsUnsupportedError,
        );
      });
    });

    group('Equality', () {
      test('equal advertisements have same hashCode', () {
        final ad1 = Advertisement(
          serviceUuids: [Services.heartRate],
          serviceData: {},
          isConnectable: true,
        );

        final ad2 = Advertisement(
          serviceUuids: [Services.heartRate],
          serviceData: {},
          isConnectable: true,
        );

        expect(ad1, equals(ad2));
        expect(ad1.hashCode, equals(ad2.hashCode));
      });

      test('different advertisements are not equal', () {
        final ad1 = Advertisement(
          serviceUuids: [Services.heartRate],
          serviceData: {},
          isConnectable: true,
        );

        final ad2 = Advertisement(
          serviceUuids: [Services.battery],
          serviceData: {},
          isConnectable: true,
        );

        expect(ad1, isNot(equals(ad2)));
      });
    });
  });

  group('ManufacturerData', () {
    test('creates with company ID and data', () {
      final data = ManufacturerData(0x004C, Uint8List.fromList([1, 2, 3]));

      expect(data.companyId, equals(0x004C));
      expect(data.data, equals(Uint8List.fromList([1, 2, 3])));
    });

    test('has well-known company IDs', () {
      expect(ManufacturerData.apple, equals(0x004C));
      expect(ManufacturerData.google, equals(0x00E0));
      expect(ManufacturerData.microsoft, equals(0x0006));
    });

    test('equality based on company ID and data', () {
      final data1 = ManufacturerData(0x004C, Uint8List.fromList([1, 2]));
      final data2 = ManufacturerData(0x004C, Uint8List.fromList([1, 2]));

      expect(data1, equals(data2));
      expect(data1.hashCode, equals(data2.hashCode));
    });

    test('different data is not equal', () {
      final data1 = ManufacturerData(0x004C, Uint8List.fromList([1, 2]));
      final data2 = ManufacturerData(0x004C, Uint8List.fromList([3, 4]));

      expect(data1, isNot(equals(data2)));
    });
  });

  group('Device', () {
    final testUuid = UUID.short(0x1234);
    final testAdvertisement = Advertisement(
      serviceUuids: [Services.heartRate],
      serviceData: {},
      isConnectable: true,
    );

    group('Construction', () {
      test('creates with all fields', () {
        final device = Device(
          id: testUuid,
          name: 'Heart Monitor',
          rssi: -60,
          advertisement: testAdvertisement,
        );

        expect(device.id, equals(testUuid));
        expect(device.name, equals('Heart Monitor'));
        expect(device.rssi, equals(-60));
        expect(device.advertisement, equals(testAdvertisement));
        expect(device.lastSeen, isNotNull);
      });

      test('address defaults to id.toString() when not provided', () {
        final device = Device(
          id: testUuid,
          rssi: -60,
          advertisement: testAdvertisement,
        );

        expect(device.address, equals(testUuid.toString()));
      });

      test('address can be set explicitly (e.g., MAC address on Android)', () {
        const macAddress = 'AA:BB:CC:DD:EE:FF';
        final device = Device(
          id: testUuid,
          address: macAddress,
          rssi: -60,
          advertisement: testAdvertisement,
        );

        expect(device.address, equals(macAddress));
        expect(device.id, equals(testUuid)); // id is still the UUID
      });

      test('creates without name', () {
        final device = Device(
          id: testUuid,
          rssi: -60,
          advertisement: testAdvertisement,
        );

        expect(device.name, isNull);
      });

      test('lastSeen defaults to now', () {
        final before = DateTime.now();
        final device = Device(
          id: testUuid,
          rssi: -60,
          advertisement: testAdvertisement,
        );
        final after = DateTime.now();

        expect(
          device.lastSeen.isAfter(before.subtract(Duration(seconds: 1))),
          isTrue,
        );
        expect(
          device.lastSeen.isBefore(after.add(Duration(seconds: 1))),
          isTrue,
        );
      });

      test('accepts custom lastSeen', () {
        final customTime = DateTime(2024, 1, 1, 12, 0, 0);
        final device = Device(
          id: testUuid,
          rssi: -60,
          advertisement: testAdvertisement,
          lastSeen: customTime,
        );

        expect(device.lastSeen, equals(customTime));
      });
    });

    group('Equality', () {
      test('equality based on ID only', () {
        final device1 = Device(
          id: testUuid,
          name: 'Device 1',
          rssi: -50,
          advertisement: testAdvertisement,
        );

        final device2 = Device(
          id: testUuid,
          name: 'Device 2',
          rssi: -70,
          advertisement: Advertisement.empty(),
        );

        // Same ID = equal devices (entity equality)
        expect(device1, equals(device2));
        expect(device1.hashCode, equals(device2.hashCode));
      });

      test('different IDs are not equal', () {
        final device1 = Device(
          id: UUID.short(0x1234),
          rssi: -60,
          advertisement: testAdvertisement,
        );

        final device2 = Device(
          id: UUID.short(0x5678),
          rssi: -60,
          advertisement: testAdvertisement,
        );

        expect(device1, isNot(equals(device2)));
      });
    });

    group('Immutability', () {
      test('device is immutable value', () {
        final device = Device(
          id: testUuid,
          name: 'Test',
          rssi: -60,
          advertisement: testAdvertisement,
        );

        // All fields are final - this is enforced at compile time
        expect(device.id, equals(testUuid));
      });
    });

    group('CopyWith', () {
      test('creates copy with updated fields', () {
        final original = Device(
          id: testUuid,
          name: 'Original',
          rssi: -60,
          advertisement: testAdvertisement,
        );

        final updated = original.copyWith(name: 'Updated', rssi: -50);

        expect(updated.id, equals(original.id));
        expect(updated.name, equals('Updated'));
        expect(updated.rssi, equals(-50));
        expect(updated.advertisement, equals(original.advertisement));
      });

      test('copyWith without arguments returns equal device', () {
        final original = Device(
          id: testUuid,
          name: 'Test',
          rssi: -60,
          advertisement: testAdvertisement,
        );

        final copy = original.copyWith();

        expect(copy.id, equals(original.id));
        expect(copy.name, equals(original.name));
        expect(copy.rssi, equals(original.rssi));
      });

      test('copyWith can clear name', () {
        final original = Device(
          id: testUuid,
          name: 'Test',
          rssi: -60,
          advertisement: testAdvertisement,
        );

        final updated = original.copyWith(name: null);

        expect(updated.name, isNull);
      });
    });
  });
}
