import 'dart:collection';

import '../domain/radio_scan_input.dart';

/// Takes the radio scan's inputs one at a time, and runs each decision that
/// reads the radio scan only once every input queued before it has been
/// stepped, so a call made from inside a step reads what the queued steps
/// leave and never what they are about to change.
final class ScanTurns {
  ScanTurns(this._step);

  final void Function(RadioScanInput input) _step;
  final Queue<RadioScanInput> _inputs = Queue<RadioScanInput>();
  final Queue<void Function()> _decisions = Queue<void Function()>();
  bool _taking = false;

  /// Steps [input] now, or after the step in progress and those queued.
  void feed(RadioScanInput input) {
    _inputs.add(input);
    _take();
  }

  /// Runs [decision] now, or once every input queued so far has been
  /// stepped; inputs it feeds are stepped before the next decision.
  void decide(void Function() decision) {
    _decisions.add(decision);
    _take();
  }

  void _take() {
    if (_taking) return;
    _taking = true;
    try {
      while (_inputs.isNotEmpty || _decisions.isNotEmpty) {
        if (_inputs.isNotEmpty) {
          _step(_inputs.removeFirst());
        } else {
          _decisions.removeFirst()();
        }
      }
    } finally {
      _taking = false;
    }
  }
}
