import 'package:bluey/bluey.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ConnectionInterval', () {
    test('constructs at BLE-spec minimum (7.5 ms)', () {
      final interval = ConnectionInterval(7.5);
      expect(interval.milliseconds, 7.5);
    });

    test('constructs at BLE-spec maximum (4000 ms)', () {
      final interval = ConnectionInterval(4000);
      expect(interval.milliseconds, 4000);
    });

    test('throws ArgumentError just below minimum (7.4 ms)', () {
      expect(() => ConnectionInterval(7.4), throwsArgumentError);
    });

    test('throws ArgumentError just above maximum (4000.1 ms)', () {
      expect(() => ConnectionInterval(4000.1), throwsArgumentError);
    });

    test('two intervals with the same value are equal', () {
      expect(ConnectionInterval(30), equals(ConnectionInterval(30)));
    });

    test('two intervals with the same value share a hash code', () {
      expect(
        ConnectionInterval(30).hashCode,
        equals(ConnectionInterval(30).hashCode),
      );
    });

    test('two intervals with different values are not equal', () {
      expect(
        ConnectionInterval(30),
        isNot(equals(ConnectionInterval(31))),
      );
    });

    test('toString includes the wrapped value', () {
      expect(ConnectionInterval(30).toString(), contains('30'));
    });
  });
}
