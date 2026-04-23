import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../domain/stress_test.dart';
import '../../domain/stress_test_config.dart';
import '../../domain/stress_test_result.dart';
import 'config_form.dart';
import 'results_panel.dart';

// ─── Design tokens ────────────────────────────────────────────────────────────

const _kCard = Colors.white;
const _kAccent = Color(0xFF3F6187);
const _kDark = Color(0xFF2C3437);
const _kMid = Color(0xFF596064);
const _kGreen = Color(0xFF006D4A);
const _kRed = Color(0xFFA83836);
const _kStopBg = Color(0xFFE3E9ED);

// ─── Presentation metadata extension ─────────────────────────────────────────

extension _StressTestMeta on StressTest {
  IconData get _icon => switch (this) {
        StressTest.burstWrite => Icons.bolt,
        StressTest.mixedOps => Icons.swap_horiz,
        StressTest.soak => Icons.timer_outlined,
        StressTest.timeoutProbe => Icons.alarm_outlined,
        StressTest.failureInjection => Icons.bug_report_outlined,
        StressTest.mtuProbe => Icons.settings_ethernet,
        StressTest.notificationThroughput => Icons.notifications_outlined,
      };

  Color get _iconBg => switch (this) {
        StressTest.burstWrite => const Color(0x4DAFD2FD),
        StressTest.mixedOps => const Color(0x4DD3E4FE),
        StressTest.soak => const Color(0x3369F6B8),
        StressTest.timeoutProbe => const Color(0x33FA746F),
        StressTest.failureInjection => const Color(0x33FA746F),
        StressTest.mtuProbe => const Color(0x4DAFD2FD),
        StressTest.notificationThroughput => const Color(0x4DD3E4FE),
      };

  Color get _iconColor => switch (this) {
        StressTest.burstWrite => _kAccent,
        StressTest.mixedOps => _kAccent,
        StressTest.soak => _kGreen,
        StressTest.timeoutProbe => _kRed,
        StressTest.failureInjection => _kRed,
        StressTest.mtuProbe => _kAccent,
        StressTest.notificationThroughput => _kAccent,
      };

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

// ─── TestCard ─────────────────────────────────────────────────────────────────

class TestCard extends StatelessWidget {
  final StressTest test;
  final StressTestConfig config;
  final StressTestResult? result;
  final bool isRunning;

  /// True when *some* card (possibly this one) is running. Used to
  /// disable the Run button on idle cards.
  final bool anyRunning;
  final VoidCallback onRun;
  final VoidCallback onStop;
  final ValueChanged<StressTestConfig> onConfigChanged;

  const TestCard({
    super.key,
    required this.test,
    required this.config,
    required this.result,
    required this.isRunning,
    required this.anyRunning,
    required this.onRun,
    required this.onStop,
    required this.onConfigChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeader(test: test),
          const SizedBox(height: 24),
          ConfigForm(
            config: config,
            enabled: !isRunning,
            onChanged: onConfigChanged,
          ),
          if (result != null) ...[
            const SizedBox(height: 24),
            ResultsPanel(result: result!),
          ],
          const SizedBox(height: 24),
          _ActionRow(
            isRunning: isRunning,
            anyRunning: anyRunning,
            onRun: onRun,
            onStop: onStop,
          ),
        ],
      ),
    );
  }
}

// ─── Card header ─────────────────────────────────────────────────────────────

class _CardHeader extends StatelessWidget {
  final StressTest test;
  const _CardHeader({required this.test});

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
        Column(
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
      ],
    );
  }
}

// ─── Action row ───────────────────────────────────────────────────────────────

class _ActionRow extends StatelessWidget {
  final bool isRunning;
  final bool anyRunning;
  final VoidCallback onRun;
  final VoidCallback onStop;

  const _ActionRow({
    required this.isRunning,
    required this.anyRunning,
    required this.onRun,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final canRun = !anyRunning;
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: canRun ? onRun : null,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                gradient: canRun
                    ? const LinearGradient(
                        begin: Alignment(-0.7, -0.5),
                        end: Alignment(0.7, 0.5),
                        colors: [Color(0xFF3F6187), Color(0xFF32557A)],
                      )
                    : null,
                color: canRun ? null : _kStopBg,
                borderRadius: BorderRadius.circular(16),
                boxShadow: canRun
                    ? [
                        BoxShadow(
                          color: _kAccent.withValues(alpha: 0.1),
                          blurRadius: 15,
                          offset: const Offset(0, 10),
                          spreadRadius: -3,
                        ),
                      ]
                    : null,
              ),
              alignment: Alignment.center,
              child: Text(
                'Run',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: canRun ? Colors.white : _kMid,
                  letterSpacing: 0.35,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        GestureDetector(
          onTap: isRunning ? onStop : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              color: _kStopBg,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              'Stop',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isRunning ? _kMid : _kMid.withValues(alpha: 0.4),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
