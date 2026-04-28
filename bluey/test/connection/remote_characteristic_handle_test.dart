import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';
import '../fakes/test_helpers.dart';

void main() {
  late FakeBlueyPlatform fakePlatform;

  setUp(() {
    fakePlatform = FakeBlueyPlatform();
    platform.BlueyPlatform.instance = fakePlatform;
  });

  tearDown(() async {
    await fakePlatform.dispose();
  });

  const cccdUuid = '00002902-0000-1000-8000-00805f9b34fb';

  Future<Connection> connectAndDiscover() async {
    fakePlatform.simulatePeripheral(
      id: TestDeviceIds.device1,
      name: 'Test Device',
      services: [
        platform.PlatformService(
          uuid: TestUuids.customService,
          isPrimary: true,
          characteristics: [
            platform.PlatformCharacteristic(
              uuid: TestUuids.customChar1,
              properties: TestProperties.readNotify,
              descriptors: const [
                platform.PlatformDescriptor(uuid: cccdUuid),
              ],
            ),
            platform.PlatformCharacteristic(
              uuid: TestUuids.customChar2,
              properties: TestProperties.readOnly,
              descriptors: const [],
            ),
          ],
          includedServices: const [],
        ),
      ],
    );

    final bluey = Bluey();
    final device = await scanFirstDevice(bluey);
    return bluey.connect(device);
  }

  test('BlueyRemoteCharacteristic exposes its AttributeHandle', () async {
    final connection = await connectAndDiscover();
    final services = await connection.services();
    final characteristic = services.first.characteristics().first;

    expect(characteristic.handle, isA<AttributeHandle>());
    expect(characteristic.handle.value, greaterThan(0));
  });

  test('BlueyRemoteDescriptor exposes its AttributeHandle', () async {
    final connection = await connectAndDiscover();
    final services = await connection.services();
    final characteristic = services.first.characteristics().first;
    final descriptor = characteristic.descriptors().first;

    expect(descriptor.handle, isA<AttributeHandle>());
    expect(descriptor.handle.value, greaterThan(0));
  });

  test('handles are stable across services() calls within one connection',
      () async {
    final connection = await connectAndDiscover();
    final firstServices = await connection.services();
    final firstHandle =
        firstServices.first.characteristics().first.handle;
    final secondServices = await connection.services();
    final secondHandle =
        secondServices.first.characteristics().first.handle;

    expect(secondHandle, equals(firstHandle));
  });

  test('distinct characteristics get distinct handles', () async {
    final connection = await connectAndDiscover();
    final services = await connection.services();
    final chars = services.first.characteristics();

    expect(chars[0].handle, isNot(equals(chars[1].handle)));
  });
}
