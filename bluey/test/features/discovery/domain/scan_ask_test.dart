import 'package:bluey/src/features/discovery/domain/scan_ask.dart';
import 'package:bluey/src/features/discovery/domain/scan_filter.dart';
import 'package:bluey/src/features/discovery/domain/scan_mode.dart';
import 'package:bluey/src/shared/domain/uuid.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final a = UUID.short(0x180D);
  final b = UUID.short(0x180F);
  final c = UUID.short(0x1810);

  ScanAsk ask(List<UUID> services, [ScanMode? mode]) =>
      ScanAsk(filter: ScanFilter.of(services), mode: mode);

  group('ScanAsk', () {
    test('equals an ask of the same filter, mode and time limit', () {
      // arrange
      const limit = Duration(seconds: 5);
      final one = ScanAsk(
        filter: ScanFilter.of([a]),
        mode: ScanMode.balanced,
        timeLimit: limit,
      );

      // act
      final same = ScanAsk(
        filter: ScanFilter.of([a]),
        mode: ScanMode.balanced,
        timeLimit: limit,
      );

      // assert
      expect(one, same);
      expect(one.hashCode, same.hashCode);
      expect(one, isNot(ScanAsk(filter: ScanFilter.of([a]))));
    });
  });

  group('ScanCoverage.of', () {
    test('joins the filters and takes the busiest stated mode', () {
      // arrange
      final asks = [
        ask([a]),
        ask([b], ScanMode.lowPower),
      ];

      // act
      final coverage = ScanCoverage.of(asks);

      // assert
      expect(
        coverage,
        ScanCoverage(filter: ScanFilter.of([a, b]), mode: ScanMode.lowPower),
      );
    });

    test('ranks low power below balanced below low latency', () {
      // arrange
      final asks = [
        ask([a], ScanMode.lowPower),
        ask([a], ScanMode.lowLatency),
        ask([a], ScanMode.balanced),
      ];

      // act
      final coverage = ScanCoverage.of(asks);

      // assert
      expect(coverage.mode, ScanMode.lowLatency);
    });

    test('asks that state no mode leave the coverage with none', () {
      // arrange
      final asks = [
        ask([a]),
        ask([b]),
      ];

      // act
      final coverage = ScanCoverage.of(asks);

      // assert
      expect(coverage.mode, isNull);
    });

    test('no asks is a state error, since coverage exists only while a '
        'scan is open', () {
      // arrange
      const none = <ScanAsk>[];

      // act
      void build() => ScanCoverage.of(none);

      // assert
      expect(build, throwsStateError);
    });

    test('a time limit never changes the coverage', () {
      // arrange
      final limited = ScanAsk(
        filter: ScanFilter.of([a]),
        timeLimit: const Duration(seconds: 3),
      );

      // act
      final coverage = ScanCoverage.of([limited]);

      // assert
      expect(
        coverage,
        ScanCoverage.of([
          ask([a]),
        ]),
      );
      expect(
        coverage.hashCode,
        ScanCoverage.of([
          ask([a]),
        ]).hashCode,
      );
    });
  });

  group('ScanCoverage.covers', () {
    final coverage = ScanCoverage.of([
      ask([a, b], ScanMode.balanced),
    ]);

    test('is true for an ask inside the filter that wants no mode', () {
      // act
      final covered = coverage.covers(ask([a]));

      // assert
      expect(covered, isTrue);
    });

    test('is false for a filter the coverage does not hold', () {
      // act
      final covered = coverage.covers(ask([c]));

      // assert
      expect(covered, isFalse);
    });

    test('is true for a mode no busier than the coverage, false above it', () {
      // act
      final lower = coverage.covers(ask([a], ScanMode.lowPower));
      final same = coverage.covers(ask([a], ScanMode.balanced));
      final busier = coverage.covers(ask([a], ScanMode.lowLatency));

      // assert
      expect(lower, isTrue);
      expect(same, isTrue);
      expect(busier, isFalse);
    });

    test('is false for a stated mode against a coverage with none', () {
      // arrange
      final unstated = ScanCoverage.of([
        ask([a]),
      ]);

      // act
      final covered = unstated.covers(ask([a], ScanMode.lowPower));

      // assert
      expect(covered, isFalse);
    });
  });

  group('ScanCoverage.widenedBy', () {
    test('an ask already covered answers an equal coverage', () {
      // arrange
      final coverage = ScanCoverage.of([
        ask([a, b], ScanMode.balanced),
      ]);

      // act
      final widened = coverage.widenedBy(ask([a], ScanMode.lowPower));

      // assert
      expect(widened, coverage);
    });

    test('an ask that is not covered widens the filter and the mode', () {
      // arrange
      final coverage = ScanCoverage.of([
        ask([a], ScanMode.lowPower),
      ]);

      // act
      final widened = coverage.widenedBy(ask([b], ScanMode.lowLatency));

      // assert
      expect(
        widened,
        ScanCoverage(filter: ScanFilter.of([a, b]), mode: ScanMode.lowLatency),
      );
    });

    test('a stated mode against a coverage with none gives the coverage '
        'that mode', () {
      // arrange
      final coverage = ScanCoverage.of([
        ask([a]),
      ]);

      // act
      final widened = coverage.widenedBy(ask([a], ScanMode.balanced));

      // assert
      expect(widened.mode, ScanMode.balanced);
    });
  });
}
