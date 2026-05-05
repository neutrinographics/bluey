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
}
