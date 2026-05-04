import 'package:bluey/bluey.dart';
import 'package:bluey/src/connection/connection_parameters_mapper.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('connectionParametersToPlatform', () {
    test('copies VO primitives onto the platform DTO', () {
      final domain = ConnectionParameters(
        interval: ConnectionInterval(30),
        latency: PeripheralLatency(2),
        timeout: SupervisionTimeout(4000),
      );

      final dto = connectionParametersToPlatform(domain);

      expect(dto.intervalMs, equals(domain.interval.milliseconds));
      expect(dto.latency, equals(domain.latency.events));
      expect(dto.timeoutMs, equals(domain.timeout.milliseconds));
    });

    test('preserves fractional intervalMs (e.g. 7.5 ms spec minimum)', () {
      final domain = ConnectionParameters(
        interval: ConnectionInterval(7.5),
        latency: PeripheralLatency(0),
        timeout: SupervisionTimeout(100),
      );

      final dto = connectionParametersToPlatform(domain);

      expect(dto.intervalMs, equals(7.5));
      expect(dto.latency, equals(0));
      expect(dto.timeoutMs, equals(100));
    });
  });

  group('connectionParametersFromPlatform', () {
    test('builds VOs whose primitives match the source DTO', () {
      const dto = PlatformConnectionParameters(
        intervalMs: 30,
        latency: 2,
        timeoutMs: 4000,
      );

      final domain = connectionParametersFromPlatform(dto);

      expect(domain.interval.milliseconds, equals(dto.intervalMs));
      expect(domain.latency.events, equals(dto.latency));
      expect(domain.timeout.milliseconds, equals(dto.timeoutMs));
    });

    test('throws ArgumentError when intervalMs exceeds spec range', () {
      const dto = PlatformConnectionParameters(
        intervalMs: 5000, // > 4000 ms spec maximum
        latency: 0,
        timeoutMs: 10000,
      );

      expect(() => connectionParametersFromPlatform(dto), throwsArgumentError);
    });

    test('throws ArgumentError when latency is negative', () {
      const dto = PlatformConnectionParameters(
        intervalMs: 30,
        latency: -1,
        timeoutMs: 4000,
      );

      expect(() => connectionParametersFromPlatform(dto), throwsArgumentError);
    });

    test('throws ArgumentError when timeoutMs is below spec range', () {
      const dto = PlatformConnectionParameters(
        intervalMs: 30,
        latency: 0,
        timeoutMs: 50, // < 100 ms spec minimum
      );

      expect(() => connectionParametersFromPlatform(dto), throwsArgumentError);
    });

    test('throws ArgumentError on cross-field invariant violation', () {
      // (1 + 99) * 100 = 10000; strict-greater-than means 10000 must throw.
      const dto = PlatformConnectionParameters(
        intervalMs: 100,
        latency: 99,
        timeoutMs: 10000,
      );

      expect(() => connectionParametersFromPlatform(dto), throwsArgumentError);
    });
  });

  group('round-trip', () {
    test('domain -> platform -> domain preserves equality', () {
      final original = ConnectionParameters(
        interval: ConnectionInterval(30),
        latency: PeripheralLatency(2),
        timeout: SupervisionTimeout(4000),
      );

      final roundTripped = connectionParametersFromPlatform(
        connectionParametersToPlatform(original),
      );

      expect(roundTripped, equals(original));
    });

    test('platform -> domain -> platform preserves primitives', () {
      const original = PlatformConnectionParameters(
        intervalMs: 30,
        latency: 2,
        timeoutMs: 4000,
      );

      final roundTripped = connectionParametersToPlatform(
        connectionParametersFromPlatform(original),
      );

      expect(roundTripped.intervalMs, equals(original.intervalMs));
      expect(roundTripped.latency, equals(original.latency));
      expect(roundTripped.timeoutMs, equals(original.timeoutMs));
    });
  });
}
