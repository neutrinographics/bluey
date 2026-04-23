# Stress Test Help Sheets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a circular ⓘ button to each stress test card that opens a bottom sheet explaining what the test does and how to read its results.

**Architecture:** Two new presentation-layer files — `stress_test_help_content.dart` holds a `StressTestHelpContent` value class, a `HelpStat` enum, and a `StressTestHelpX` extension on `StressTest` that maps each test to its copy and relevant stats; `stress_test_help_sheet.dart` holds the `StressTestHelpSheet` widget and a `showStressTestHelp` helper. `test_card.dart` gains a ⓘ button in `_CardHeader` that calls `showStressTestHelp`. Domain layer is untouched.

**Tech Stack:** Flutter, Dart, `google_fonts` (already a dependency), `flutter_test`

---

### Task 1: Help content data

**Files:**
- Create: `bluey/example/lib/features/stress_tests/presentation/widgets/stress_test_help_content.dart`

- [ ] **Step 1: Create the content file**

```dart
// lib/features/stress_tests/presentation/widgets/stress_test_help_content.dart

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
```

- [ ] **Step 2: Commit**

```bash
git add bluey/example/lib/features/stress_tests/presentation/widgets/stress_test_help_content.dart
git commit -m "feat: stress test help content data"
```

---

### Task 2: Write failing help sheet widget tests

**Files:**
- Create: `bluey/example/test/stress_tests/presentation/widgets/stress_test_help_sheet_test.dart`

- [ ] **Step 1: Write the tests**

```dart
// test/stress_tests/presentation/widgets/stress_test_help_sheet_test.dart

import 'package:bluey_example/features/stress_tests/domain/stress_test.dart';
import 'package:bluey_example/features/stress_tests/domain/stress_test_config.dart';
import 'package:bluey_example/features/stress_tests/presentation/widgets/stress_test_help_sheet.dart';
import 'package:bluey_example/features/stress_tests/presentation/widgets/test_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

StressTestConfig _defaultConfig(StressTest test) => switch (test) {
      StressTest.burstWrite => const BurstWriteConfig(),
      StressTest.mixedOps => const MixedOpsConfig(),
      StressTest.soak => const SoakConfig(),
      StressTest.timeoutProbe => const TimeoutProbeConfig(),
      StressTest.failureInjection => const FailureInjectionConfig(),
      StressTest.mtuProbe => const MtuProbeConfig(),
      StressTest.notificationThroughput => const NotificationThroughputConfig(),
    };

void main() {
  Widget wrapSheet(Widget child) => MaterialApp(
        home: Scaffold(body: child),
      );

  group('StressTestHelpSheet', () {
    for (final test in StressTest.values) {
      testWidgets('renders display name for ${test.name}', (tester) async {
        await tester.pumpWidget(
          wrapSheet(StressTestHelpSheet(test: test)),
        );
        expect(find.text(test.displayName), findsOneWidget);
      });
    }

    testWidgets('shows WHAT IT DOES section label', (tester) async {
      await tester.pumpWidget(
        wrapSheet(StressTestHelpSheet(test: StressTest.burstWrite)),
      );
      expect(find.text('WHAT IT DOES'), findsOneWidget);
    });

    testWidgets('shows READING THE RESULTS section label', (tester) async {
      await tester.pumpWidget(
        wrapSheet(StressTestHelpSheet(test: StressTest.burstWrite)),
      );
      expect(find.text('READING THE RESULTS'), findsOneWidget);
    });
  });

  group('TestCard info button', () {
    testWidgets('info button is present on each card', (tester) async {
      for (final test in StressTest.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: TestCard(
                  test: test,
                  config: _defaultConfig(test),
                  result: null,
                  isRunning: false,
                  anyRunning: false,
                  onRun: () {},
                  onStop: () {},
                  onConfigChanged: (_) {},
                ),
              ),
            ),
          ),
        );
        expect(
          find.text('i'),
          findsOneWidget,
          reason: 'Expected info button on ${test.name} card',
        );
      }
    });

    testWidgets('tapping info button opens help sheet with correct content',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: TestCard(
                test: StressTest.burstWrite,
                config: const BurstWriteConfig(),
                result: null,
                isRunning: false,
                anyRunning: false,
                onRun: () {},
                onStop: () {},
                onConfigChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('i'));
      await tester.pumpAndSettle();

      expect(find.byType(StressTestHelpSheet), findsOneWidget);
      expect(find.text('WHAT IT DOES'), findsOneWidget);
      expect(find.text('READING THE RESULTS'), findsOneWidget);
    });

    testWidgets('help sheet is dismissible by tapping barrier', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: TestCard(
                test: StressTest.mixedOps,
                config: const MixedOpsConfig(),
                result: null,
                isRunning: false,
                anyRunning: false,
                onRun: () {},
                onStop: () {},
                onConfigChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('i'));
      await tester.pumpAndSettle();
      expect(find.byType(StressTestHelpSheet), findsOneWidget);

      // Tap the modal barrier above the sheet to dismiss it.
      await tester.tapAt(const Offset(200, 50));
      await tester.pumpAndSettle();
      expect(find.byType(StressTestHelpSheet), findsNothing);
    });
  });
}
```

