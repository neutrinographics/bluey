/// Identifier for each stress test the example app can run. One enum
/// value per UI card / use case.
enum StressTest {
  burstWrite,
  mixedOps,
  soak,
  timeoutProbe,
  failureInjection,
  mtuProbe,
  notificationThroughput,
}

extension StressTestX on StressTest {
  /// Human-readable name shown on the test card.
  String get displayName => switch (this) {
        StressTest.burstWrite => 'Burst write',
        StressTest.mixedOps => 'Mixed ops',
        StressTest.soak => 'Soak',
        StressTest.timeoutProbe => 'Timeout probe',
        StressTest.failureInjection => 'Failure injection',
        StressTest.mtuProbe => 'MTU probe',
        StressTest.notificationThroughput => 'Notification throughput',
      };
}
