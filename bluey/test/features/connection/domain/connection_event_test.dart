import 'package:bluey/src/features/connection/domain/connection_event.dart';
import 'package:bluey/src/shared/domain/bluey_event.dart';
import 'package:bluey/src/shared/domain/device_address.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const address = DeviceAddress('AA:BB:CC:DD:EE:FF');

  group('ConnectingEvent', () {
    test('is a BlueyEvent that names the device being connected', () {
      // arrange
      const source = 'Bluey';

      // act
      final event = ConnectingEvent(deviceAddress: address, source: source);

      // assert
      expect(event, isA<BlueyEvent>());
      expect(event.deviceAddress, address);
      expect(event.source, source);
      expect(event.toString(), '[Connection] Connecting to AA:BB:CC');
    });
  });

  group('ConnectedEvent', () {
    test('is a BlueyEvent that names the device connected', () {
      // arrange
      const source = 'Bluey';

      // act
      final event = ConnectedEvent(deviceAddress: address, source: source);

      // assert
      expect(event, isA<BlueyEvent>());
      expect(event.deviceAddress, address);
      expect(event.source, source);
      expect(event.toString(), '[Connection] Connected to AA:BB:CC');
    });
  });

  group('DisconnectedEvent', () {
    test('names the device and the reason when there is one', () {
      // arrange
      const source = 'Bluey';

      // act
      final event = DisconnectedEvent(
        deviceAddress: address,
        reason: 'linkLoss',
        source: source,
      );

      // assert
      expect(event, isA<BlueyEvent>());
      expect(event.deviceAddress, address);
      expect(event.reason, 'linkLoss');
      expect(event.source, source);
      expect(
        event.toString(),
        '[Connection] Disconnected from AA:BB:CC (linkLoss)',
      );
    });

    test('names the device alone when there is no reason', () {
      // arrange
      const reason = null;

      // act
      final event = DisconnectedEvent(deviceAddress: address, reason: reason);

      // assert
      expect(event.reason, isNull);
      expect(event.toString(), '[Connection] Disconnected from AA:BB:CC');
    });
  });
}
