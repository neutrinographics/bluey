import 'package:bluey/bluey.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ConnectionParameters', () {
    test('constructs with valid interval/latency/timeout', () {
      final params = ConnectionParameters(
        interval: ConnectionInterval(100),
        latency: PeripheralLatency(0),
        timeout: SupervisionTimeout(200),
      );
      expect(params.interval, equals(ConnectionInterval(100)));
      expect(params.latency, equals(PeripheralLatency(0)));
      expect(params.timeout, equals(SupervisionTimeout(200)));
    });

    test('throws when timeout equals (1 + latency) * interval (10000 ms)', () {
      // (1 + 99) * 100 = 10000; strict-greater-than means 10000 must throw.
      expect(
        () => ConnectionParameters(
          interval: ConnectionInterval(100),
          latency: PeripheralLatency(99),
          timeout: SupervisionTimeout(10000),
        ),
        throwsArgumentError,
      );
    });

    test('succeeds when timeout exceeds (1 + latency) * interval by 1 ms', () {
      // (1 + 99) * 100 = 10000; 10001 must succeed.
      final params = ConnectionParameters(
        interval: ConnectionInterval(100),
        latency: PeripheralLatency(99),
        timeout: SupervisionTimeout(10001),
      );
      expect(params.timeout.milliseconds, 10001);
    });

    test('two ConnectionParameters with the same fields are equal', () {
      final a = ConnectionParameters(
        interval: ConnectionInterval(30),
        latency: PeripheralLatency(0),
        timeout: SupervisionTimeout(4000),
      );
      final b = ConnectionParameters(
        interval: ConnectionInterval(30),
        latency: PeripheralLatency(0),
        timeout: SupervisionTimeout(4000),
      );
      expect(a, equals(b));
    });

    test('two equal ConnectionParameters share a hash code', () {
      final a = ConnectionParameters(
        interval: ConnectionInterval(30),
        latency: PeripheralLatency(0),
        timeout: SupervisionTimeout(4000),
      );
      final b = ConnectionParameters(
        interval: ConnectionInterval(30),
        latency: PeripheralLatency(0),
        timeout: SupervisionTimeout(4000),
      );
      expect(a.hashCode, equals(b.hashCode));
    });

    test('two ConnectionParameters with different fields are not equal', () {
      final a = ConnectionParameters(
        interval: ConnectionInterval(30),
        latency: PeripheralLatency(0),
        timeout: SupervisionTimeout(4000),
      );
      final b = ConnectionParameters(
        interval: ConnectionInterval(30),
        latency: PeripheralLatency(0),
        timeout: SupervisionTimeout(5000),
      );
      expect(a, isNot(equals(b)));
    });

    test('toString includes interval, latency, and timeout', () {
      final s =
          ConnectionParameters(
            interval: ConnectionInterval(30),
            latency: PeripheralLatency(0),
            timeout: SupervisionTimeout(4000),
          ).toString();
      expect(s, contains('30'));
      expect(s, contains('0'));
      expect(s, contains('4000'));
    });
  });
}
