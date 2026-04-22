import 'package:flutter/material.dart';

import '../../domain/stress_test.dart';
import '../../domain/stress_test_config.dart';
import '../../domain/stress_test_result.dart';
import 'config_form.dart';
import 'results_panel.dart';

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
    final canRun = !anyRunning;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    test.displayName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                OutlinedButton(
                  onPressed: canRun ? onRun : null,
                  child: const Text('Run'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: isRunning ? onStop : null,
                  child: const Text('Stop'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ConfigForm(
              config: config,
              enabled: !isRunning,
              onChanged: onConfigChanged,
            ),
            if (result != null) ...[
              const SizedBox(height: 8),
              ResultsPanel(result: result!),
            ],
          ],
        ),
      ),
    );
  }
}
