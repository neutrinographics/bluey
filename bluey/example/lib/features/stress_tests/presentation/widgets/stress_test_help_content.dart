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
                'Fires count writes to the echo characteristic back-to-back, '
                'each waiting for its acknowledgement before the next is '
                'sent. Pushes the BLE write queue to capacity and measures '
                'sustained throughput end-to-end.\n\n'
                'count sets total writes. bytes is the payload per write — '
                'larger values stress fragmentation and reassembly. Enable '
                'withResponse to require an ATT acknowledgement per write; '
                'disable it for maximum throughput at the cost of delivery '
                'guarantees.',
            readingResults:
                'A low failure rate (ideally zero) confirms the stack '
                'handles sustained writes reliably. Any failures are '
                'broken down by exception type.\n\n'
                'A large gap between median and p95 latency points to '
                'occasional stalls — typically retransmission or '
                'flow-control backpressure on the wire.',
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
                'Runs iterations cycles of write → read → discover-services '
                '→ request-MTU. Each cycle exercises a different GATT '
                'operation in sequence, catching bugs that only appear '
                'when operation types are interleaved — state-machine '
                'races, incorrect handle caching after re-discovery, MTU '
                'desync.',
            readingResults:
                'All four operations in a cycle count as one attempt. A '
                'failure in any step is recorded as a single failure for '
                'that cycle with the exception type.\n\n'
                'Watch for GattOperationFailedException — it often '
                'indicates a state-machine bug triggered by the specific '
                'sequence. Median and p95 latency measure end-to-end '
                'cycle time.',
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
                'seconds, mimicking a long-running sensor stream. '
                'Designed to expose memory leaks, handle exhaustion, and '
                'reliability degradation under sustained load — not peak '
                'throughput.\n\n'
                'duration is the total wall time. interval controls write '
                'cadence — lower values increase pressure. bytes is the '
                'payload per write.',
            readingResults:
                'Focus on failure rate over time, not throughput. A rising '
                'failure count late in the run (compare elapsed vs '
                'attempted) suggests resource exhaustion.\n\n'
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
                'Sends a single write and asks the server to delay its '
                'acknowledgement by delay past timeout milliseconds '
                'beyond the per-operation timeout. Verifies that the '
                'client correctly raises GattTimeoutException for the '
                'slow op AND that the underlying connection survives — a '
                'server taking a long time to respond is not a peer-dead '
                'signal.',
            readingResults:
                'Expect exactly 1 GattTimeoutException (the timed-out '
                'write). The connection should remain connected after '
                'the timeout, demonstrating that the lifecycle layer '
                'correctly tolerates a long-running server-side '
                'operation.\n\n'
                'If the connection drops, the lifecycle policy is being '
                'tripped by the slow op — see the "Heartbeat tolerance" '
                'setting on the connection screen. With Strict (1), even '
                'one slow op can trip the dead-peer threshold; with '
                'Tolerant (3) or higher, slow ops are absorbed.',
            relevantStats: [
              HelpStat.attempted,
              HelpStat.succeeded,
              HelpStat.failed,
            ],
          ),
        StressTest.failureInjection => const StressTestHelpContent(
            whatItDoes:
                'Issues a drop-next command to the server, then fires '
                'writeCount writes against the echo characteristic. The '
                'first write is silently dropped by the server; '
                'subsequent writes are answered normally. Verifies how '
                'the client handles a single dropped response — and '
                'depending on the heartbeat tolerance setting, '
                'demonstrates either clean disconnect or tolerant '
                'recovery.',
            readingResults:
                'Outcome depends on the "Heartbeat tolerance" setting on '
                'the connection screen.\n\n'
                'Strict (1) — the default: expect 1 GattTimeoutException '
                '(the dropped write) followed by writeCount−1 '
                'GattOperationDisconnectedException as the queued ops '
                'drain. The lifecycle layer correctly declares the peer '
                'unreachable and tears down. Tap Reconnect on the '
                'disconnected dialog to start over. This is the '
                'disconnect-cascade scenario.\n\n'
                'Tolerant (3) or Very tolerant (5): expect 1 '
                'GattTimeoutException and writeCount−1 successes. A '
                'single dropped response is absorbed, the connection '
                'survives, subsequent writes succeed. This is the '
                'recovery scenario.',
            relevantStats: [
              HelpStat.attempted,
              HelpStat.succeeded,
              HelpStat.failed,
            ],
          ),
        StressTest.mtuProbe => const StressTestHelpContent(
            whatItDoes:
                'Requests requestedMtu bytes as the ATT MTU, then sends '
                'writes of payloadBytes each. Confirms that MTU '
                'negotiation completes and that payloads at or near the '
                'negotiated MTU transfer without fragmentation '
                'errors.\n\n'
                'requestedMtu is the value passed to the platform MTU '
                'request API — the negotiated result may be lower '
                'depending on the peripheral. Set payloadBytes to '
                'requestedMtu − 3 to test the maximum single-packet '
                'payload (3-byte ATT header overhead).',
            readingResults:
                'Any failures indicate either failed MTU negotiation or '
                'incorrect payload sizing.\n\n'
                'Unusually high median or p95 latency at large MTU sizes '
                'can indicate retransmission due to RF congestion rather '
                'than stack bugs.',
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
                'Asks the server to fire count notifications, then counts '
                'how many are received and measures per-notification '
                'latency from burst start. Tests the inbound notification '
                'pipeline: subscription stability, delivery ordering, '
                'and throughput under a burst of inbound packets.\n\n'
                'count is the total notifications requested. payloadBytes '
                'is the payload per notification — larger values test '
                'reassembly and buffer management on the receive path.',
            readingResults:
                'SUCCEEDED should equal count. Any shortfall means '
                'notifications were dropped or arrived after the '
                'observation window closed.\n\n'
                'Median and p95 latency measure time from burst command '
                'to notification receipt — high p95 indicates OS-level '
                'scheduling jitter rather than BLE-stack issues.',
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
