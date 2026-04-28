import 'package:bluey/bluey.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PeripheralLatency', () {
    test('constructs at BLE-spec minimum (0)', () {
      final latency = PeripheralLatency(0);
      expect(latency.events, 0);
    });

    test('constructs at BLE-spec maximum (499)', () {
      final latency = PeripheralLatency(499);
      expect(latency.events, 499);
    });

    test('throws ArgumentError just below minimum (-1)', () {
      expect(() => PeripheralLatency(-1), throwsArgumentError);
    });

    test('throws ArgumentError just above maximum (500)', () {
      expect(() => PeripheralLatency(500), throwsArgumentError);
    });

    test('two latencies with the same value are equal', () {
      expect(PeripheralLatency(4), equals(PeripheralLatency(4)));
    });

    test('two latencies with the same value share a hash code', () {
      expect(
        PeripheralLatency(4).hashCode,
        equals(PeripheralLatency(4).hashCode),
      );
    });

    test('two latencies with different values are not equal', () {
      expect(PeripheralLatency(4), isNot(equals(PeripheralLatency(5))));
    });

    test('toString includes the wrapped value', () {
      expect(PeripheralLatency(7).toString(), contains('7'));
    });
  });
}
