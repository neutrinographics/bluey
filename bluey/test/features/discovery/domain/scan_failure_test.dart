import 'package:bluey/src/features/discovery/domain/scan_failure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('message', () {
    final failures = <ScanFailure>[
      for (final reason in ScanRefusalReason.values) ScanRefused(reason),
      const ScanPermissionMissing('BLUETOOTH_SCAN'),
      const ScanRadioUnavailable(),
      UnexpectedScanFailure('the platform threw', cause: StateError('x')),
    ];

    for (final failure in failures) {
      test('${failure.runtimeType} answers a sentence', () {
        // arrange
        final subject = failure;

        // act
        final message = subject.message;

        // assert
        expect(message, isNotEmpty);
        expect(message, endsWith('.'));
        expect(message[0], matches(RegExp('[A-Z]')));
      });
    }

    test('a missing permission names it', () {
      // arrange
      const failure = ScanPermissionMissing('BLUETOOTH_SCAN');

      // act
      final message = failure.message;

      // assert
      expect(message, contains('BLUETOOTH_SCAN'));
    });

    test('an unexpected failure carries its detail', () {
      // arrange
      final failure = UnexpectedScanFailure('boom', cause: StateError('x'));

      // act
      final message = failure.message;

      // assert
      expect(message, contains('boom'));
    });
  });

  group('equality by value', () {
    final cause = StateError('x');
    final rows = <(String, ScanFailure, ScanFailure, ScanFailure)>[
      (
        'refused',
        const ScanRefused(ScanRefusalReason.alreadyStarted),
        ScanRefused(ScanRefusalReason.alreadyStarted),
        const ScanRefused(ScanRefusalReason.unknown),
      ),
      (
        'permission missing',
        const ScanPermissionMissing('a'),
        ScanPermissionMissing('a'),
        const ScanPermissionMissing('b'),
      ),
      (
        'radio unavailable',
        const ScanRadioUnavailable(),
        ScanRadioUnavailable(),
        const ScanPermissionMissing('a'),
      ),
      (
        'unexpected',
        UnexpectedScanFailure('d', code: 'c', cause: cause),
        UnexpectedScanFailure('d', code: 'c', cause: cause),
        UnexpectedScanFailure('d', code: 'other', cause: cause),
      ),
    ];

    for (final (name, failure, same, other) in rows) {
      test('$name equals a failure of the same values and no other', () {
        // arrange
        final built = same;

        // act
        final equal = failure == built;

        // assert
        expect(equal, isTrue);
        expect(failure.hashCode, built.hashCode);
        expect(failure, isNot(other));
      });
    }
  });
}
