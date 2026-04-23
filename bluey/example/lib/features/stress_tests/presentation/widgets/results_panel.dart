import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../domain/stress_test_result.dart';

const _kUuidBg = Color(0xFFF0F4F7);
const _kDark = Color(0xFF2C3437);
const _kMid = Color(0xFF596064);
const _kAccent = Color(0xFF3F6187);
const _kGreen = Color(0xFF006D4A);
const _kRed = Color(0xFFA83836);

class ResultsPanel extends StatelessWidget {
  final StressTestResult result;
  const ResultsPanel({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final r = result;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      decoration: BoxDecoration(
        color: _kUuidBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (r.connectionLost) ...[
            const _ConnectionLostBanner(),
            const SizedBox(height: 16),
          ],
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: _StatCell(
                    label: 'ATTEMPTED',
                    value: '${r.attempted}',
                    valueColor: _kAccent,
                    valueFontSize: 18,
                    bold: true,
                  ),
                ),
                const _ColumnDivider(),
                Expanded(
                  child: _StatCell(
                    label: 'SUCCEEDED',
                    value: '${r.succeeded}',
                    valueColor: _kGreen,
                    valueFontSize: 18,
                    bold: true,
                  ),
                ),
                const _ColumnDivider(),
                Expanded(
                  child: _StatCell(
                    label: 'FAILED',
                    value: '${r.failed}',
                    valueColor: _kRed,
                    valueFontSize: 18,
                    bold: true,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: _StatCell(
                    label: 'MEDIAN',
                    value: r.latencies.isNotEmpty
                        ? '${r.medianLatency.inMilliseconds}ms'
                        : '—',
                    valueColor: _kDark,
                    valueFontSize: 16,
                    bold: false,
                  ),
                ),
                const _ColumnDivider(),
                Expanded(
                  child: _StatCell(
                    label: 'P95',
                    value: r.latencies.isNotEmpty
                        ? '${r.p95Latency.inMilliseconds}ms'
                        : '—',
                    valueColor: _kDark,
                    valueFontSize: 16,
                    bold: false,
                  ),
                ),
                const _ColumnDivider(),
                Expanded(
                  child: _StatCell(
                    label: 'ELAPSED',
                    value: _formatElapsed(r.elapsed),
                    valueColor: _kDark,
                    valueFontSize: 16,
                    bold: false,
                  ),
                ),
              ],
            ),
          ),
          if (r.failuresByType.isNotEmpty) ...[
            const SizedBox(height: 12),
            _FailureDetails(result: r),
          ],
        ],
      ),
    );
  }

  String _formatElapsed(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _StatCell extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  final double valueFontSize;
  final bool bold;

  const _StatCell({
    required this.label,
    required this.value,
    required this.valueColor,
    required this.valueFontSize,
    required this.bold,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: _kMid,
            letterSpacing: -0.45,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: bold
              ? GoogleFonts.manrope(
                  fontSize: valueFontSize,
                  fontWeight: FontWeight.w700,
                  color: valueColor,
                )
              : GoogleFonts.manrope(
                  fontSize: valueFontSize,
                  fontWeight: FontWeight.w600,
                  color: valueColor,
                ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _ColumnDivider extends StatelessWidget {
  const _ColumnDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 1),
      color: const Color(0x1AACB3B7),
    );
  }
}

class _ConnectionLostBanner extends StatelessWidget {
  const _ConnectionLostBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0x1AA83836),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          const Icon(Icons.link_off, size: 14, color: _kRed),
          const SizedBox(width: 6),
          Text(
            'Connection lost',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _kRed,
            ),
          ),
        ],
      ),
    );
  }
}

class _FailureDetails extends StatelessWidget {
  final StressTestResult result;
  const _FailureDetails({required this.result});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Failures:',
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: _kMid,
          ),
        ),
        for (final entry in result.failuresByType.entries)
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 2),
            child: Text(
              '${entry.key} × ${entry.value}',
              style: GoogleFonts.inter(fontSize: 11, color: _kRed),
            ),
          ),
        if (result.statusCounts.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 2),
            child: Text(
              'Status codes: ${result.statusCounts.entries.map((e) => '0x${e.key.toRadixString(16)} × ${e.value}').join(', ')}',
              style: GoogleFonts.inter(fontSize: 11, color: _kMid),
            ),
          ),
      ],
    );
  }
}