- [ ] **Step 2: Run tests — verify they fail**

```bash
cd bluey/example && flutter test test/stress_tests/presentation/widgets/stress_test_help_sheet_test.dart
```

Expected: compile error or test failure — `StressTestHelpSheet` does not exist yet.

---

### Task 3: Implement the help sheet widget

**Files:**
- Create: `bluey/example/lib/features/stress_tests/presentation/widgets/stress_test_help_sheet.dart`

- [ ] **Step 1: Create the sheet widget**

```dart
// lib/features/stress_tests/presentation/widgets/stress_test_help_sheet.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../domain/stress_test.dart';
import 'stress_test_help_content.dart';

// ─── Design tokens ────────────────────────────────────────────────────────────

const _kAccent = Color(0xFF3F6187);
const _kDark = Color(0xFF2C3437);
const _kMid = Color(0xFF596064);
const _kGreen = Color(0xFF006D4A);
const _kRed = Color(0xFFA83836);
const _kUuidBg = Color(0xFFF0F4F7);
const _kDivider = Color(0xFFF0F4F7);
const _kHandle = Color(0xFFE3E9ED);

// ─── Public API ───────────────────────────────────────────────────────────────

void showStressTestHelp(BuildContext context, StressTest test) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => StressTestHelpSheet(test: test),
  );
}

// ─── Sheet widget ─────────────────────────────────────────────────────────────

class StressTestHelpSheet extends StatelessWidget {
  final StressTest test;
  const StressTestHelpSheet({super.key, required this.test});

  @override
  Widget build(BuildContext context) {
    final content = test.helpContent;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Handle(),
            _SheetHeader(test: test),
            const SizedBox(height: 16),
            const _Divider(),
            const SizedBox(height: 14),
            _SectionLabel('WHAT IT DOES'),
            const SizedBox(height: 8),
            _BodyText(content.whatItDoes),
            const SizedBox(height: 14),
            const _Divider(),
            const SizedBox(height: 14),
            _SectionLabel('READING THE RESULTS'),
            const SizedBox(height: 8),
            _StatPillsRow(stats: content.relevantStats),
            const SizedBox(height: 8),
            _BodyText(content.readingResults),
          ],
        ),
      ),
    );
  }
}

// ─── Internal widgets ─────────────────────────────────────────────────────────

class _Handle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 32,
        height: 3.5,
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: _kHandle,
          borderRadius: BorderRadius.circular(99),
        ),
      ),
    );
  }
}

class _SheetHeader extends StatelessWidget {
  final StressTest test;
  const _SheetHeader({required this.test});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: _iconBg(test),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(_icon(test), color: _iconColor(test), size: 16),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              test.displayName,
              style: GoogleFonts.manrope(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: _kDark,
                letterSpacing: -0.3,
              ),
            ),
            Text(
              test.helpContent.whatItDoes.split('\n').first.split('.').first,
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: _kMid,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Container(height: 1, color: _kDivider);
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: GoogleFonts.inter(
        fontSize: 9,
        fontWeight: FontWeight.w700,
        color: _kAccent,
        letterSpacing: 1.0,
      ),
    );
  }
}

class _BodyText extends StatelessWidget {
  final String text;
  const _BodyText(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w400,
        color: _kMid,
        height: 1.55,
      ),
    );
  }
}

class _StatPillsRow extends StatelessWidget {
  final List<HelpStat> stats;
  const _StatPillsRow({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: stats.map(_pill).toList(),
    );
  }

  Widget _pill(HelpStat stat) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _kUuidBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: _pillColor(stat),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            _pillLabel(stat),
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: _kMid,
            ),
          ),
        ],
      ),
    );
  }

  Color _pillColor(HelpStat stat) => switch (stat) {
        HelpStat.attempted => _kAccent,
        HelpStat.succeeded => _kGreen,
        HelpStat.failed => _kRed,
        HelpStat.median || HelpStat.p95 || HelpStat.elapsed => _kMid,
      };

  String _pillLabel(HelpStat stat) => switch (stat) {
        HelpStat.attempted => 'ATTEMPTED',
        HelpStat.succeeded => 'SUCCEEDED',
        HelpStat.failed => 'FAILED',
        HelpStat.median => 'MEDIAN',
        HelpStat.p95 => 'P95',
        HelpStat.elapsed => 'ELAPSED',
      };
}

// ─── Icon helpers (mirrors test_card.dart _StressTestMeta) ───────────────────

IconData _icon(StressTest test) => switch (test) {
      StressTest.burstWrite => Icons.bolt,
      StressTest.mixedOps => Icons.swap_horiz,
      StressTest.soak => Icons.timer_outlined,
      StressTest.timeoutProbe => Icons.alarm_outlined,
      StressTest.failureInjection => Icons.bug_report_outlined,
      StressTest.mtuProbe => Icons.settings_ethernet,
      StressTest.notificationThroughput => Icons.notifications_outlined,
    };

Color _iconBg(StressTest test) => switch (test) {
      StressTest.burstWrite => const Color(0x4DAFD2FD),
      StressTest.mixedOps => const Color(0x4DD3E4FE),
      StressTest.soak => const Color(0x3369F6B8),
      StressTest.timeoutProbe => const Color(0x33FA746F),
      StressTest.failureInjection => const Color(0x33FA746F),
      StressTest.mtuProbe => const Color(0x4DAFD2FD),
      StressTest.notificationThroughput => const Color(0x4DD3E4FE),
    };

Color _iconColor(StressTest test) => switch (test) {
      StressTest.burstWrite || StressTest.mixedOps => _kAccent,
      StressTest.mtuProbe || StressTest.notificationThroughput => _kAccent,
      StressTest.soak => _kGreen,
      StressTest.timeoutProbe || StressTest.failureInjection => _kRed,
    };
```

