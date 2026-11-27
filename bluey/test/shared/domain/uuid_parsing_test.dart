import 'package:bluey/src/shared/domain/either.dart';
import 'package:bluey/src/shared/domain/uuid.dart';
import 'package:bluey/src/shared/domain/uuid_parsing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('uuidFrom', () {
    test('answers the same UUID the constructor builds, whatever the form', () {
      for (final raw in [
        '180d',
        '0000180d-0000-1000-8000-00805f9b34fb',
        '0000180D-0000-1000-8000-00805F9B34FB',
      ]) {
        // arrange
        final expected = raw.length == 4 ? UUID.short(0x180d) : UUID(raw);

        // act
        final parsed = uuidFrom(raw);

        // assert
        expect(parsed, Right<MalformedUuid, UUID>(expected), reason: raw);
      }
    });

    test(
      'answers a MalformedUuid naming the raw text when it is not a UUID',
      () {
        for (final raw in ['', 'xyz', '180', 'a' * 33]) {
          // arrange / act
          final parsed = uuidFrom(raw);

          // assert
          expect(parsed, Left<MalformedUuid, UUID>(MalformedUuid(raw)));
        }
      },
    );
  });
}
