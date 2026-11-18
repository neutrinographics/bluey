import 'package:bluey/src/features/connection/domain/link_end.dart';
import 'package:flutter_test/flutter_test.dart';

LinkEnd _built(LinkEnd Function() build) => build();

void main() {
  group('LinkEnd equality', () {
    test('an end on request equals another end on request', () {
      // arrange
      final first = _built(EndedOnRequest.new);

      // act
      final second = _built(EndedOnRequest.new);

      // assert
      expect(first, second);
      expect(first.hashCode, second.hashCode);
    });

    test('an end by drop equals another end by drop', () {
      // arrange
      final first = _built(EndedByDrop.new);

      // act
      final second = _built(EndedByDrop.new);

      // assert
      expect(first, second);
      expect(first.hashCode, second.hashCode);
    });

    test('ends by the same radio outage are equal', () {
      // arrange
      final outage = RadioOutage.values.first;

      // act
      final first = EndedByRadioOutage(outage);
      final second = EndedByRadioOutage(outage);

      // assert
      expect(first, second);
      expect(first.hashCode, second.hashCode);
    });

    test('ends by different radio outages differ', () {
      // arrange
      const first = EndedByRadioOutage(RadioOutage.off);

      // act
      const second = EndedByRadioOutage(RadioOutage.unauthorized);

      // assert
      expect(first, isNot(second));
    });

    test('ends of different kinds differ', () {
      // arrange
      const ends = <LinkEnd>[
        EndedOnRequest(),
        EndedByDrop(),
        EndedByRadioOutage(RadioOutage.unsupported),
      ];

      // act
      final pairs = [
        for (final a in ends)
          for (final b in ends)
            if (!identical(a, b)) (a, b),
      ];

      // assert
      for (final (a, b) in pairs) {
        expect(a, isNot(b));
      }
    });
  });
}
