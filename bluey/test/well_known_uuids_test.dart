import 'package:flutter_test/flutter_test.dart';
import 'package:bluey/bluey.dart';

void main() {
  group('Services', () {
    test('has standard service UUIDs', () {
      expect(Services.genericAccess, equals(UUID.short(0x1800)));
      expect(Services.genericAttribute, equals(UUID.short(0x1801)));
      expect(Services.deviceInformation, equals(UUID.short(0x180A)));
      expect(Services.heartRate, equals(UUID.short(0x180D)));
      expect(Services.battery, equals(UUID.short(0x180F)));
    });

    test('has health-related service UUIDs', () {
      expect(Services.healthThermometer, equals(UUID.short(0x1809)));
      expect(Services.bloodPressure, equals(UUID.short(0x1810)));
    });

    test('has fitness service UUIDs', () {
      expect(Services.runningSpeedAndCadence, equals(UUID.short(0x1814)));
      expect(Services.cyclingSpeedAndCadence, equals(UUID.short(0x1816)));
      expect(Services.cyclingPower, equals(UUID.short(0x1818)));
      expect(Services.fitnessMachine, equals(UUID.short(0x1826)));
    });

    test('has alert service UUIDs', () {
      expect(Services.immediateAlert, equals(UUID.short(0x1802)));
      expect(Services.linkLoss, equals(UUID.short(0x1803)));
      expect(Services.txPower, equals(UUID.short(0x1804)));
    });
  });

  group('Characteristics', () {
    test('has device information characteristics', () {
      expect(Characteristics.deviceName, equals(UUID.short(0x2A00)));
      expect(Characteristics.appearance, equals(UUID.short(0x2A01)));
      expect(Characteristics.modelNumber, equals(UUID.short(0x2A24)));
      expect(Characteristics.serialNumber, equals(UUID.short(0x2A25)));
      expect(Characteristics.firmwareRevision, equals(UUID.short(0x2A26)));
      expect(Characteristics.hardwareRevision, equals(UUID.short(0x2A27)));
      expect(Characteristics.softwareRevision, equals(UUID.short(0x2A28)));
      expect(Characteristics.manufacturerName, equals(UUID.short(0x2A29)));
    });

    test('has battery characteristic', () {
      expect(Characteristics.batteryLevel, equals(UUID.short(0x2A19)));
    });

    test('has heart rate characteristics', () {
      expect(Characteristics.heartRateMeasurement, equals(UUID.short(0x2A37)));
      expect(Characteristics.bodySensorLocation, equals(UUID.short(0x2A38)));
    });
  });

  group('Descriptors', () {
    test('has standard descriptor UUIDs', () {
      expect(
        Descriptors.characteristicExtendedProperties,
        equals(UUID.short(0x2900)),
      );
      expect(
        Descriptors.characteristicUserDescription,
        equals(UUID.short(0x2901)),
      );
      expect(
        Descriptors.clientCharacteristicConfiguration,
        equals(UUID.short(0x2902)),
      );
      expect(
        Descriptors.serverCharacteristicConfiguration,
        equals(UUID.short(0x2903)),
      );
      expect(
        Descriptors.characteristicPresentationFormat,
        equals(UUID.short(0x2904)),
      );
    });
  });
}