- [ ] **Step 2: Run tests — verify they pass**

```bash
cd bluey/example && flutter test test/stress_tests/presentation/widgets/stress_test_help_sheet_test.dart
```

Expected: all tests PASS except the TestCard group (info button not wired yet — those should still fail at this point).

- [ ] **Step 3: Commit**

```bash
git add bluey/example/lib/features/stress_tests/presentation/widgets/stress_test_help_sheet.dart \
        bluey/example/test/stress_tests/presentation/widgets/stress_test_help_sheet_test.dart
git commit -m "feat: stress test help sheet widget + tests"
```

---

### Task 4: Wire ⓘ button into TestCard

**Files:**
- Modify: `bluey/example/lib/features/stress_tests/presentation/widgets/test_card.dart`

The ⓘ button goes into `_CardHeader`. The existing `_CardHeader.build` returns:

```dart
Row(children: [icon-container, SizedBox(12), Column(title, subtitle)])
```

The new version wraps the Column in `Expanded` and appends the ⓘ button on the right.

- [ ] **Step 1: Add the import and `_kUuidBg` token, then update `_CardHeader`**

In `test_card.dart`, add to the imports block:

```dart
import 'stress_test_help_sheet.dart';
```

Add to the design tokens section (after `_kStopBg`):

```dart
const _kUuidBg = Color(0xFFF0F4F7);
```

Replace the entire `_CardHeader.build` method:

```dart
@override
Widget build(BuildContext context) {
  return Row(
    children: [
      Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: test._iconBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(test._icon, color: test._iconColor, size: 18),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              test.displayName,
              style: GoogleFonts.manrope(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _kDark,
                letterSpacing: -0.45,
              ),
            ),
            Text(
              test._subtitle,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: _kMid,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(width: 8),
      GestureDetector(
        onTap: () => showStressTestHelp(context, test),
        child: Container(
          width: 22,
          height: 22,
          decoration: const BoxDecoration(
            color: _kUuidBg,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            'i',
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: _kAccent,
            ),
          ),
        ),
      ),
    ],
  );
}
```

- [ ] **Step 2: Run the full stress test suite**

```bash
cd bluey/example && flutter test test/stress_tests/
```

Expected: all tests pass, including the previously-failing TestCard group in `stress_test_help_sheet_test.dart` and all existing `test_card_test.dart` tests.

- [ ] **Step 3: Run analyze**

```bash
cd bluey/example && flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add bluey/example/lib/features/stress_tests/presentation/widgets/test_card.dart
git commit -m "feat: wire info button into stress test cards (#help-sheets)"
```
