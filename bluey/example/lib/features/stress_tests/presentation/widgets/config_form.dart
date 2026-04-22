import 'package:flutter/material.dart';

import '../../domain/stress_test_config.dart';

class ConfigForm extends StatefulWidget {
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
  State<ConfigForm> createState() => _ConfigFormState();
}

class _ConfigFormState extends State<ConfigForm> {
  final _controllers = <String, TextEditingController>{};

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(String label, int value) {
    final existing = _controllers[label];
    final text = value.toString();
    if (existing == null) {
      return _controllers[label] = TextEditingController(text: text);
    }
    if (existing.text != text) {
      existing.text = text;
    }
    return existing;
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.config;
    if (c is BurstWriteConfig) return _burst(c);
    if (c is MixedOpsConfig) return _mixedOps(c);
    if (c is SoakConfig) return _soak(c);
    if (c is TimeoutProbeConfig) return _timeoutProbe(c);
    if (c is FailureInjectionConfig) return _failureInjection(c);
    if (c is MtuProbeConfig) return _mtuProbe(c);
    if (c is NotificationThroughputConfig) return _notifThroughput(c);
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
          onChanged: (v) => widget.onChanged(SoakConfig(
            duration: Duration(seconds: v),
            interval: c.interval,
            payloadBytes: c.payloadBytes,
          )),
        ),
        _intField(
          label: 'interval (ms)',
          value: c.interval.inMilliseconds,
          onChanged: (v) => widget.onChanged(SoakConfig(
            duration: c.duration,
            interval: Duration(milliseconds: v),
            payloadBytes: c.payloadBytes,
          )),
        ),
        _intField(
          label: 'bytes',
          value: c.payloadBytes,
          onChanged: (v) => widget.onChanged(SoakConfig(
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
      onChanged: (v) => widget.onChanged(TimeoutProbeConfig(
        delayPastTimeout: Duration(seconds: v),
      )),
    );
  }

  Widget _failureInjection(FailureInjectionConfig c) {
    return _intField(
      label: 'writeCount',
      value: c.writeCount,
      onChanged: (v) => widget.onChanged(FailureInjectionConfig(writeCount: v)),
    );
  }

  Widget _mixedOps(MixedOpsConfig c) {
    return _intField(
      label: 'iterations',
      value: c.iterations,
      onChanged: (v) => widget.onChanged(MixedOpsConfig(iterations: v)),
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
          onChanged: (v) => widget.onChanged(BurstWriteConfig(
            count: v,
            payloadBytes: c.payloadBytes,
            withResponse: c.withResponse,
          )),
        ),
        _intField(
          label: 'bytes',
          value: c.payloadBytes,
          onChanged: (v) => widget.onChanged(BurstWriteConfig(
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
              onChanged: widget.enabled
                  ? (v) => widget.onChanged(BurstWriteConfig(
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

  Widget _mtuProbe(MtuProbeConfig c) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _intField(
          label: 'requestedMtu',
          value: c.requestedMtu,
          onChanged: (v) => widget.onChanged(MtuProbeConfig(
            requestedMtu: v,
            payloadBytes: c.payloadBytes,
          )),
        ),
        _intField(
          label: 'payloadBytes',
          value: c.payloadBytes,
          onChanged: (v) => widget.onChanged(MtuProbeConfig(
            requestedMtu: c.requestedMtu,
            payloadBytes: v,
          )),
        ),
      ],
    );
  }

  Widget _notifThroughput(NotificationThroughputConfig c) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _intField(
          label: 'count',
          value: c.count,
          onChanged: (v) => widget.onChanged(NotificationThroughputConfig(
            count: v,
            payloadBytes: c.payloadBytes,
          )),
        ),
        _intField(
          label: 'payloadBytes',
          value: c.payloadBytes,
          onChanged: (v) => widget.onChanged(NotificationThroughputConfig(
            count: c.count,
            payloadBytes: v,
          )),
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
        enabled: widget.enabled,
        controller: _controllerFor(label, value),
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
