import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../domain/stress_test_config.dart';

const _kUuidBg = Color(0xFFF0F4F7);
const _kDark = Color(0xFF2C3437);
const _kMid = Color(0xFF596064);

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
    return Text(
      'Config form for ${c.runtimeType} not implemented yet',
      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }

  Widget _soak(SoakConfig c) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _intField(
            label: 'DUR (S)',
            value: c.duration.inSeconds,
            onChanged:
                (v) => widget.onChanged(
                  SoakConfig(
                    duration: Duration(seconds: v),
                    interval: c.interval,
                    payloadBytes: c.payloadBytes,
                  ),
                ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _intField(
            label: 'INT (MS)',
            value: c.interval.inMilliseconds,
            onChanged:
                (v) => widget.onChanged(
                  SoakConfig(
                    duration: c.duration,
                    interval: Duration(milliseconds: v),
                    payloadBytes: c.payloadBytes,
                  ),
                ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _intField(
            label: 'BYTES',
            value: c.payloadBytes,
            onChanged:
                (v) => widget.onChanged(
                  SoakConfig(
                    duration: c.duration,
                    interval: c.interval,
                    payloadBytes: v,
                  ),
                ),
          ),
        ),
      ],
    );
  }

  Widget _timeoutProbe(TimeoutProbeConfig c) {
    return _intField(
      label: 'DELAY PAST TIMEOUT (MS)',
      value: c.delayPastTimeout.inSeconds,
      onChanged:
          (v) => widget.onChanged(
            TimeoutProbeConfig(delayPastTimeout: Duration(seconds: v)),
          ),
    );
  }

  Widget _failureInjection(FailureInjectionConfig c) {
    return _intField(
      label: 'WRITE COUNT',
      value: c.writeCount,
      onChanged: (v) => widget.onChanged(FailureInjectionConfig(writeCount: v)),
    );
  }

  Widget _mixedOps(MixedOpsConfig c) {
    return _intField(
      label: 'ITERATIONS',
      value: c.iterations,
      onChanged: (v) => widget.onChanged(MixedOpsConfig(iterations: v)),
    );
  }

  Widget _burst(BurstWriteConfig c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _intField(
                label: 'COUNT',
                value: c.count,
                onChanged:
                    (v) => widget.onChanged(
                      BurstWriteConfig(
                        count: v,
                        payloadBytes: c.payloadBytes,
                        withResponse: c.withResponse,
                      ),
                    ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _intField(
                label: 'BYTES',
                value: c.payloadBytes,
                onChanged:
                    (v) => widget.onChanged(
                      BurstWriteConfig(
                        count: c.count,
                        payloadBytes: v,
                        withResponse: c.withResponse,
                      ),
                    ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Row(
            children: [
              Checkbox(
                value: c.withResponse,
                onChanged:
                    widget.enabled
                        ? (v) => widget.onChanged(
                          BurstWriteConfig(
                            count: c.count,
                            payloadBytes: c.payloadBytes,
                            withResponse: v ?? true,
                          ),
                        )
                        : null,
              ),
              const SizedBox(width: 4),
              Text(
                'withResponse',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: _kMid,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _mtuProbe(MtuProbeConfig c) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _intField(
            label: 'REQUESTED MTU',
            value: c.requestedMtu,
            onChanged:
                (v) => widget.onChanged(
                  MtuProbeConfig(requestedMtu: v, payloadBytes: c.payloadBytes),
                ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _intField(
            label: 'PAYLOAD BYTES',
            value: c.payloadBytes,
            onChanged:
                (v) => widget.onChanged(
                  MtuProbeConfig(requestedMtu: c.requestedMtu, payloadBytes: v),
                ),
          ),
        ),
      ],
    );
  }

  Widget _notifThroughput(NotificationThroughputConfig c) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _intField(
            label: 'COUNT',
            value: c.count,
            onChanged:
                (v) => widget.onChanged(
                  NotificationThroughputConfig(
                    count: v,
                    payloadBytes: c.payloadBytes,
                  ),
                ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _intField(
            label: 'PAYLOAD BYTES',
            value: c.payloadBytes,
            onChanged:
                (v) => widget.onChanged(
                  NotificationThroughputConfig(count: c.count, payloadBytes: v),
                ),
          ),
        ),
      ],
    );
  }

  Widget _intField({
    required String label,
    required int value,
    required ValueChanged<int> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: _kMid,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: _kUuidBg,
            borderRadius: BorderRadius.circular(16),
          ),
          child: TextField(
            enabled: widget.enabled,
            controller: _controllerFor(label, value),
            decoration: const InputDecoration.collapsed(hintText: null),
            keyboardType: TextInputType.number,
            style: GoogleFonts.manrope(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: _kDark,
            ),
            // Use onChanged (commits per-keystroke) rather than onSubmitted:
            // iOS's number keyboard has no Done / action button, so
            // onSubmitted never fires there and typed values would never
            // save. The screen-level keyboard-dismiss handler (see
            // stress_tests_screen.dart) closes the keyboard via tap-outside
            // or the Done bar.
            onChanged: (s) {
              final parsed = int.tryParse(s);
              if (parsed != null && parsed > 0) onChanged(parsed);
            },
          ),
        ),
      ],
    );
  }
}
