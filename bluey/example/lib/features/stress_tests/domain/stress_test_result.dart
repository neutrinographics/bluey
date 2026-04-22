/// Immutable snapshot of a stress test's running counters.
///
/// Created via [StressTestResult.initial] and updated functionally via
/// [recordSuccess] / [recordFailure] / [finished], each returning a new
/// instance. The runner emits successive snapshots on its result stream.
class StressTestResult {
  final int attempted;
  final int succeeded;
  final int failed;

  /// Failure counts keyed by exception class name (e.g.
  /// `'GattTimeoutException'`, `'DisconnectedException'`).
  final Map<String, int> failuresByType;

  /// Status-code counts for failures of type
  /// `GattOperationFailedException`. Empty for any other failure type.
  final Map<int, int> statusCounts;

  /// Per-op latencies, in submission order. Used for median / p95.
  final List<Duration> latencies;

  /// Wall-clock elapsed since the test started. Updated incrementally
  /// while the test runs; frozen by [finished].
  final Duration elapsed;

  /// Whether the test is still in flight. False after [finished].
  final bool isRunning;

  /// Whether a [DisconnectedException] was observed during the run. Once set
  /// to true it stays true for the lifetime of the result chain.
  final bool connectionLost;

  const StressTestResult._({
    required this.attempted,
    required this.succeeded,
    required this.failed,
    required this.failuresByType,
    required this.statusCounts,
    required this.latencies,
    required this.elapsed,
    required this.isRunning,
    required this.connectionLost,
  });

  factory StressTestResult.initial() => const StressTestResult._(
        attempted: 0,
        succeeded: 0,
        failed: 0,
        failuresByType: {},
        statusCounts: {},
        latencies: [],
        elapsed: Duration.zero,
        isRunning: true,
        connectionLost: false,
      );

  StressTestResult recordSuccess({required Duration latency}) {
    return StressTestResult._(
      attempted: attempted + 1,
      succeeded: succeeded + 1,
      failed: failed,
      failuresByType: failuresByType,
      statusCounts: statusCounts,
      latencies: List.unmodifiable([...latencies, latency]),
      elapsed: elapsed,
      isRunning: isRunning,
      connectionLost: connectionLost,
    );
  }

  StressTestResult recordFailure({
    required String typeName,
    int? status,
  }) {
    final newFailures = Map<String, int>.from(failuresByType);
    newFailures[typeName] = (newFailures[typeName] ?? 0) + 1;
    final newStatusCounts = Map<int, int>.from(statusCounts);
    if (status != null) {
      newStatusCounts[status] = (newStatusCounts[status] ?? 0) + 1;
    }
    return StressTestResult._(
      attempted: attempted + 1,
      succeeded: succeeded,
      failed: failed + 1,
      failuresByType: Map.unmodifiable(newFailures),
      statusCounts: Map.unmodifiable(newStatusCounts),
      latencies: latencies,
      elapsed: elapsed,
      isRunning: isRunning,
      connectionLost: connectionLost,
    );
  }

  StressTestResult withElapsed(Duration newElapsed) {
    return StressTestResult._(
      attempted: attempted,
      succeeded: succeeded,
      failed: failed,
      failuresByType: failuresByType,
      statusCounts: statusCounts,
      latencies: latencies,
      elapsed: newElapsed,
      isRunning: isRunning,
      connectionLost: connectionLost,
    );
  }

  StressTestResult finished({required Duration elapsed}) {
    return StressTestResult._(
      attempted: attempted,
      succeeded: succeeded,
      failed: failed,
      failuresByType: failuresByType,
      statusCounts: statusCounts,
      latencies: latencies,
      elapsed: elapsed,
      isRunning: false,
      connectionLost: connectionLost,
    );
  }

  /// Returns a new instance with [connectionLost] set to true, preserving all
  /// other fields. Once the connection is lost it cannot be un-lost.
  StressTestResult markConnectionLost() {
    return StressTestResult._(
      attempted: attempted,
      succeeded: succeeded,
      failed: failed,
      failuresByType: failuresByType,
      statusCounts: statusCounts,
      latencies: latencies,
      elapsed: elapsed,
      isRunning: isRunning,
      connectionLost: true,
    );
  }

  /// Median (50th-percentile) latency. Zero if no successes recorded.
  Duration get medianLatency {
    if (latencies.isEmpty) return Duration.zero;
    final sorted = [...latencies]..sort();
    return sorted[sorted.length ~/ 2];
  }

  /// 95th-percentile latency. Zero if no successes recorded.
  Duration get p95Latency {
    if (latencies.isEmpty) return Duration.zero;
    final sorted = [...latencies]..sort();
    final idx = ((sorted.length - 1) * 0.95).round();
    return sorted[idx];
  }
}
