import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:bluey/src/discovery/device.dart';
import 'package:bluey/src/discovery/advertisement.dart';
import 'package:bluey/src/shared/manufacturer_data.dart';
import 'package:bluey/src/shared/uuid.dart';
import 'package:bluey/src/gatt_client/well_known_uuids.dart';

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

    group('Construction', () {
      test('creates with all fields', () {
        final device = Device(id: testUuid, name: 'Heart Monitor');

        expect(device.id, equals(testUuid));
        expect(device.name, equals('Heart Monitor'));
      });

      test('address defaults to id.toString() when not provided', () {
        final device = Device(id: testUuid);

        expect(device.address, equals(testUuid.toString()));
      });

      test('address can be set explicitly (e.g., MAC address on Android)', () {
        const macAddress = 'AA:BB:CC:DD:EE:FF';
        final device = Device(id: testUuid, address: macAddress);

        expect(device.address, equals(macAddress));
        expect(device.id, equals(testUuid)); // id is still the UUID
      });

      test('creates without name', () {
        final device = Device(id: testUuid);

        expect(device.name, isNull);
      });
    });

    group('Equality', () {
      test('equality based on ID only', () {
        final device1 = Device(id: testUuid, name: 'Device 1');

        final device2 = Device(id: testUuid, name: 'Device 2');

        // Same ID = equal devices (entity equality)
        expect(device1, equals(device2));
        expect(device1.hashCode, equals(device2.hashCode));
      });

      test('different IDs are not equal', () {
        final device1 = Device(id: UUID.short(0x1234));

        final device2 = Device(id: UUID.short(0x5678));

        expect(device1, isNot(equals(device2)));
      });
    });

    group('Immutability', () {
      test('device is immutable value', () {
        final device = Device(id: testUuid, name: 'Test');

        // All fields are final - this is enforced at compile time
        expect(device.id, equals(testUuid));
      });
    });

    group('CopyWith', () {
      test('creates copy with updated name', () {
        final original = Device(id: testUuid, name: 'Original');

        final updated = original.copyWith(name: 'Updated');

        expect(updated.id, equals(original.id));
        expect(updated.name, equals('Updated'));
      });

      test('copyWith without arguments returns equal device', () {
        final original = Device(id: testUuid, name: 'Test');

        final copy = original.copyWith();

        expect(copy.id, equals(original.id));
        expect(copy.name, equals(original.name));
      });

      test('copyWith can clear name', () {
        final original = Device(id: testUuid, name: 'Test');

        final updated = original.copyWith(name: null);

        expect(updated.name, isNull);
      });
    });
  });
}
