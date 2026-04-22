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
    if (c is MixedOpsConfig) return _mixedOps(c);
    if (c is SoakConfig) return _soak(c);
    if (c is TimeoutProbeConfig) return _timeoutProbe(c);
    if (c is FailureInjectionConfig) return _failureInjection(c);
    // Fallback for as-yet-unsupported configs (filled in by Tasks 16-19)
    return Text(
      'Config form for ${c.runtimeType} not implemented yet',
      style: TextStyle(color: Colors.grey.shade600),
    );
  }

  Widget _soak(SoakConfig c) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _intField(
          label: 'duration (s)',
          value: c.duration.inSeconds,
          onChanged: (v) => onChanged(SoakConfig(
            duration: Duration(seconds: v),
            interval: c.interval,
            payloadBytes: c.payloadBytes,
          )),
        ),
        _intField(
          label: 'interval (ms)',
          value: c.interval.inMilliseconds,
          onChanged: (v) => onChanged(SoakConfig(
            duration: c.duration,
            interval: Duration(milliseconds: v),
            payloadBytes: c.payloadBytes,
          )),
        ),
        _intField(
          label: 'bytes',
          value: c.payloadBytes,
          onChanged: (v) => onChanged(SoakConfig(
            duration: c.duration,
            interval: c.interval,
            payloadBytes: v,
          )),
        ),
      ],
    );
  }

  Widget _timeoutProbe(TimeoutProbeConfig c) {
    return _intField(
      label: 'delay past timeout (s)',
      value: c.delayPastTimeout.inSeconds,
      onChanged: (v) => onChanged(TimeoutProbeConfig(
        delayPastTimeout: Duration(seconds: v),
      )),
    );
  }

  Widget _failureInjection(FailureInjectionConfig c) {
    return _intField(
      label: 'writeCount',
      value: c.writeCount,
      onChanged: (v) => onChanged(FailureInjectionConfig(writeCount: v)),
    );
  }

  Widget _mixedOps(MixedOpsConfig c) {
    return _intField(
      label: 'iterations',
      value: c.iterations,
      onChanged: (v) => onChanged(MixedOpsConfig(iterations: v)),
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
