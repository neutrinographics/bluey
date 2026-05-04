import 'package:bluey/bluey.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AttributeHandle', () {
    test('constructs with positive value and exposes it via .value', () {
      final handle = AttributeHandle(1);
      expect(handle.value, 1);
    });

    test('throws ArgumentError for zero', () {
      expect(() => AttributeHandle(0), throwsArgumentError);
    });

    test('throws ArgumentError for negative values', () {
      expect(() => AttributeHandle(-5), throwsArgumentError);
    });

    test('two handles with the same value are equal', () {
      expect(AttributeHandle(7), equals(AttributeHandle(7)));
    });

    test('two handles with the same value share a hash code', () {
      expect(AttributeHandle(7).hashCode, equals(AttributeHandle(7).hashCode));
    });

    test('two handles with different values are not equal', () {
      expect(AttributeHandle(7), isNot(equals(AttributeHandle(8))));
    });

    test('toString includes the wrapped value', () {
      expect(AttributeHandle(7).toString(), contains('7'));
    });
  });
}
