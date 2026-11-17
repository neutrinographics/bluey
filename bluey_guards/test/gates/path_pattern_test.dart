import 'package:bluey_guards/gates.dart';
import 'package:test/test.dart';

void main() {
  group('a path pattern', () {
    test('takes in every path under its folder', () {
      // arrange
      final pattern = PathPattern('lib/src/shared/domain');

      // act
      final taken = pattern.takesIn('lib/src/shared/domain/either.dart');

      // assert
      expect(taken, isTrue);
    });

    test('reads a star as any one folder', () {
      // arrange
      final pattern = PathPattern('lib/src/features/*/domain');

      // act
      final taken = [
        'lib/src/features/connection/domain/link.dart',
        'lib/src/features/peer/domain/value_objects/server_id.dart',
        'lib/src/features/connection/application/connect.dart',
        'lib/src/features/domain/a.dart',
      ].map(pattern.takesIn);

      // assert
      expect(taken, [true, true, false, false]);
    });

    test('takes in no path that only begins with its text', () {
      // arrange
      final pattern = PathPattern('lib/src/shared/domain');

      // act
      final taken = pattern.takesIn('lib/src/shared/domains/a.dart');

      // assert
      expect(taken, isFalse);
    });

    test('takes in no path above it', () {
      // arrange
      final pattern = PathPattern('lib/src/shared/domain');

      // act
      final taken = pattern.takesIn('lib/src/shared/a.dart');

      // assert
      expect(taken, isFalse);
    });
  });
}
