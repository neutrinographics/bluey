import 'package:bluey/bluey.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CharacteristicProperties', () {
    group('Construction', () {
      test('creates with all properties false by default', () {
        const props = CharacteristicProperties();

        expect(props.canRead, isFalse);
        expect(props.canWrite, isFalse);
        expect(props.canWriteWithoutResponse, isFalse);
        expect(props.canNotify, isFalse);
        expect(props.canIndicate, isFalse);
      });

      test('creates with specified properties', () {
        const props = CharacteristicProperties(
          canRead: true,
          canWrite: true,
          canWriteWithoutResponse: false,
          canNotify: true,
          canIndicate: false,
        );

        expect(props.canRead, isTrue);
        expect(props.canWrite, isTrue);
        expect(props.canWriteWithoutResponse, isFalse);
        expect(props.canNotify, isTrue);
        expect(props.canIndicate, isFalse);
      });
    });

    group('fromFlags', () {
      test('parses read flag (0x02)', () {
        final props = CharacteristicProperties.fromFlags(0x02);
        expect(props.canRead, isTrue);
        expect(props.canWrite, isFalse);
      });

      test('parses write without response flag (0x04)', () {
        final props = CharacteristicProperties.fromFlags(0x04);
        expect(props.canWriteWithoutResponse, isTrue);
        expect(props.canWrite, isFalse);
      });

      test('parses write flag (0x08)', () {
        final props = CharacteristicProperties.fromFlags(0x08);
        expect(props.canWrite, isTrue);
        expect(props.canWriteWithoutResponse, isFalse);
      });

      test('parses notify flag (0x10)', () {
        final props = CharacteristicProperties.fromFlags(0x10);
        expect(props.canNotify, isTrue);
        expect(props.canIndicate, isFalse);
      });

      test('parses indicate flag (0x20)', () {
        final props = CharacteristicProperties.fromFlags(0x20);
        expect(props.canIndicate, isTrue);
        expect(props.canNotify, isFalse);
      });

      test('parses combined flags', () {
        // read + write + notify = 0x02 + 0x08 + 0x10 = 0x1A
        final props = CharacteristicProperties.fromFlags(0x1A);
        expect(props.canRead, isTrue);
        expect(props.canWrite, isTrue);
        expect(props.canWriteWithoutResponse, isFalse);
        expect(props.canNotify, isTrue);
        expect(props.canIndicate, isFalse);
      });

      test('parses all flags', () {
        // read + writeNoResp + write + notify + indicate = 0x3E
        final props = CharacteristicProperties.fromFlags(0x3E);
        expect(props.canRead, isTrue);
        expect(props.canWrite, isTrue);
        expect(props.canWriteWithoutResponse, isTrue);
        expect(props.canNotify, isTrue);
        expect(props.canIndicate, isTrue);
      });

      test('ignores unknown flags', () {
        // Unknown high bits should not cause issues
        final props = CharacteristicProperties.fromFlags(0xFF);
        expect(props.canRead, isTrue);
        expect(props.canWrite, isTrue);
        expect(props.canWriteWithoutResponse, isTrue);
        expect(props.canNotify, isTrue);
        expect(props.canIndicate, isTrue);
      });
    });

    group('Equality', () {
      test('equal properties have same hashCode', () {
        const props1 = CharacteristicProperties(canRead: true, canWrite: true);
        const props2 = CharacteristicProperties(canRead: true, canWrite: true);

        expect(props1, equals(props2));
        expect(props1.hashCode, equals(props2.hashCode));
      });

      test('different properties are not equal', () {
        const props1 = CharacteristicProperties(canRead: true);
        const props2 = CharacteristicProperties(canWrite: true);

        expect(props1, isNot(equals(props2)));
      });
    });

    group('Convenience getters', () {
      test('canWriteAny returns true if any write is supported', () {
        const writeOnly = CharacteristicProperties(canWrite: true);
        const writeNoRespOnly = CharacteristicProperties(
          canWriteWithoutResponse: true,
        );
        const both = CharacteristicProperties(
          canWrite: true,
          canWriteWithoutResponse: true,
        );
        const neither = CharacteristicProperties(canRead: true);

        expect(writeOnly.canWriteAny, isTrue);
        expect(writeNoRespOnly.canWriteAny, isTrue);
        expect(both.canWriteAny, isTrue);
        expect(neither.canWriteAny, isFalse);
      });

      test('canSubscribe returns true if notify or indicate is supported', () {
        const notifyOnly = CharacteristicProperties(canNotify: true);
        const indicateOnly = CharacteristicProperties(canIndicate: true);
        const both = CharacteristicProperties(
          canNotify: true,
          canIndicate: true,
        );
        const neither = CharacteristicProperties(canRead: true);

        expect(notifyOnly.canSubscribe, isTrue);
        expect(indicateOnly.canSubscribe, isTrue);
        expect(both.canSubscribe, isTrue);
        expect(neither.canSubscribe, isFalse);
      });
    });

    group('toString', () {
      test('includes all properties', () {
        const props = CharacteristicProperties(
          canRead: true,
          canWrite: true,
          canNotify: true,
        );

        final str = props.toString();
        expect(str, contains('canRead: true'));
        expect(str, contains('canWrite: true'));
        expect(str, contains('canNotify: true'));
      });
    });
  });
}
