import 'package:bluey_guards/gates.dart';
import 'package:test/test.dart';

const _report =
    'SF:lib/a.dart\nDA:1,1\nDA:2,0\nLF:2\nLH:1\nend_of_record\n'
    'SF:lib/b.dart\nLF:8\nLH:8\nend_of_record\n';

void main() {
  group('a report of two files', () {
    test('sums the lines found and hit across every file', () {
      // arrange
      const report = _report;

      // act
      final coverage = LineCoverage.parse(report);

      // assert
      expect(coverage.found, 10);
      expect(coverage.hit, 9);
      expect(coverage.percent, 90.0);
    });

    test('names the files it measured', () {
      // arrange
      const report = _report;

      // act
      final coverage = LineCoverage.parse(report);

      // assert
      expect(coverage.files, {'lib/a.dart', 'lib/b.dart'});
    });

    test('meets a floor it reaches and not one above it', () {
      // arrange
      final coverage = LineCoverage.parse(_report);

      // act
      final reachesNinety = coverage.meets(90);
      final reachesAboveNinety = coverage.meets(90.1);

      // assert
      expect(reachesNinety, isTrue);
      expect(reachesAboveNinety, isFalse);
    });
  });

  group('a report with no lines', () {
    test('meets no floor, not even zero', () {
      // arrange
      const report = '';

      // act
      final coverage = LineCoverage.parse(report);

      // assert
      expect(coverage.percent, 0);
      expect(coverage.meets(0), isFalse);
    });
  });
}
