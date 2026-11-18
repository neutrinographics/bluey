import 'dart:async';

import 'package:bluey/src/shared/domain/either.dart';
import 'package:fake_async/fake_async.dart' as fake_async;
import 'package:flutter_test/flutter_test.dart';

export 'package:fake_async/fake_async.dart' hide fakeAsync;

const _driver = #eitherResultsFakeAsync;

/// The value of a successful [answer]; a failure fails the test, naming it.
T rightOf<T>(Either<Object?, T> answer) => answer.fold(
  (failure) => fail('Expected a success, but the answer was Left($failure).'),
  (value) => value,
);

/// `package:fake_async`'s `fakeAsync`, which also lets [resultOf] read the
/// futures the test made: a listener added to a future that has already
/// completed only hears it on a later microtask, which only the `FakeAsync`
/// driving the test can run.
T fakeAsync<T>(
  T Function(fake_async.FakeAsync async) callback, {
  DateTime? initialTime,
}) => fake_async.fakeAsync(
  (async) => runZoned(() => callback(async), zoneValues: {_driver: async}),
  initialTime: initialTime,
);

/// The value of [future], which must have completed by the time virtual time
/// reached now; one still in flight fails the test, so a test cannot pass by
/// reading an answer that has not arrived.
///
/// Call it inside this file's [fakeAsync].
T resultOf<T>(Future<T> future) {
  final driver = Zone.current[_driver] as fake_async.FakeAsync?;
  if (driver == null) {
    fail(
      'resultOf runs inside the fakeAsync of test/fixtures/either_results.dart.',
    );
  }
  late T value;
  var completed = false;
  Object? error;
  future.then(
    (answer) {
      value = answer;
      completed = true;
    },
    onError: (Object failure) {
      error = failure;
    },
  );
  driver.flushMicrotasks();
  if (error != null) fail('The future failed with $error.');
  if (!completed) fail('The future has not completed yet.');
  return value;
}
