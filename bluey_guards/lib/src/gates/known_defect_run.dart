import 'dart:convert';

/// The verdict on one run of the known-defect tests, read from the JSON
/// reporter of `flutter test`, so CI fails when a defect is fixed without
/// its test moving into the normal suite, and when a known defect stops
/// running and so could be retired without anyone noticing.
final class KnownDefectRun {
  KnownDefectRun._({
    required this.stillFailing,
    required this.nowPassing,
    required this.notRun,
    required this.finished,
  });

  /// Reads the reporter's events, one per line, judging each test by how it
  /// finished. A line that is not a JSON object is passed over, so whatever
  /// the tool prints around its events does not spoil the verdict.
  factory KnownDefectRun.parse(Iterable<String> lines) {
    final names = <Object, String>{};
    final outcomes = <Object, _Outcome>{};
    var finished = false;
    for (final event in lines.map(_eventOf).whereType<Map<String, Object?>>()) {
      switch (event) {
        case {'type': 'done'}:
          finished = true;
        case {
          'type': 'testStart',
          'test': {'id': final Object id, 'name': final String name},
        }:
          names[id] = name;
        case {
          'type': 'testDone',
          'testID': final Object id,
          'result': final String result,
        }:
          outcomes[id] = _Outcome(result, skipped: event['skipped'] == true);
      }
    }
    final stillFailing = <String>[];
    final nowPassing = <String>[];
    final notRun = <String>[];
    names.forEach((id, name) {
      final outcome = outcomes[id];
      if (_isMadeByTheRunner(name)) {
        if (outcome?.result != 'success') notRun.add(name);
      } else if (outcome == null || outcome.skipped) {
        notRun.add(name);
      } else if (outcome.result == 'success') {
        nowPassing.add(name);
      } else {
        stillFailing.add(name);
      }
    });
    return KnownDefectRun._(
      stillFailing: List.unmodifiable(stillFailing),
      nowPassing: List.unmodifiable(nowPassing),
      notRun: List.unmodifiable(notRun),
      finished: finished,
    );
  }

  /// The known defects that still fail, as they should, in the run's order.
  final List<String> stillFailing;

  /// The known defects that pass: each is fixed, and its test belongs in the
  /// normal suite.
  final List<String> nowPassing;

  /// The tests that did not run to a result, and the runner's own steps
  /// (loading a file, a `setUpAll` or `tearDownAll`) that failed and so kept
  /// known defects from running.
  final List<String> notRun;

  /// Whether the reporter sent its last event. A log cut short, by a killed
  /// process or a full disk, names only the tests that started, so the
  /// known defects after the cut would otherwise go unseen.
  final bool finished;

  /// Whether the run is what the gate expects: it finished, every known
  /// defect ran and failed, and at least one did.
  bool get holds =>
      finished &&
      nowPassing.isEmpty &&
      notRun.isEmpty &&
      stillFailing.isNotEmpty;

  /// The verdict in words, naming each test that fails the gate and what to
  /// do about it.
  String describe() {
    if (stillFailing.isEmpty && nowPassing.isEmpty && notRun.isEmpty) {
      return 'Known defects: the run produced no result.\n';
    }
    final text = StringBuffer(
      'Known defects: ${stillFailing.length} still failing, '
      '${nowPassing.length} now passing, ${notRun.length} not run.\n',
    );
    if (!finished) {
      text.writeln(
        'The run did not finish: the reporter never sent its last event, so '
        'a known defect that never started is not counted. Fix what stopped '
        'the run.',
      );
    }
    _section(
      text,
      'Now passing. The defect is fixed: move its test into the normal '
      'suite, in the commit that fixes it:',
      nowPassing,
    );
    _section(
      text,
      'Not run. A known defect has to run and fail. Fix what stops it:',
      notRun,
    );
    return text.toString();
  }
}

final class _Outcome {
  _Outcome(this.result, {required this.skipped});

  final String result;
  final bool skipped;
}

Map<String, Object?>? _eventOf(String line) {
  try {
    final decoded = jsonDecode(line);
    return decoded is Map<String, Object?> ? decoded : null;
  } on FormatException {
    return null;
  }
}

bool _isMadeByTheRunner(String name) =>
    name.startsWith('loading ') ||
    name.endsWith('(setUpAll)') ||
    name.endsWith('(tearDownAll)');

void _section(StringBuffer text, String heading, List<String> names) {
  if (names.isEmpty) return;
  text.writeln(heading);
  for (final name in names) {
    text.writeln('  $name');
  }
}
