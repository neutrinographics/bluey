import 'package:bluey/bluey.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WritePayloadLimit', () {
    test('constructs with positive value', () {
      final limit = WritePayloadLimit(182);
      expect(limit.value, equals(182));
    });

    test('throws ArgumentError on zero', () {
      expect(() => WritePayloadLimit(0), throwsArgumentError);
    });

    test('throws ArgumentError on negative', () {
      expect(() => WritePayloadLimit(-1), throwsArgumentError);
    });

    test('fromPlatform bypasses validation', () {
      // Platform is authoritative; the factory accepts any int the
      // platform returns without throwing.
      expect(WritePayloadLimit.fromPlatform(0).value, equals(0));
      expect(WritePayloadLimit.fromPlatform(-1).value, equals(-1));
    });

    test('equality by value', () {
      expect(WritePayloadLimit(100), equals(WritePayloadLimit(100)));
      expect(WritePayloadLimit(100), isNot(equals(WritePayloadLimit(101))));
    });

    test('hashCode consistent with equality', () {
      expect(
        WritePayloadLimit(100).hashCode,
        equals(WritePayloadLimit(100).hashCode),
      );
    });

    test('toString includes the value', () {
      expect(WritePayloadLimit(182).toString(), contains('182'));
    });
  });

  group('WritePayloadLimit.fromPlatform clamps to the 512-octet attribute cap (I343)', () {
    test('clamps a value above 512 down to 512', () {
      // iOS over-reports maximumWriteValueLength(.withoutResponse) as MTU-3
      // (514 @ MTU 517); the BLE spec caps an attribute value at 512 octets
      // and Android silently truncates the overflow. See I343.
      expect(WritePayloadLimit.fromPlatform(514).value, equals(512));
      expect(WritePayloadLimit.fromPlatform(513).value, equals(512));
      expect(WritePayloadLimit.fromPlatform(1000).value, equals(512));
    });

    test('leaves 512 and below unchanged', () {
      expect(WritePayloadLimit.fromPlatform(512).value, equals(512));
      expect(WritePayloadLimit.fromPlatform(511).value, equals(511));
      expect(WritePayloadLimit.fromPlatform(182).value, equals(182));
      expect(WritePayloadLimit.fromPlatform(20).value, equals(20));
    });

    test('preserves the platform "unavailable" sentinels (0, -1)', () {
      // The clamp only ever lowers values above 512.
      expect(WritePayloadLimit.fromPlatform(0).value, equals(0));
      expect(WritePayloadLimit.fromPlatform(-1).value, equals(-1));
    });

    test('exposes the cap as a constant', () {
      expect(maxAttributeValueLength, equals(512));
    });
  });
}
