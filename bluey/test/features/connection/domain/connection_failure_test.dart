import 'package:bluey/src/features/connection/domain/connection_failure.dart';
import 'package:bluey/src/features/connection/domain/link_end.dart';
import 'package:bluey/src/shared/domain/failure.dart';
import 'package:flutter_test/flutter_test.dart';

/// Names the subtype, so the test fails to compile when the family gains a
/// member this list does not name.
String _kindOf(ConnectionFailure failure) => switch (failure) {
  ConnectFailed() => 'connect failed',
  LinkHadEnded() => 'link ended',
  RadioUnavailable() => 'radio unavailable',
  PermissionMissing() => 'permission missing',
  OperationTimedOut() => 'operation timed out',
  OperationRejected() => 'operation rejected',
  UnexpectedPlatformFailure() => 'unexpected platform failure',
};

void main() {
  final cause = StateError('platform said no');

  final sameValues = <String, (ConnectionFailure, ConnectionFailure)>{
    'ConnectFailed': (
      const ConnectFailed(ConnectFailureReason.timeout),
      const ConnectFailed(ConnectFailureReason.timeout),
    ),
    'LinkHadEnded': (
      const LinkHadEnded(EndedByDrop()),
      const LinkHadEnded(EndedByDrop()),
    ),
    'RadioUnavailable': (const RadioUnavailable(), const RadioUnavailable()),
    'PermissionMissing': (
      const PermissionMissing('bluetoothConnect'),
      const PermissionMissing('bluetoothConnect'),
    ),
    'OperationTimedOut': (
      const OperationTimedOut('requestMtu'),
      const OperationTimedOut('requestMtu'),
    ),
    'OperationRejected': (
      const OperationRejected('readRssi', 133),
      const OperationRejected('readRssi', 133),
    ),
    'UnexpectedPlatformFailure': (
      UnexpectedPlatformFailure('boom', code: 'E1', cause: cause),
      UnexpectedPlatformFailure('boom', code: 'E1', cause: cause),
    ),
  };

  final otherValues = <String, (ConnectionFailure, ConnectionFailure)>{
    'ConnectFailed': (
      const ConnectFailed(ConnectFailureReason.timeout),
      const ConnectFailed(ConnectFailureReason.deviceNotFound),
    ),
    'LinkHadEnded': (
      const LinkHadEnded(EndedByDrop()),
      const LinkHadEnded(EndedOnRequest()),
    ),
    'RadioUnavailable': (
      const RadioUnavailable(),
      const OperationTimedOut('x'),
    ),
    'PermissionMissing': (
      const PermissionMissing('bluetoothConnect'),
      const PermissionMissing('bluetoothScan'),
    ),
    'OperationTimedOut': (
      const OperationTimedOut('requestMtu'),
      const OperationTimedOut('readRssi'),
    ),
    'OperationRejected by operation': (
      const OperationRejected('readRssi', 133),
      const OperationRejected('requestMtu', 133),
    ),
    'OperationRejected by status': (
      const OperationRejected('readRssi', 133),
      const OperationRejected('readRssi', 8),
    ),
    'UnexpectedPlatformFailure by detail': (
      UnexpectedPlatformFailure('boom', code: 'E1', cause: cause),
      UnexpectedPlatformFailure('bang', code: 'E1', cause: cause),
    ),
    'UnexpectedPlatformFailure by code': (
      UnexpectedPlatformFailure('boom', code: 'E1', cause: cause),
      UnexpectedPlatformFailure('boom', code: 'E2', cause: cause),
    ),
    'UnexpectedPlatformFailure by cause': (
      UnexpectedPlatformFailure('boom', code: 'E1', cause: cause),
      const UnexpectedPlatformFailure('boom', code: 'E1'),
    ),
  };

  group('ConnectionFailure equality', () {
    for (final MapEntry(key: name, value: (first, second))
        in sameValues.entries) {
      test('$name equals another of the same values', () {
        // arrange
        final failure = first;

        // act
        final equal = failure == second;

        // assert
        expect(equal, isTrue);
        expect(failure.hashCode, second.hashCode);
      });
    }

    for (final MapEntry(key: name, value: (first, second))
        in otherValues.entries) {
      test('$name differs from one of other values', () {
        // arrange
        final failure = first;

        // act
        final equal = failure == second;

        // assert
        expect(equal, isFalse);
      });
    }
  });

  group('ConnectionFailure message', () {
    final named = <ConnectionFailure, String>{
      for (final reason in ConnectFailureReason.values)
        ConnectFailed(reason): reason.name,
      const LinkHadEnded(EndedOnRequest()): 'requested',
      const LinkHadEnded(EndedByDrop()): 'lost',
      const LinkHadEnded(EndedByRadioOutage(RadioOutage.off)): 'off',
      const RadioUnavailable(): 'radio',
      const PermissionMissing('bluetoothConnect'): 'bluetoothConnect',
      const OperationTimedOut('requestMtu'): 'requestMtu',
      const OperationRejected('readRssi', 133): '133',
      const UnexpectedPlatformFailure('boom'): 'boom',
      const UnexpectedPlatformFailure('boom', code: 'E1'): 'E1',
    };

    for (final MapEntry(key: failure, value: word) in named.entries) {
      test('${_kindOf(failure)} names "$word" in a sentence', () {
        // arrange
        final Failure asFailure = failure;

        // act
        final message = asFailure.message;

        // assert
        expect(message, contains(word));
        expect(message, matches(RegExp(r'^[A-Z].*\.$')));
      });
    }

    test('a rejected operation names its operation and its status', () {
      // arrange
      const failure = OperationRejected('readRssi', 133);

      // act
      final message = failure.message;

      // assert
      expect(message, allOf(contains('readRssi'), contains('133')));
    });
  });

  group('ConnectionFailure description', () {
    test('toString is the message, so a log line reads as a sentence', () {
      // arrange
      const failure = OperationTimedOut('requestMtu');

      // act
      final text = failure.toString();

      // assert
      expect(text, failure.message);
    });
  });
}
