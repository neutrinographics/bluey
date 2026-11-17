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
        ];

        // act
        final run = KnownDefectRun.parse(lines);

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
      final run = KnownDefectRun.parse(lines);

      // assert
      expect(run.nowPassing, ['H2 probes']);
      expect(run.holds, isFalse);
    });

    test('does not hold when the suite no longer loads', () {
      // arrange
      final lines = [_start(1, _loading), _done(1, 'error')];

      // act
      final run = KnownDefectRun.parse(lines);

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
      final run = KnownDefectRun.parse(lines);

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
      final run = KnownDefectRun.parse(lines);

      // assert
      expect(run.notRun, ['H2 probes', 'H3 finalise']);
      expect(run.nowPassing, isEmpty);
      expect(run.holds, isFalse);
    });

    test('does not hold when nothing ran', () {
      // act
      final run = KnownDefectRun.parse(const []);

      // assert
      expect(run.holds, isFalse);
      expect(run.describe(), 'Known defects: the run produced no result.\n');
    });

    test('passes over lines that are not events', () {
      // arrange
      final lines = [
        'Woah! You appear to be trying to run flutter as root.',
        '',
        '[1, 2]',
        '{"type":"done","success":false}',
        _start(2, 'H2 probes'),
        _done(2, 'failure'),
      ];

      // act
      final run = KnownDefectRun.parse(lines);

      // assert
      expect(run.stillFailing, ['H2 probes']);
      expect(run.holds, isTrue);
    });
  });

  group('describe', () {
    test(
      'counts each kind and says what to do about the two that fail the gate',
      () {
        // arrange
        final run = KnownDefectRun.parse([
          _start(1, 'H2 probes'),
          _done(1, 'failure'),
          _start(2, 'H3 finalise'),
          _done(2, 'success'),
          _start(3, _loading),
          _done(3, 'error'),
        ]);

        // act
        final description = run.describe();

        // assert
        expect(
          description,
          'Known defects: 1 still failing, 1 now passing, 1 not run.\n'
          'Now passing. The defect is fixed: move its test into the normal '
          'suite, in the commit that fixes it:\n'
          '  H3 finalise\n'
          'Not run. A known defect has to run and fail. Fix what stops it:\n'
          '  $_loading\n',
        );
      },
    );
  });
}
