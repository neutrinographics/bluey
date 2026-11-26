import 'package:bluey/src/features/connection/infrastructure/adapters/platform_connection_ports.dart';
import 'package:bluey/src/features/connection/infrastructure/adapters/platform_links.dart';
import 'package:bluey/src/shared/domain/device_address.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../fakes/fake_platform.dart';
import '../../../../fixtures/shared/application/recording_log.dart';

const device = DeviceAddress('AA:BB:CC:DD:EE:01');

void main() {
  test('its links are PlatformLinks over the platform it was given', () async {
    // arrange
    final fake = FakeBlueyPlatform()..simulatePeripheral(id: device.value);
    final ports = platformConnectionPorts(fake, log: RecordingLog());

    // act
    await ports.links.open(device);

    // assert
    expect(ports.links, isA<PlatformLinks>());
    expect(fake.connectedDeviceIds, contains(device.value));
  });
}
