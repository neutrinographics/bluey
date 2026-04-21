import 'dart:async';
import 'dart:typed_data';

import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';
import '../fakes/test_helpers.dart';

/// Tests verifying that the public API rewraps platform-interface
/// disconnect exceptions into the domain-level [DisconnectedException]
/// with [DisconnectReason.linkLoss].
///
/// [platform.GattOperationDisconnectedException] is an internal contract
/// type emitted by the platform queue when a pending GATT op is drained
/// on link loss. Public callers of [BlueyConnection] and friends must
/// only ever see [BlueyException] subtypes so they can pattern-match
/// exhaustively.
void main() {
  late FakeBlueyPlatform fakePlatform;
  late Bluey bluey;

  const _serviceUuid = TestUuids.customService;
  const _charUuid = TestUuids.customChar1;

  setUp(() {
    fakePlatform = FakeBlueyPlatform();
    platform.BlueyPlatform.instance = fakePlatform;

    fakePlatform.simulatePeripheral(
      id: TestDeviceIds.device1,
      name: 'Disconnect Test Device',
      services: [
        TestServiceBuilder(_serviceUuid)
            .withWritable(_charUuid)
            .withNotifiable(TestUuids.customChar2)
            .build(),
      ],
    );

    bluey = Bluey();
  });

  tearDown(() async {
    await bluey.dispose();
  });

  final deviceUuid = UUID('00000000-0000-0000-0000-aabbccddee01');

  Device buildDevice() => Device(
    id: deviceUuid,
    address: TestDeviceIds.device1,
    name: 'Disconnect Test Device',
  );

  group('BlueyConnection GATT status-failed rewrap', () {
    test(
      'writeCharacteristic rewraps platform status-failed into GattOperationFailedException',
      () async {
        final conn = await bluey.connect(buildDevice());
        final services = await conn.services();
        final svc = services.first;
        final char = svc.characteristic(UUID(_charUuid));

        fakePlatform.simulateWriteStatusFailed = 1;

        try {
          await char.write(Uint8List.fromList([0x01]));
          fail('Expected GattOperationFailedException');
        } on GattOperationFailedException catch (e) {
          expect(e.operation, equals('writeCharacteristic'));
          expect(e.status, equals(1));
        }

        fakePlatform.simulateWriteStatusFailed = null;
        await conn.disconnect();
      },
    );

    test(
      'GattOperationFailedException is a BlueyException (sealed hierarchy)',
      () async {
        final conn = await bluey.connect(buildDevice());
        final services = await conn.services();
        final svc = services.first;
        final char = svc.characteristic(UUID(_charUuid));

        fakePlatform.simulateWriteStatusFailed = 5;

        await expectLater(
          () => char.write(Uint8List.fromList([0x01])),
          throwsA(isA<BlueyException>()),
        );

        fakePlatform.simulateWriteStatusFailed = null;
        await conn.disconnect();
      },
    );

    test(
      'platform.GattOperationStatusFailedException does not leak past the public API',
      () async {
        final conn = await bluey.connect(buildDevice());
        final services = await conn.services();
        final svc = services.first;
        final char = svc.characteristic(UUID(_charUuid));

        fakePlatform.simulateWriteStatusFailed = 1;

        await expectLater(
          () => char.write(Uint8List.fromList([0x01])),
          throwsA(isNot(isA<platform.GattOperationStatusFailedException>())),
        );

        fakePlatform.simulateWriteStatusFailed = null;
        await conn.disconnect();
      },
    );
  });

  group('BlueyConnection GATT disconnect rewrap', () {
    test(
      'writeCharacteristic rewraps platform disconnect into DisconnectedException',
      () async {
        final conn = await bluey.connect(buildDevice());
        final services = await conn.services();
        final svc = services.first;
        final char = svc.characteristic(UUID(_charUuid));

        fakePlatform.simulateWriteDisconnected = true;

        expect(
          () => char.write(Uint8List.fromList([0x01])),
          throwsA(isA<DisconnectedException>()),
        );

        fakePlatform.simulateWriteDisconnected = false;
        await conn.disconnect();
      },
    );

    test(
      'platform.GattOperationDisconnectedException does not leak past the public API',
      () async {
        final conn = await bluey.connect(buildDevice());
        final services = await conn.services();
        final svc = services.first;
        final char = svc.characteristic(UUID(_charUuid));

        fakePlatform.simulateWriteDisconnected = true;

        await expectLater(
          () => char.write(Uint8List.fromList([0x01])),
          throwsA(isNot(isA<platform.GattOperationDisconnectedException>())),
        );

        fakePlatform.simulateWriteDisconnected = false;
        await conn.disconnect();
      },
    );

    test(
      'thrown DisconnectedException is also a BlueyException (sealed-hierarchy match)',
      () async {
        final conn = await bluey.connect(buildDevice());
        final services = await conn.services();
        final svc = services.first;
        final char = svc.characteristic(UUID(_charUuid));

        fakePlatform.simulateWriteDisconnected = true;

        await expectLater(
          () => char.write(Uint8List.fromList([0x01])),
          throwsA(isA<BlueyException>()),
        );

        fakePlatform.simulateWriteDisconnected = false;
        await conn.disconnect();
      },
    );

    test(
      'setNotification failure on first listen surfaces on the notification stream',
      () async {
        final conn = await bluey.connect(buildDevice());
        final services = await conn.services();
        final svc = services.first;
        final notifyChar = svc.characteristic(UUID(TestUuids.customChar2));

        fakePlatform.simulateSetNotificationDisconnected = true;

        final errorCompleter = Completer<Object>();
        final sub = notifyChar.notifications.listen(
          (_) {},
          onError: errorCompleter.complete,
        );

        final received = await errorCompleter.future.timeout(
          const Duration(seconds: 2),
          onTimeout: () => fail(
            'Expected _onFirstListen setNotification failure to reach the '
            'stream consumer, but no error arrived within 2s',
          ),
        );
        expect(received, isA<DisconnectedException>());

        fakePlatform.simulateSetNotificationDisconnected = false;
        await sub.cancel();
        await conn.disconnect();
      },
    );

    test(
      'setNotification failure on last cancel does not produce unhandled async error',
      () async {
        final conn = await bluey.connect(buildDevice());
        final services = await conn.services();
        final svc = services.first;
        final notifyChar = svc.characteristic(UUID(TestUuids.customChar2));

        // Subscribe and cancel so we hit _onLastCancel. setNotification(false)
        // then fails; there is no stream consumer left, so the failure has no
        // natural recipient. It must be swallowed silently — otherwise it
        // escapes as an unhandled Future error and trips the test zone.
        final sub = notifyChar.notifications.listen((_) {});
        await Future<void>.delayed(Duration.zero);

        fakePlatform.simulateSetNotificationDisconnected = true;
        await sub.cancel();
        // Let the teardown microtask settle. If _onLastCancel leaks its
        // rejected future, flutter_test's zone guard fails the test here.
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        fakePlatform.simulateSetNotificationDisconnected = false;
        await conn.disconnect();
      },
    );

    test(
      'DisconnectedException carries deviceId and DisconnectReason.linkLoss',
      () async {
        final conn = await bluey.connect(buildDevice());
        final services = await conn.services();
        final svc = services.first;
        final char = svc.characteristic(UUID(_charUuid));

        fakePlatform.simulateWriteDisconnected = true;

        try {
          await char.write(Uint8List.fromList([0x01]));
          fail('Expected DisconnectedException');
        } on DisconnectedException catch (e) {
          expect(e.deviceId, equals(deviceUuid));
          expect(e.reason, equals(DisconnectReason.linkLoss));
        }

        fakePlatform.simulateWriteDisconnected = false;
        await conn.disconnect();
      },
    );
  });
}
