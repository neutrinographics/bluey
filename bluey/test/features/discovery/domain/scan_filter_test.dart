import 'package:bluey/src/features/discovery/domain/advertisement.dart';
import 'package:bluey/src/features/discovery/domain/scan_filter.dart';
import 'package:bluey/src/shared/domain/uuid.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final a = UUID.short(0x180D);
  final b = UUID.short(0x180F);
  final c = UUID.short(0x1810);

  Advertisement listing(List<UUID> services) => Advertisement(
    serviceUuids: services,
    serviceData: {},
    isConnectable: true,
  );

  group('of', () {
    test('null and an empty list ask for everything', () {
      // arrange
      const noServices = <UUID>[];

      // act
      final fromNull = ScanFilter.of(null);
      final fromEmpty = ScanFilter.of(noServices);

      // assert
      expect(fromNull, isA<Everything>());
      expect(fromEmpty, isA<Everything>());
    });

    test('a repeated service is one service', () {
      // arrange
      final repeated = [a, a];

      // act
      final filter = ScanFilter.of(repeated);

      // assert
      expect(filter, ScanFilter.of([a]));
      expect(filter.hashCode, ScanFilter.of([a]).hashCode);
    });

    test('keeps no reference to the iterable it was given', () {
      // arrange
      final services = [a];
      final filter = ScanFilter.of(services) as ServicesOnly;

      // act
      services.add(b);

      // assert
      expect(filter.services, {a});
      expect(() => filter.services.add(b), throwsUnsupportedError);
    });

    test('different services are different filters', () {
      // arrange
      final onlyA = ScanFilter.of([a]);

      // act
      final onlyB = ScanFilter.of([b]);

      // assert
      expect(onlyA, isNot(onlyB));
      expect(onlyA, isNot(const Everything()));
    });
  });

  group('union', () {
    test('everything with anything is everything, either way round', () {
      // arrange
      final some = ScanFilter.of([a]);

      // act
      final left = const Everything().union(some);
      final right = some.union(const Everything());

      // assert
      expect(left, const Everything());
      expect(right, const Everything());
    });

    test('two sets of services join', () {
      // arrange
      final onlyA = ScanFilter.of([a]);
      final onlyB = ScanFilter.of([b]);

      // act
      final joined = onlyA.union(onlyB);

      // assert
      expect(joined, ScanFilter.of([a, b]));
    });
  });

  group('covers', () {
    test('everything covers anything', () {
      // arrange
      final some = ScanFilter.of([a]);

      // act
      final coversSome = const Everything().covers(some);
      final coversEverything = const Everything().covers(const Everything());

      // assert
      expect(coversSome, isTrue);
      expect(coversEverything, isTrue);
    });

    test('a set covers a subset of itself and nothing else', () {
      // arrange
      final both = ScanFilter.of([a, b]);

      // act
      final coversSubset = both.covers(ScanFilter.of([a]));
      final coversItself = both.covers(both);
      final coversOther = both.covers(ScanFilter.of([c]));
      final coversPartlyOther = both.covers(ScanFilter.of([a, c]));
      final coversEverything = both.covers(const Everything());

      // assert
      expect(coversSubset, isTrue);
      expect(coversItself, isTrue);
      expect(coversOther, isFalse);
      expect(coversPartlyOther, isFalse);
      expect(coversEverything, isFalse);
    });
  });

  group('shows', () {
    test('everything shows any advertisement', () {
      // arrange
      final nothingListed = listing([]);

      // act
      final shown = const Everything().shows(nothingListed);

      // assert
      expect(shown, isTrue);
    });

    test('services show an advertisement that lists one of them', () {
      // arrange
      final filter = ScanFilter.of([a]);

      // act
      final shown = filter.shows(listing([a, b]));

      // assert
      expect(shown, isTrue);
    });

    test('services hide an advertisement that lists none of them', () {
      // arrange
      final filter = ScanFilter.of([a]);

      // act
      final shownOther = filter.shows(listing([c]));
      final shownEmpty = filter.shows(listing([]));

      // assert
      expect(shownOther, isFalse);
      expect(shownEmpty, isFalse);
    });
  });
}
