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
              test._subtitle,
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
      StressTest.burstWrite ||
      StressTest.mixedOps ||
      StressTest.mtuProbe ||
      StressTest.notificationThroughput =>
        _kAccent,
      StressTest.soak => _kGreen,
      StressTest.timeoutProbe || StressTest.failureInjection => _kRed,
    };

// Access _subtitle from test_card.dart's private extension via a local mirror.
// This avoids duplicating the strings by re-using the same source of truth
// in test_card.dart — but since that extension is private, we read displayName
// from domain and subtitle is available because _SheetHeader is in the same
// file where _subtitle is defined below as a module-private extension.
extension _StressTestSubtitle on StressTest {
  String get _subtitle => switch (this) {
        StressTest.burstWrite => 'Rapid throughput validation',
        StressTest.mixedOps => 'Read/Write/Notify sequence',
        StressTest.soak => 'Stability & memory leakage',
        StressTest.timeoutProbe => 'Protocol resilience check',
        StressTest.failureInjection => 'Error handling validation',
        StressTest.mtuProbe => 'Maximum transfer unit check',
        StressTest.notificationThroughput => 'Notification delivery rate',
      };
}
