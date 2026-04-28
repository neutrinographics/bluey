import 'package:bluey/bluey.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SupervisionTimeout', () {
    test('constructs at BLE-spec minimum (100 ms)', () {
      final timeout = SupervisionTimeout(100);
      expect(timeout.milliseconds, 100);
    });

    test('constructs at BLE-spec maximum (32000 ms)', () {
      final timeout = SupervisionTimeout(32000);
      expect(timeout.milliseconds, 32000);
    });

    test('throws ArgumentError just below minimum (99)', () {
      expect(() => SupervisionTimeout(99), throwsArgumentError);
    });

    test('throws ArgumentError just above maximum (32001)', () {
      expect(() => SupervisionTimeout(32001), throwsArgumentError);
    });

    test('two timeouts with the same value are equal', () {
      expect(
        SupervisionTimeout(5000),
        equals(SupervisionTimeout(5000)),
      );
    });

    test('two timeouts with the same value share a hash code', () {
      expect(
        SupervisionTimeout(5000).hashCode,
        equals(SupervisionTimeout(5000).hashCode),
      );
    });

    test('two timeouts with different values are not equal', () {
      expect(
        SupervisionTimeout(5000),
        isNot(equals(SupervisionTimeout(6000))),
      );
    });

    test('toString includes the wrapped value', () {
      expect(SupervisionTimeout(5000).toString(), contains('5000'));
    });
  });
}
