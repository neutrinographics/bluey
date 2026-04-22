import 'package:flutter/material.dart';

import '../../domain/stress_test_config.dart';

class ConfigForm extends StatelessWidget {
  final StressTestConfig config;
  final bool enabled;
  final ValueChanged<StressTestConfig> onChanged;

  const ConfigForm({
    super.key,
    required this.config,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = config;
    if (c is BurstWriteConfig) return _burst(c);
    // Fallback for as-yet-unsupported configs (filled in by Tasks 14-19)
    return Text(
      'Config form for ${c.runtimeType} not implemented yet',
      style: TextStyle(color: Colors.grey.shade600),
    );
  }

  Widget _burst(BurstWriteConfig c) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _intField(
          label: 'count',
          value: c.count,
          onChanged: (v) => onChanged(BurstWriteConfig(
            count: v,
            payloadBytes: c.payloadBytes,
            withResponse: c.withResponse,
          )),
        ),
        _intField(
          label: 'bytes',
          value: c.payloadBytes,
          onChanged: (v) => onChanged(BurstWriteConfig(
            count: c.count,
            payloadBytes: v,
            withResponse: c.withResponse,
          )),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(
              value: c.withResponse,
              onChanged: enabled
                  ? (v) => onChanged(BurstWriteConfig(
                        count: c.count,
                        payloadBytes: c.payloadBytes,
                        withResponse: v ?? true,
                      ))
                  : null,
            ),
            const Text('withResponse'),
          ],
        ),
      ],
    );
  }

  Widget _intField({
    required String label,
    required int value,
    required ValueChanged<int> onChanged,
  }) {
    return SizedBox(
      width: 100,
      child: TextField(
        enabled: enabled,
        controller: TextEditingController(text: value.toString()),
        decoration: InputDecoration(labelText: label, isDense: true),
        keyboardType: TextInputType.number,
        onSubmitted: (s) {
          final parsed = int.tryParse(s);
          if (parsed != null && parsed > 0) onChanged(parsed);
        },
      ),
    );
  }
}
