import 'dart:typed_data';

import 'package:bluey/bluey.dart';
import 'package:bluey/src/connection/bluey_connection.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';
import '../fakes/test_helpers.dart';

void main() {
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
}
