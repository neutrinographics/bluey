/// Per-test configuration. Each subclass holds the parameters its test
/// needs. Defaults are sensible and chosen to complete in seconds-ish
/// against a typical example-server.
sealed class StressTestConfig {
  const StressTestConfig();
}

class BurstWriteConfig extends StressTestConfig {
  /// Total number of writes to fire.
  final int count;
  /// Payload bytes per write (excluding the 1-byte opcode prefix).
  final int payloadBytes;
  /// Whether each write requests a response (true) or fires
  /// without-response (false).
  final bool withResponse;

  const BurstWriteConfig({
    this.count = 50,
    this.payloadBytes = 20,
    this.withResponse = true,
  });
}

class MixedOpsConfig extends StressTestConfig {
  /// Number of (write, read, discoverServices, requestMtu) cycles.
  final int iterations;
  const MixedOpsConfig({this.iterations = 10});
}

class SoakConfig extends StressTestConfig {
  /// Total wall-clock duration of the soak.
  final Duration duration;
  /// Time between successive write attempts.
  final Duration interval;
  /// Echo payload size per write.
  final int payloadBytes;

  const SoakConfig({
    this.duration = const Duration(minutes: 5),
    this.interval = const Duration(seconds: 1),
    this.payloadBytes = 20,
  });
}

class TimeoutProbeConfig extends StressTestConfig {
  /// How far past the per-op timeout the server should delay its ack.
  /// 2s past the default 10s timeout = 12s total wait.
  final Duration delayPastTimeout;
  const TimeoutProbeConfig({
    this.delayPastTimeout = const Duration(seconds: 2),
  });
}

class FailureInjectionConfig extends StressTestConfig {
  /// Total writes to attempt after the dropNext command.
  /// First should time out (dropped); rest should succeed.
  final int writeCount;
  const FailureInjectionConfig({this.writeCount = 10});
}

class MtuProbeConfig extends StressTestConfig {
  /// MTU value to request from the platform.
  final int requestedMtu;
  /// Payload bytes per write/read (defaults to negotiated MTU - 3 ATT
  /// header bytes if 0).
  final int payloadBytes;
  const MtuProbeConfig({this.requestedMtu = 247, this.payloadBytes = 244});
}

class NotificationThroughputConfig extends StressTestConfig {
  /// Number of notifications to ask the server to fire.
  final int count;
  /// Bytes per notification (excluding the burst-id prefix byte).
  final int payloadBytes;
  /// Per-test wall-clock budget for the entire burst to complete. If
  /// `null`, the runner derives a default from [count] (~10 ms per
  /// notification + 2 s prologue overhead) — sized for the post-I040
  /// iOS-server delivery rate (~2–3 ms / notification, queue-drain
  /// bound) with a 5× safety margin.
  final Duration? timeout;
  const NotificationThroughputConfig({
    this.count = 100,
    this.payloadBytes = 20,
    this.timeout,
  });
}
