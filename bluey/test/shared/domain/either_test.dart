import 'package:bluey/src/shared/domain/either.dart';
import 'package:bluey/src/shared/domain/failure.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Refused implements Failure {
  const _Refused();
  @override
  String get message => 'refused';
}

final class _Lost implements Failure {
  const _Lost();
  @override
  String get message => 'lost';
}

Either<_Refused, int> _answers(int value) => Right(value);
Either<_Refused, int> _refuses() => const Left(_Refused());
String _read(Either<Failure, Object> either) =>
    either.fold((failure) => failure.message, (value) => '$value');

void main() {
  group('fold', () {
    test('answers the right value through onRight', () {
      // arrange
      final either = _answers(1);

      // act
      final read = _read(either);

      // assert
      expect(read, '1');
    });

    test('answers the left value through onLeft', () {
      // arrange
      final either = _refuses();

      // act
      final read = _read(either);

      // assert
      expect(read, 'refused');
    });
  });

  group('map', () {
    test('transforms a right value', () {
      // arrange
      final either = _answers(1);

      // act
      final mapped = either.map((value) => value + 1);

      // assert
      expect(mapped, const Right<_Refused, int>(2));
    });

    test('leaves a left as it is', () {
      // arrange
      final either = _refuses();

      // act
      final mapped = either.map((value) => value + 1);

      // assert
      expect(_read(mapped), 'refused');
    });
  });

  group('flatMap', () {
    test('hands a right value to the next step', () {
      // arrange
      final either = _answers(1);

      // act
      final result = either.flatMap((value) => _answers(value + 1));

      // assert
      expect(result, const Right<_Refused, int>(2));
    });

    test('does not run the next step after a left', () {
      // arrange
      var ran = false;

      // act
      final result = _refuses().flatMap((value) {
        ran = true;
        return _answers(value);
      });

      // assert
      expect(ran, isFalse);
      expect(_read(result), 'refused');
    });

    test(
      'lets the next step answer another failure once the first is seen as a Failure',
      () {
        // arrange
        final Either<Failure, int> widened = _answers(1);

        // act
        final result = widened.flatMap<String>((_) => const Left(_Lost()));

        // assert
        expect(_read(result), 'lost');
      },
    );
  });

  group('equality', () {
    test('two lefts of one value are equal whatever their type arguments', () {
      // arrange
      const first = Left<String, int>('a');
      const second = Left<Object, num>('a');

      // act
      final hashes = [first.hashCode, second.hashCode];

      // assert
      expect(first, second);
      expect(hashes[0], hashes[1]);
    });

    test('a left and a right of one value differ', () {
      // arrange
      const left = Left<String, String>('a');
      const right = Right<String, String>('a');

      // act
      final equal = left == right;

      // assert
      expect(equal, isFalse);
    });

    test('each prints its side and its value', () {
      // arrange
      const left = Left<String, int>('a');
      const right = Right<String, int>(1);

      // act
      final printed = ['$left', '$right'];

      // assert
      expect(printed, ['Left(a)', 'Right(1)']);
    });
  });
}
