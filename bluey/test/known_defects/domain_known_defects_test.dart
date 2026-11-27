/// Known defects from the audit of 2026-11-17
/// (docs/reviews/2026-11-17-correctness-and-test-rig-audit.md).
///
/// Each test asserts what an app would reasonably expect and fails today.
/// The slice that fixes a defect moves its test into the suite of the code
/// it fixes and takes it out of this file.
@Tags(['known-defect'])
library;

import 'dart:async';

import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';
import '../fakes/test_helpers.dart';

final class _ControlServiceRejectingPlatform extends FakeBlueyPlatform {
  int failuresLeft = 1;

  @override
  Future<platform.PlatformLocalService> addService(
    platform.PlatformLocalService service,
  ) async {
    if (failuresLeft > 0) {
      failuresLeft--;
      throw const platform.GattOperationUnknownPlatformException(
        'addService',
        code: 'bluey-unknown',
        message: 'transient native failure',
      );
    }
    return super.addService(service);
  }
}

void main() {
  const centralId = 'CC:CC:CC:CC:CC:01';
  late FakeBlueyPlatform fake;
  late Bluey bluey;

  setUp(() async {
    fake = FakeBlueyPlatform();
    platform.BlueyPlatform.instance = fake;
    bluey = await Bluey.create(localIdentity: TestServerIds.localIdentity);
  });

  group('L1 (I386): advertising state desync', () {
    test('a rejected re-start does not make stopAdvertising a no-op', () async {
      // arrange
      final server = bluey.server()!;
      await server.startAdvertising(name: 'a');
      expect(fake.isAdvertising, isTrue);
      fake.advertisingShouldFail = true;

      // act
      await expectLater(server.startAdvertising(name: 'b'), throwsA(anything));
      await server.stopAdvertising();

      // assert
      expect(
        fake.isAdvertising,
        isFalse,
        reason: 'radio still advertising and can no longer be stopped',
      );
    });
  });

  group('M7 (I384): server request with no handler attached', () {
    test('a read with no readRequests listener is answered', () async {
      // arrange
      final server = bluey.server()!;
      await server.addService(
        HostedService(
          uuid: UUID(TestUuids.customService),
          characteristics: [
            HostedCharacteristic.readable(uuid: UUID(TestUuids.customChar1)),
          ],
        ),
      );
      fake.simulateCentralConnection(centralId: centralId);
      await pumpEventQueue();

      // act
      final settled = fake
          .simulateReadRequest(
            centralId: centralId,
            characteristicUuid: TestUuids.customChar1,
          )
          .then<Object?>((v) => v, onError: (Object e) => e);

      // assert
      await expectLater(
        settled.timeout(const Duration(seconds: 1)),
        completes,
        reason: 'request is dropped; the central waits out the ATT timeout',
      );
    });
  });

  group('M6 (I383): control-service registration failure', () {
    test('a transient addService failure does not brick the server', () async {
      // arrange
      final unhandled = <Object>[];
      final outcome = Completer<List<Object?>>();

      // act
      runZonedGuarded(() async {
        final failing = _ControlServiceRejectingPlatform();
        platform.BlueyPlatform.instance = failing;
        final b = await Bluey.create(
          localIdentity: TestServerIds.localIdentity,
        );
        final server = b.server()!;
        await pumpEventQueue();

        final errors = <Object?>[];
        for (var attempt = 0; attempt < 2; attempt++) {
          try {
            await server.addService(
              HostedService(
                uuid: UUID(TestUuids.customService),
                characteristics: [
                  HostedCharacteristic.readable(
                    uuid: UUID(TestUuids.customChar1),
                  ),
                ],
              ),
            );
            errors.add(null);
          } catch (e) {
            errors.add(e);
          }
        }
        outcome.complete(errors);
      }, (e, _) => unhandled.add(e));

      final errors = await outcome.future;
      await pumpEventQueue();

      // assert
      // ignore: avoid_print
      print('unhandled=$unhandled addService errors=$errors');
      expect(unhandled, isEmpty, reason: 'unhandled async error at server()');
      expect(
        errors.last,
        anyOf(isNull, isA<BlueyException>()),
        reason:
            'server is permanently unusable: every later call rethrows '
            'the cached, untranslated platform error',
      );
    });
  });
}
