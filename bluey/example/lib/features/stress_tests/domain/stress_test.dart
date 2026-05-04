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

  /// Short subtitle shown beneath the display name. Names *what* the test
  /// verifies, not jargon. Audited 2026-04-25.
  String get subtitle => switch (this) {
    StressTest.burstWrite => 'Sustained writes at maximum rate',
    StressTest.mixedOps => 'Interleaved GATT operations',
    StressTest.soak => 'Long-running stability under steady load',
    StressTest.timeoutProbe => 'Slow server response is tolerated',
    StressTest.failureInjection => 'Server drops a response — see what happens',
    StressTest.mtuProbe => 'MTU negotiation and large-payload writes',
    StressTest.notificationThroughput => 'Burst notification reception',
  };
}
