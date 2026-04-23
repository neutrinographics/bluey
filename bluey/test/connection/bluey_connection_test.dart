import 'dart:typed_data';

import 'package:bluey/bluey.dart';
import 'package:bluey/src/connection/bluey_connection.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';
import '../fakes/test_helpers.dart';

void main() {
  group('_runGattOp GattOperationUnknownPlatformException translation', () {
    test(
      'wraps GattOperationUnknownPlatformException as BlueyPlatformException '
      'preserving wire code',
      () async {
        final fakePlatform = FakeBlueyPlatform();
        platform.BlueyPlatform.instance = fakePlatform;

        fakePlatform.simulatePeripheral(
          id: TestDeviceIds.device1,
          name: 'Test',
          services: [
            TestServiceBuilder(TestUuids.customService)
                .withReadable(TestUuids.customChar1)
                .build(),
          ],
          characteristicValues: {
            TestUuids.customChar1: Uint8List.fromList([0x01]),
          },
        );
        await fakePlatform.connect(
          TestDeviceIds.device1,
          const platform.PlatformConnectConfig(timeoutMs: null, mtu: null),
        );

        // Inject a GattOperationUnknownPlatformException — this is the typed
        // exception the iOS adapter now throws for 'bluey-unknown' codes
        // instead of going directly to BlueyPlatformException.
        fakePlatform.simulateReadUnknownPlatformExceptionCode = 'bluey-unknown';
        fakePlatform.simulateReadUnknownPlatformExceptionMessage =
            'opaque native error';

        final char = BlueyRemoteCharacteristic(
          platform: fakePlatform,
          connectionId: TestDeviceIds.device1,
          deviceId: UUID('00000000-0000-0000-0000-aabbccddee01'),
          uuid: UUID(TestUuids.customChar1),
          properties: const CharacteristicProperties(
            canRead: true,
            canWrite: false,
            canWriteWithoutResponse: false,
            canNotify: false,
            canIndicate: false,
          ),
          descriptors: const [],
        );

        try {
          await char.read();
          fail('expected BlueyPlatformException');
        } on BlueyPlatformException catch (e) {
          // Wire code is preserved as-is (not stripped to 'unknown').
          expect(e.code, 'bluey-unknown');
          expect(e.message, contains('opaque native error'));
        }
      },
    );
  });

  group('_runGattOp defensive PlatformException catch-all', () {
    test('wraps untranslated PlatformException as BlueyPlatformException',
        () async {
      final fakePlatform = FakeBlueyPlatform();
      platform.BlueyPlatform.instance = fakePlatform;

      fakePlatform.simulatePeripheral(
        id: TestDeviceIds.device1,
        name: 'Test',
        services: [
          TestServiceBuilder(TestUuids.customService)
              .withReadable(TestUuids.customChar1)
              .build(),
        ],
        characteristicValues: {
          TestUuids.customChar1: Uint8List.fromList([0x01]),
        },
      );
      await fakePlatform.connect(
        TestDeviceIds.device1,
        const platform.PlatformConnectConfig(timeoutMs: null, mtu: null),
      );

      // Inject a raw PlatformException with an unknown code — models a
      // platform error that no adapter has translated yet.
      fakePlatform.simulateReadPlatformErrorCode = 'fictitious-code';

      final char = BlueyRemoteCharacteristic(
        platform: fakePlatform,
        connectionId: TestDeviceIds.device1,
        deviceId: UUID('00000000-0000-0000-0000-aabbccddee01'),
        uuid: UUID(TestUuids.customChar1),
        properties: const CharacteristicProperties(
          canRead: true,
          canWrite: false,
          canWriteWithoutResponse: false,
          canNotify: false,
          canIndicate: false,
        ),
        descriptors: const [],
      );

      try {
        await char.read();
        fail('expected BlueyPlatformException');
      } on BlueyPlatformException catch (e) {
        expect(e.code, 'fictitious-code');
        expect(e.message, contains('fictitious-code'));
      }
    });
  });

  group('_runGattOp PlatformPermissionDeniedException translation', () {
    test('wraps PlatformPermissionDeniedException as PermissionDeniedException',
        () async {
      final fakePlatform = FakeBlueyPlatform();
      platform.BlueyPlatform.instance = fakePlatform;

      fakePlatform.simulatePeripheral(
        id: TestDeviceIds.device1,
        name: 'Test',
        services: [
          TestServiceBuilder(TestUuids.customService)
              .withReadable(TestUuids.customChar1)
              .build(),
        ],
        characteristicValues: {
          TestUuids.customChar1: Uint8List.fromList([0x01]),
        },
      );
      await fakePlatform.connect(
        TestDeviceIds.device1,
        const platform.PlatformConnectConfig(timeoutMs: null, mtu: null),
      );

      fakePlatform.simulateReadError(
        const platform.PlatformPermissionDeniedException(
          'readCharacteristic',
          permission: 'BLUETOOTH_CONNECT',
          message: 'Missing BLUETOOTH_CONNECT permission',
        ),
      );

      final char = BlueyRemoteCharacteristic(
        platform: fakePlatform,
        connectionId: TestDeviceIds.device1,
        deviceId: UUID('00000000-0000-0000-0000-aabbccddee01'),
        uuid: UUID(TestUuids.customChar1),
        properties: const CharacteristicProperties(
          canRead: true,
          canWrite: false,
          canWriteWithoutResponse: false,
          canNotify: false,
          canIndicate: false,
        ),
        descriptors: const [],
      );

      try {
        await char.read();
        fail('expected PermissionDeniedException');
      } on PermissionDeniedException catch (e) {
        expect(e.permissions, ['BLUETOOTH_CONNECT']);
      }
    });
  });
}
