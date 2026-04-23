import '../../domain/stress_test.dart';

enum HelpStat { attempted, succeeded, failed, median, p95, elapsed }

class StressTestHelpContent {
  final String whatItDoes;
  final String readingResults;
  final List<HelpStat> relevantStats;

  const StressTestHelpContent({
    required this.whatItDoes,
    required this.readingResults,
    required this.relevantStats,
  });
}

extension StressTestHelpX on StressTest {
  StressTestHelpContent get helpContent => switch (this) {
        StressTest.burstWrite => const StressTestHelpContent(
            whatItDoes:
                'Fires count writes to the echo characteristic back-to-back '
                'with no delay, waiting for each acknowledgement before moving '
                'on. Pushes the BLE write queue to capacity.\n\n'
                'count sets total writes. bytes is the payload per write — '
                'larger values stress fragmentation and reassembly. Enable '
                'withResponse to require an ATT acknowledgement per write; '
                'disable it for maximum throughput at the cost of delivery '
                'guarantees.',
            readingResults:
                'A low failure rate confirms the stack handles sustained writes '
                'reliably. Any failures are broken down by exception type.\n\n'
                'A large gap between median and p95 latency points to '
                'occasional stalls — typically retransmission or flow-control '
                'backpressure.',
            relevantStats: [
              HelpStat.attempted,
              HelpStat.succeeded,
              HelpStat.failed,
              HelpStat.median,
              HelpStat.p95,
              HelpStat.elapsed,
            ],
          ),
        StressTest.mixedOps => const StressTestHelpContent(
            whatItDoes:
                'Runs iterations cycles of write → read → discover-services → '
                'request-MTU in sequence. Each cycle exercises a different GATT '
                'operation, catching bugs that only appear when operation types '
                'are interleaved — such as state machine races or incorrect '
                'handle caching after re-discovery.',
            readingResults:
                'All operations in a cycle count as one attempt. A failure in '
                'any step of a cycle is recorded as a single failure with the '
                'exception type.\n\n'
                'Watch for GattOperationFailedException — it often indicates a '
                'state machine bug triggered by the specific sequence. Median '
                'and p95 latency measure end-to-end cycle time.',
            relevantStats: [
              HelpStat.attempted,
              HelpStat.succeeded,
              HelpStat.failed,
              HelpStat.median,
              HelpStat.p95,
              HelpStat.elapsed,
            ],
          ),
        StressTest.soak => const StressTestHelpContent(
            whatItDoes:
                'Sends a write every interval milliseconds for duration '
                'seconds, mimicking a long-running sensor stream. Designed to '
                'expose memory leaks, handle exhaustion, and reliability '
                'degradation under sustained load rather than peak throughput.\n\n'
                'duration is the total test wall time. interval controls the '
                'write cadence — lower values increase pressure. bytes is the '
                'payload per write.',
            readingResults:
                'Focus on the failure rate over time, not throughput. A rising '
                'failure count late in the run (check elapsed vs attempted) '
                'suggests resource exhaustion.\n\n'
                'Connection loss during a soak is a strong signal of a '
                'platform-level memory or handle leak.',
            relevantStats: [
              HelpStat.attempted,
              HelpStat.succeeded,
              HelpStat.failed,
              HelpStat.elapsed,
            ],
          ),
        StressTest.timeoutProbe => const StressTestHelpContent(
            whatItDoes:
                'Sends a special command telling the server to delay its '
                'acknowledgement by delay past timeout milliseconds beyond the '
                'per-operation timeout. Verifies that the client correctly '
                'raises GattTimeoutException and that subsequent operations '
                'succeed — confirming the stack recovers cleanly from a '
                'timeout.',
            readingResults:
                'Expect exactly 1 failure (the timed-out write) and all '
                'subsequent writes to succeed.\n\n'
                'If more than one operation fails, the stack is not recovering '
                'from timeouts correctly. If none fail, the delay value is '
                'shorter than the actual per-op timeout in use.',
            relevantStats: [
              HelpStat.attempted,
              HelpStat.succeeded,
              HelpStat.failed,
            ],
          ),
        StressTest.failureInjection => const StressTestHelpContent(
            whatItDoes:
                'Issues a drop-next command to the server, then fires '
                'writeCount writes. The first write is intentionally dropped '
                'by the server, causing a timeout. The remaining writes should '
                'all succeed. Verifies that the client correctly classifies '
                'dropped writes as failures and resumes normal operation '
                'immediately after.',
            readingResults:
                'A healthy result is exactly 1 failure (GattTimeoutException) '
                'followed by writeCount − 1 successes.\n\n'
                'More failures indicate the stack is not resetting correctly '
                'after an injected error. Zero failures means the drop command '
                'was not received or the timeout is longer than the test '
                'waited.',
            relevantStats: [
              HelpStat.attempted,
              HelpStat.succeeded,
              HelpStat.failed,
            ],
          ),
        StressTest.mtuProbe => const StressTestHelpContent(
            whatItDoes:
                'Requests requestedMtu bytes as the ATT MTU, then sends writes '
                'of payloadBytes each. Confirms that MTU negotiation completes '
                'and that payloads at or near the negotiated MTU size transfer '
                'without fragmentation errors.\n\n'
                'requestedMtu is the value passed to the platform MTU request '
                'API — the negotiated result may be lower depending on the '
                'peripheral. Set payloadBytes to requestedMtu − 3 to test the '
                'maximum single-packet payload (3-byte ATT header overhead).',
            readingResults:
                'Any failures indicate either a failed MTU negotiation or '
                'incorrect payload sizing.\n\n'
                'Check MEDIAN — unusually high latency at large MTU sizes can '
                'indicate retransmission due to RF congestion rather than stack '
                'bugs.',
            relevantStats: [
              HelpStat.attempted,
              HelpStat.succeeded,
              HelpStat.failed,
              HelpStat.median,
              HelpStat.p95,
              HelpStat.elapsed,
            ],
          ),
        StressTest.notificationThroughput => const StressTestHelpContent(
            whatItDoes:
                'Asks the server to fire count notifications, then counts how '
                'many are received and measures per-notification latency from '
                'burst start. Tests the client-side notification pipeline: '
                'subscription stability, delivery ordering, and throughput '
                'under a burst of inbound packets.\n\n'
                'count is the total notifications requested. payloadBytes is '
                'the payload per notification — larger values test reassembly '
                'and buffer management on the receive path.',
            readingResults:
                'SUCCEEDED should equal count. Any shortfall means '
                'notifications were dropped or arrived after the observation '
                'window closed.\n\n'
                'Median and p95 latency measure time from burst command to '
                'notification receipt — high p95 indicates OS-level scheduling '
                'jitter rather than BLE stack issues.',
            relevantStats: [
              HelpStat.attempted,
              HelpStat.succeeded,
              HelpStat.failed,
              HelpStat.median,
              HelpStat.p95,
              HelpStat.elapsed,
            ],
          ),
      };
}
