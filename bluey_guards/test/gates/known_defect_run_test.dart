import 'package:bluey_guards/gates.dart';
import 'package:test/test.dart';

const _loading = 'loading test/known_defects/domain_known_defects_test.dart';

String _start(int id, String name) =>
    '{"test":{"id":$id,"name":"$name"},"type":"testStart"}';

String _done(
  int id,
  String result, {
  bool skipped = false,
  bool hidden = false,
}) =>
    '{"testID":$id,"result":"$result","skipped":$skipped,"hidden":$hidden,'
    '"type":"testDone"}';

String _error(int id, String message) =>
    '{"testID":$id,"error":"$message","stackTrace":"","isFailure":true,'
    '"type":"error"}';

/// The reporter's last event, which a run that finished always ends with,
/// whatever its tests did.
const _finished = '{"success":false,"type":"done","time":1200}';

/// The known defects the runs below are expected to hold.
const _roster = ['H2 probes', 'H3 finalise'];

void main() {
  group('parse', () {
    test(
      'holds while every known defect fails, by an expectation or by an error',
      () {
        // arrange
        final lines = [
          _start(1, _loading),
          _done(1, 'success', hidden: true),
          _start(2, 'H2 probes'),
          _done(2, 'failure'),
          _start(3, 'H3 finalise'),
          _done(3, 'error'),
          _finished,
        ];

        // act
        final run = KnownDefectRun.parse(lines, roster: _roster);

        // assert
        expect(run.stillFailing, ['H2 probes', 'H3 finalise']);
        expect(run.holds, isTrue);
      },
    );

    test('does not hold when a known defect passes', () {
      // arrange
      final lines = [
        _start(2, 'H2 probes'),
        _done(2, 'success'),
        _start(3, 'H3 finalise'),
        _done(3, 'failure'),
      ];

      // act
      final run = KnownDefectRun.parse(lines, roster: _roster);

      // assert
      expect(run.nowPassing, ['H2 probes']);
      expect(run.holds, isFalse);
    });

    test('does not hold when the suite no longer loads', () {
      // arrange
      final lines = [_start(1, _loading), _done(1, 'error')];

      // act
      final run = KnownDefectRun.parse(lines, roster: _roster);

      // assert
      expect(run.notRun, [_loading]);
      expect(run.holds, isFalse);
    });

    test('does not hold when a setUpAll fails', () {
      // arrange
      final lines = [
        _start(2, 'H2 (setUpAll)'),
        _done(2, 'error'),
        _start(3, 'H3 finalise'),
        _done(3, 'failure'),
      ];

      // act
      final run = KnownDefectRun.parse(lines, roster: _roster);

      // assert
      expect(run.notRun, ['H2 (setUpAll)']);
      expect(run.holds, isFalse);
    });

    test('does not hold when a test was skipped or never finished', () {
      // arrange
      final lines = [
        _start(2, 'H2 probes'),
        _done(2, 'success', skipped: true),
        _start(3, 'H3 finalise'),
      ];

      // act
      final run = KnownDefectRun.parse(lines, roster: _roster);

      // assert
      expect(run.notRun, ['H2 probes', 'H3 finalise']);
      expect(run.nowPassing, isEmpty);
      expect(run.holds, isFalse);
    });

    test('does not hold when nothing ran', () {
      // act
      final run = KnownDefectRun.parse(const [], roster: const []);

      // assert
      expect(run.holds, isFalse);
      expect(run.describe(), 'Known defects: the run produced no result.\n');
    });

    test('does not hold when the log stops before the run finished', () {
      // arrange
      final lines = [
        _start(1, _loading),
        _done(1, 'success', hidden: true),
        _start(2, 'H2 probes'),
        _done(2, 'failure'),
        _start(3, 'H3 finalise'),
        _done(3, 'error'),
      ];

      // act
      final run = KnownDefectRun.parse(lines, roster: _roster);

      // assert
      expect(run.stillFailing, ['H2 probes', 'H3 finalise']);
      expect(run.finished, isFalse);
      expect(run.holds, isFalse);
    });

    test('holds when the run finished, whatever the reporter says of its '
        'success', () {
      // arrange
      final lines = [
        _start(2, 'H2 probes'),
        _done(2, 'failure'),
        '{"success":true,"type":"done","time":900}',
      ];

      // act
      final run = KnownDefectRun.parse(lines, roster: ['H2 probes']);

      // assert
      expect(run.finished, isTrue);
      expect(run.holds, isTrue);
    });

    test('passes over lines that are not events', () {
      // arrange
      final lines = [
        'Woah! You appear to be trying to run flutter as root.',
        '',
        '[1, 2]',
        _start(2, 'H2 probes'),
        _done(2, 'failure'),
        _finished,
      ];

      // act
      final run = KnownDefectRun.parse(lines, roster: ['H2 probes']);

      // assert
      expect(run.stillFailing, ['H2 probes']);
      expect(run.holds, isTrue);
    });

    test('does not hold when a name on the roster is not in the run', () {
      // arrange
      final lines = [_start(2, 'H2 probes'), _done(2, 'failure'), _finished];

      // act
      final run = KnownDefectRun.parse(lines, roster: _roster);

      // assert
      expect(run.absent, ['H3 finalise']);
      expect(run.holds, isFalse);
    });

    test('does not hold when a test in the run is not on the roster', () {
      // arrange
      final lines = [
        _start(1, _loading),
        _done(1, 'success', hidden: true),
        _start(2, 'H2 probes'),
        _done(2, 'failure'),
        _start(3, 'H3 finalise'),
        _done(3, 'failure'),
        _start(4, 'H9 unheard of'),
        _done(4, 'failure'),
        _finished,
      ];

      // act
      final run = KnownDefectRun.parse(lines, roster: _roster);

      // assert
      expect(run.unlisted, ['H9 unheard of']);
      expect(run.absent, isEmpty);
      expect(run.holds, isFalse);
    });

    test('keeps the first line of the first error of each failing test', () {
      // arrange
      final lines = [
        _start(2, 'H2 probes'),
        _error(2, 'Expected: true\\n  Actual: <false>\\n'),
        _error(2, 'a second error'),
        _done(2, 'failure'),
        _start(3, 'H3 finalise'),
        _done(3, 'error'),
        _finished,
      ];

      // act
      final run = KnownDefectRun.parse(lines, roster: _roster);

      // assert
      expect(run.reasons, {'H2 probes': 'Expected: true'});
    });
  });

  group('describe', () {
    test('says that a run which did not finish proves nothing', () {
      // arrange
      final run = KnownDefectRun.parse(
        roster: ['H2 probes'],
        [_start(1, 'H2 probes'), _done(1, 'failure')],
      );

      // act
      final description = run.describe();

      // assert
      expect(
        description,
        'Known defects: 1 still failing, 0 now passing, 0 not run.\n'
        'Still failing, as each should, with its first error line:\n'
        '  H2 probes\n'
        '    (no error was reported)\n'
        'The run did not finish: the reporter never sent its last event, so '
        'a known defect that never started is not counted. Fix what stopped '
        'the run.\n',
      );
    });

    test(
      'counts each kind and says what to do about the two that fail the gate',
      () {
        // arrange
        final run = KnownDefectRun.parse(roster: _roster, [
          _start(1, 'H2 probes'),
          _error(1, 'NoSuchMethodError: no method named probe'),
          _done(1, 'failure'),
          _start(2, 'H3 finalise'),
          _done(2, 'success'),
          _start(3, _loading),
          _done(3, 'error'),
          _finished,
        ]);

        // act
        final description = run.describe();

        // assert
        expect(
          description,
          'Known defects: 1 still failing, 1 now passing, 1 not run.\n'
          'Still failing, as each should, with its first error line:\n'
          '  H2 probes\n'
          '    NoSuchMethodError: no method named probe\n'
          'Now passing. The defect is fixed: move its test into the normal '
          'suite, in the commit that fixes it:\n'
          '  H3 finalise\n'
          'Not run. A known defect has to run and fail. Fix what stops it:\n'
          '  $_loading\n',
        );
      },
    );

    test('names what the roster and the run disagree on, and what to do', () {
      // arrange
      final run = KnownDefectRun.parse(roster: _roster, [
        _start(2, 'H2 probes'),
        _error(2, 'Expected: true'),
        _done(2, 'failure'),
        _start(4, 'H9 unheard of'),
        _error(4, 'Expected: true'),
        _done(4, 'failure'),
        _finished,
      ]);

      // act
      final description = run.describe();

      // assert
      expect(
        description,
        'Known defects: 2 still failing, 0 now passing, 0 not run.\n'
        'Still failing, as each should, with its first error line:\n'
        '  H2 probes\n'
        '    Expected: true\n'
        '  H9 unheard of\n'
        '    Expected: true\n'
        'On the roster but not in the run. A known defect leaves only with '
        'its fix, its name struck from the roster in the same commit; '
        'restore its test:\n'
        '  H3 finalise\n'
        'In the run but not on the roster, which only shrinks. Keep the '
        'name its test had, or prove a new defect in its slice\'s own '
        'suite:\n'
        '  H9 unheard of\n',
      );
    });
  });
}
