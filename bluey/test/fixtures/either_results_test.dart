import 'dart:async';

import 'package:bluey/src/shared/domain/either.dart';
import 'package:flutter_test/flutter_test.dart';

import 'either_results.dart';

void main() {
  group('rightOf', () {
    test('answers the value of a success', () {
      // arrange
      const answer = Right<String, int>(7);

      // act
      final value = rightOf(answer);

      // assert
      expect(value, 7);
    });

    test('fails the test on a failure', () {
      // arrange
      const answer = Left<String, int>('refused');

      // act
      int read() => rightOf(answer);

      // assert
      expect(read, throwsA(isA<TestFailure>()));
    });
  });

  group('resultOf', () {
    test('answers the value of a future that has completed', () {
      fakeAsync((async) {
        // arrange
        final future = Future<int>.delayed(const Duration(seconds: 1), () => 3);

        // act
        async.elapse(const Duration(seconds: 1));

        // assert
        expect(resultOf(future), 3);
      });
    });

    test('fails the test for a future still in flight', () {
      fakeAsync((async) {
        // arrange
        final future = Completer<int>().future;

        // act
        int read() => resultOf(future);

        // assert
        expect(read, throwsA(isA<TestFailure>()));
      });
    });

    test('fails the test outside this file\'s fakeAsync', () {
      // arrange
      final future = Future<int>.value(3);

      // act
      int read() => resultOf(future);

      // assert
      expect(read, throwsA(isA<TestFailure>()));
    });
  });
}
