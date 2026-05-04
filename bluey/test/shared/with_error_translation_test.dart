import 'package:bluey/bluey.dart';
import 'package:bluey/src/connection/lifecycle_client.dart';
import 'package:bluey/src/shared/error_translation.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';
import '../fakes/test_helpers.dart';

/// Tests for the `withErrorTranslation` Future sugar — error translation
/// plus optional lifecycle-accounting hooks (preserves I097's user-op
/// accounting).
///
/// The lifecycle hook contract under test:
/// - Success: `markUserOpStarted` → body runs → `recordActivity` →
///   `markUserOpEnded` (in finally).
/// - Failure: `markUserOpStarted` → body throws → `recordUserOpFailure`
///   (with the *original* platform exception, not the translated one)
///   → `markUserOpEnded`.
/// - No-lifecycle (lifecycleClient: null): translation runs, hooks
///   skipped entirely.
void main() {
  final testDeviceId = UUID('00000000-0000-0000-0000-aabbccddee01');

  group('withErrorTranslation', () {
    test('returns body value on success', () async {
      final result = await withErrorTranslation<int>(
        () async => 42,
        operation: 'readCharacteristic',
        deviceId: testDeviceId,
      );
      expect(result, 42);
    });

    test(
      'translates thrown platform exception to typed domain exception',
      () async {
        await expectLater(
          withErrorTranslation<void>(
            () async {
              throw const platform.GattOperationTimeoutException(
                'readCharacteristic',
              );
            },
            operation: 'readCharacteristic',
            deviceId: testDeviceId,
          ),
          throwsA(isA<GattTimeoutException>()),
        );
      },
    );

    test('lifecycle hooks fire in order on success', () async {
      final spy = _SpyLifecycleClient();

      await withErrorTranslation<int>(
        () async => 1,
        operation: 'readCharacteristic',
        deviceId: testDeviceId,
        lifecycleClient: spy,
      );

      expect(
        spy.calls,
        equals(['markUserOpStarted', 'recordActivity', 'markUserOpEnded']),
      );
    });

    test('lifecycle hooks fire in order on failure; recordUserOpFailure '
        'receives the ORIGINAL platform exception (not the translated '
        'domain exception) so the I097 type-filter still works', () async {
      final spy = _SpyLifecycleClient();
      const original = platform.GattOperationTimeoutException(
        'readCharacteristic',
      );

      await expectLater(
        withErrorTranslation<int>(
          () async {
            throw original;
          },
          operation: 'readCharacteristic',
          deviceId: testDeviceId,
          lifecycleClient: spy,
        ),
        throwsA(isA<GattTimeoutException>()),
      );

      expect(
        spy.calls,
        equals(['markUserOpStarted', 'recordUserOpFailure', 'markUserOpEnded']),
      );
      expect(
        spy.lastFailureArgument,
        same(original),
        reason:
            'must pass the ORIGINAL platform exception, not the '
            'translated domain one — the I097 filter inside '
            'recordUserOpFailure does an `is GattOperationTimeoutException` '
            'check that would not match the translated GattTimeoutException.',
      );
    });

    test('no lifecycle hooks fire when lifecycleClient is null — pure '
        'translation only', () async {
      // Success path: just verify it returns without crashing.
      final result = await withErrorTranslation<int>(
        () async => 7,
        operation: 'connect',
      );
      expect(result, 7);

      // Failure path: still translates.
      await expectLater(
        withErrorTranslation<void>(() async {
          throw const platform.GattOperationTimeoutException('connect');
        }, operation: 'connect'),
        throwsA(isA<GattTimeoutException>()),
      );
    });
  });
}

/// Records calls to lifecycle-accounting hooks so tests can assert
/// order and arguments. Subclasses [LifecycleClient] (the production
/// type) so the helper's `LifecycleClient?` parameter accepts it.
class _SpyLifecycleClient extends LifecycleClient {
  _SpyLifecycleClient()
    : super(
        platformApi: FakeBlueyPlatform(),
        connectionId: 'spy-connection-id',
        peerSilenceTimeout: const Duration(seconds: 30),
        onServerUnreachable: _noop,
        logger: testLogger(),
      );

  static void _noop() {}

  final List<String> calls = [];
  Object? lastFailureArgument;

  @override
  void markUserOpStarted() {
    calls.add('markUserOpStarted');
  }

  @override
  void markUserOpEnded() {
    calls.add('markUserOpEnded');
  }

  @override
  void recordActivity() {
    calls.add('recordActivity');
  }

  @override
  void recordUserOpFailure(Object error) {
    calls.add('recordUserOpFailure');
    lastFailureArgument = error;
  }
}
