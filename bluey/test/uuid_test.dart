import 'package:flutter_test/flutter_test.dart';
import 'package:bluey/src/uuid.dart';
import 'package:bluey/src/well_known_uuids.dart';

void main() {
  group('UUID', () {
    group('Construction', () {
      test('creates from full 128-bit UUID string', () {
        final uuid = UUID('0000180d-0000-1000-8000-00805f9b34fb');

        expect(uuid, isNotNull);
        expect(uuid.toString(), '0000180d-0000-1000-8000-00805f9b34fb');
      });

      test('creates from short 16-bit value', () {
        final uuid = UUID.short(0x180D);

        expect(uuid, isNotNull);
        expect(uuid.toString(), '0000180d-0000-1000-8000-00805f9b34fb');
      });

      test('normalizes uppercase to lowercase', () {
        final uuid = UUID('0000180D-0000-1000-8000-00805F9B34FB');

        expect(uuid.toString(), '0000180d-0000-1000-8000-00805f9b34fb');
      });

      test('accepts UUID without hyphens', () {
        final uuid = UUID('0000180d00001000800000805f9b34fb');

        expect(uuid.toString(), '0000180d-0000-1000-8000-00805f9b34fb');
      });

      test('throws on invalid UUID string', () {
        expect(() => UUID('invalid'), throwsArgumentError);
        expect(() => UUID(''), throwsArgumentError);
        expect(
          () => UUID('180d'),
          throwsArgumentError,
        ); // 4 chars - use UUID.short() instead
        expect(
          () => UUID('12345678'),
          throwsArgumentError,
        ); // 8 chars - not full UUID
      });

      test('throws on invalid short value', () {
        expect(() => UUID.short(-1), throwsArgumentError);
        expect(() => UUID.short(0x10000), throwsArgumentError);
      });
    });

    group('Equality', () {
      test('equal UUIDs have same hashCode', () {
        final uuid1 = UUID('0000180d-0000-1000-8000-00805f9b34fb');
        final uuid2 = UUID('0000180d-0000-1000-8000-00805f9b34fb');

        expect(uuid1, equals(uuid2));
        expect(uuid1.hashCode, equals(uuid2.hashCode));
      });

      test('different UUIDs are not equal', () {
        final uuid1 = UUID.short(0x180D);
        final uuid2 = UUID.short(0x180F);

        expect(uuid1, isNot(equals(uuid2)));
      });

      test('equality ignores case', () {
        final uuid1 = UUID('0000180d-0000-1000-8000-00805f9b34fb');
        final uuid2 = UUID('0000180D-0000-1000-8000-00805F9B34FB');

        expect(uuid1, equals(uuid2));
      });
    });

    group('Short form detection', () {
      test('recognizes Bluetooth SIG short UUID', () {
        final uuid = UUID.short(0x180D);

        expect(uuid.isShort, isTrue);
        expect(uuid.shortString, '180d');
      });

      test('recognizes custom UUID as not short', () {
        final uuid = UUID('12345678-1234-1234-1234-123456789abc');

        expect(uuid.isShort, isFalse);
        expect(uuid.shortString, '12345678-1234-1234-1234-123456789abc');
      });

      test('Bluetooth base UUID pattern', () {
        // UUIDs matching 0000xxxx-0000-1000-8000-00805f9b34fb are "short"
        final shortUuid = UUID('00001234-0000-1000-8000-00805f9b34fb');
        final notShort = UUID('00001234-0000-2000-8000-00805f9b34fb');

        expect(shortUuid.isShort, isTrue);
        expect(notShort.isShort, isFalse);
      });
    });

    group('Well-known UUIDs (via Services class)', () {
      test('heart rate service', () {
        expect(Services.heartRate, equals(UUID.short(0x180D)));
      });

      test('battery service', () {
        expect(Services.battery, equals(UUID.short(0x180F)));
      });

      test('device information service', () {
        expect(Services.deviceInformation, equals(UUID.short(0x180A)));
      });
    });
  });
}
