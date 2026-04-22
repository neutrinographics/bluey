import 'package:bluey_example/features/stress_tests/domain/stress_test_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StressTestResult', () {
    test('empty result has zero counters and isRunning=true', () {
      final r = StressTestResult.initial();
      expect(r.attempted, equals(0));
      expect(r.succeeded, equals(0));
      expect(r.failed, equals(0));
      expect(r.failuresByType, isEmpty);
      expect(r.statusCounts, isEmpty);
      expect(r.latencies, isEmpty);
      expect(r.isRunning, isTrue);
      expect(r.connectionLost, isFalse);
    });

    test('recordSuccess increments attempted and succeeded', () {
      final r = StressTestResult.initial()
          .recordSuccess(latency: const Duration(milliseconds: 10));
      expect(r.attempted, equals(1));
      expect(r.succeeded, equals(1));
      expect(r.failed, equals(0));
      expect(r.latencies, equals([const Duration(milliseconds: 10)]));
    });

    test('recordFailure increments attempted and failed', () {
      final r = StressTestResult.initial()
          .recordFailure(typeName: 'GattTimeoutException');
      expect(r.attempted, equals(1));
      expect(r.succeeded, equals(0));
      expect(r.failed, equals(1));
      expect(r.failuresByType['GattTimeoutException'], equals(1));
    });

    test('recordFailure with status increments statusCounts', () {
      final r = StressTestResult.initial().recordFailure(
        typeName: 'GattOperationFailedException',
        status: 1,
      );
      expect(r.statusCounts[1], equals(1));
    });

    test('multiple failures of same type accumulate', () {
      var r = StressTestResult.initial();
      r = r.recordFailure(typeName: 'GattTimeoutException');
      r = r.recordFailure(typeName: 'GattTimeoutException');
      r = r.recordFailure(typeName: 'DisconnectedException');
      expect(r.failuresByType['GattTimeoutException'], equals(2));
      expect(r.failuresByType['DisconnectedException'], equals(1));
      expect(r.failed, equals(3));
    });

    test('medianLatency returns middle value', () {
      var r = StressTestResult.initial();
      for (final ms in [5, 10, 15, 20, 25]) {
        r = r.recordSuccess(latency: Duration(milliseconds: ms));
      }
      expect(r.medianLatency, equals(const Duration(milliseconds: 15)));
    });

    test('medianLatency returns Duration.zero when no latencies', () {
      expect(StressTestResult.initial().medianLatency, equals(Duration.zero));
    });

    test('p95Latency returns 95th-percentile value', () {
      var r = StressTestResult.initial();
      for (var i = 1; i <= 100; i++) {
        r = r.recordSuccess(latency: Duration(milliseconds: i));
      }
      // 95th percentile of 1..100 = 95.
      expect(r.p95Latency, equals(const Duration(milliseconds: 95)));
    });

    test('finished sets isRunning false and freezes elapsed', () {
      final r = StressTestResult.initial().finished(
        elapsed: const Duration(seconds: 3),
      );
      expect(r.isRunning, isFalse);
      expect(r.elapsed, equals(const Duration(seconds: 3)));
    });

    test('markConnectionLost flips connectionLost to true while preserving counters', () {
      final base = StressTestResult.initial()
          .recordSuccess(latency: const Duration(milliseconds: 5))
          .recordFailure(typeName: 'GattTimeoutException');
      final lost = base.markConnectionLost();
      expect(lost.connectionLost, isTrue);
      expect(lost.attempted, equals(base.attempted));
      expect(lost.succeeded, equals(base.succeeded));
      expect(lost.failed, equals(base.failed));
    });

    test('recordSuccess called on a connectionLost=true result keeps it true', () {
      final r = StressTestResult.initial()
          .markConnectionLost()
          .recordSuccess(latency: const Duration(milliseconds: 10));
      expect(r.connectionLost, isTrue);
    });

    test('recordFailure called on a connectionLost=true result keeps it true', () {
      final r = StressTestResult.initial()
          .markConnectionLost()
          .recordFailure(typeName: 'DisconnectedException');
      expect(r.connectionLost, isTrue);
    });

    test('failuresByType is unmodifiable', () {
      final r = StressTestResult.initial()
          .recordFailure(typeName: 'GattTimeoutException');
      expect(() => r.failuresByType['X'] = 1, throwsUnsupportedError);
    });

    test('latencies is unmodifiable', () {
      final r = StressTestResult.initial()
          .recordSuccess(latency: const Duration(milliseconds: 10));
      expect(() => r.latencies.add(Duration.zero), throwsUnsupportedError);
    });

    test('statusCounts is unmodifiable', () {
      final r = StressTestResult.initial().recordFailure(
        typeName: 'GattOperationFailedException',
        status: 1,
      );
      expect(() => r.statusCounts[2] = 1, throwsUnsupportedError);
    });
  });
}
