import 'package:flutter/material.dart';

import '../../domain/stress_test_result.dart';

class ResultsPanel extends StatelessWidget {
  final StressTestResult result;
  const ResultsPanel({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final r = result;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Attempted ${r.attempted}  Succeeded ${r.succeeded}  Failed ${r.failed}',
          ),
          if (r.failuresByType.isNotEmpty) ...[
            const SizedBox(height: 4),
            const Text('Failures:'),
            for (final entry in r.failuresByType.entries)
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Text('${entry.key} × ${entry.value}'),
              ),
            if (r.statusCounts.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Text(
                  'Status codes: '
                  '${r.statusCounts.entries.map((e) => '0x${e.key.toRadixString(16)} × ${e.value}').join(', ')}',
                ),
              ),
          ],
          if (r.latencies.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Median: ${r.medianLatency.inMilliseconds}ms  '
                'p95: ${r.p95Latency.inMilliseconds}ms',
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Elapsed: ${_format(r.elapsed)}',
              style: TextStyle(color: Colors.grey.shade700),
            ),
          ),
        ],
      ),
    );
  }

  String _format(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
