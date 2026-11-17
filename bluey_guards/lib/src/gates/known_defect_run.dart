import 'dart:convert';

/// The verdict on one run of the known-defect tests, read from the JSON
/// reporter of `flutter test` and judged against the package's roster of
/// the known defects it has, so CI fails when a defect is fixed without its
/// test moving into the normal suite, when a known defect stops running,
/// and when one is deleted or added without its roster saying so.
final class KnownDefectRun {
  KnownDefectRun._({
    required this.stillFailing,
    required this.reasons,
    required this.nowPassing,
    required this.notRun,
    required this.absent,
    required this.unlisted,
    required this.finished,
  });

  /// Reads the reporter's events, one per line, judging each test by how it
  /// finished, and compares the tests the run named with [roster], the full
  /// names of the known defects the package has. A line that is not a JSON
  /// object is passed over, so whatever the tool prints around its events
  /// does not spoil the verdict.
  factory KnownDefectRun.parse(
    Iterable<String> lines, {
    required List<String> roster,
  }) {
    final names = <Object, String>{};
    final outcomes = <Object, _Outcome>{};
    final firstErrors = <Object, String>{};
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
        case {
          'type': 'error',
          'testID': final Object id,
          'error': final String error,
        }:
          firstErrors.putIfAbsent(id, () => _firstLineOf(error));
      }
    }
    final stillFailing = <String>[];
    final reasons = <String, String>{};
    final nowPassing = <String>[];
    final notRun = <String>[];
    final named = <String>{};
    names.forEach((id, name) {
      final outcome = outcomes[id];
      if (_isMadeByTheRunner(name)) {
        if (outcome?.result != 'success') notRun.add(name);
        return;
      }
      named.add(name);
      if (outcome == null || outcome.skipped) {
        notRun.add(name);
      } else if (outcome.result == 'success') {
        nowPassing.add(name);
      } else {
        stillFailing.add(name);
        if (firstErrors[id] case final reason?) reasons[name] = reason;
      }
    });
    return KnownDefectRun._(
      stillFailing: List.unmodifiable(stillFailing),
      reasons: Map.unmodifiable(reasons),
      nowPassing: List.unmodifiable(nowPassing),
      notRun: List.unmodifiable(notRun),
      absent: List.unmodifiable(roster.where((name) => !named.contains(name))),
      unlisted: List.unmodifiable(
        named.where((name) => !roster.contains(name)),
      ),
      finished: finished,
    );
  }

  /// The known defects that still fail, as they should, in the run's order.
  final List<String> stillFailing;

  /// The first line of the first error each still-failing test reported,
  /// by its name, so the log shows that it fails for the defect its name
  /// gives and not for a changed fake or a typo. A test that reported none
  /// is not here.
  final Map<String, String> reasons;

  /// The known defects that pass: each is fixed, and its test belongs in the
  /// normal suite.
  final List<String> nowPassing;

  /// The tests that did not run to a result, and the runner's own steps
  /// (loading a file, a `setUpAll` or `tearDownAll`) that failed and so kept
  /// known defects from running.
  final List<String> notRun;

  /// The names on the roster that the run did not name: a known defect
  /// deleted, renamed or no longer reached.
  final List<String> absent;

  /// The tests the run named that the roster does not hold, in the run's
  /// order: a known defect added, or renamed, without its roster changing.
  final List<String> unlisted;

  /// Whether the reporter sent its last event. A log cut short, by a killed
  /// process or a full disk, names only the tests that started, so the
  /// known defects after the cut would otherwise go unseen.
  final bool finished;

  /// Whether the run is what the gate expects: it finished, it named
  /// exactly the roster's known defects, every one ran and failed, and at
  /// least one did.
  bool get holds =>
      finished &&
      nowPassing.isEmpty &&
      notRun.isEmpty &&
      absent.isEmpty &&
      unlisted.isEmpty &&
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
    if (stillFailing.isNotEmpty) {
      text.writeln('Still failing, as each should, with its first error line:');
      for (final name in stillFailing) {
        text
          ..writeln('  $name')
          ..writeln('    ${reasons[name] ?? '(no error was reported)'}');
      }
    }
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
    _section(
      text,
      'On the roster but not in the run. A known defect leaves only with its '
      'fix, its name struck from the roster in the same commit; restore its '
      'test:',
      absent,
    );
    _section(
      text,
      'In the run but not on the roster, which only shrinks. Keep the name '
      "its test had, or prove a new defect in its slice's own suite:",
      unlisted,
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

String _firstLineOf(String error) =>
    error
        .split('\n')
        .firstWhere((line) => line.trim().isNotEmpty, orElse: () => '')
        .trim();

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
