import 'dart:typed_data';

import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';

/// I054 — pins the contract that GATT-op events declared in
/// `events.dart` are actually emitted on `bluey.events`. Pre-fix the
/// event types were defined but never `emit()`ed, so consumers
/// subscribing to the stream got scan/connect/server events but no
/// read/write/discovery/notification events.
///
/// Each test wires an end-to-end Bluey instance against
/// [FakeBlueyPlatform], invokes the relevant GATT op, and asserts the
/// event reaches the stream. The wiring path covered here:
/// `Bluey._eventBus` → `BlueyConnection._events` →
/// `BlueyRemoteCharacteristic._events` → `EventPublisher.emit`.
void main() {
  late FakeBlueyPlatform fakePlatform;
  late Bluey bluey;

  final deviceId = UUID('00000000-0000-0000-0000-aabbccddee01');
  const deviceAddress = 'AA:BB:CC:DD:EE:01';
  const serviceUuidStr = '0000180d-0000-1000-8000-00805f9b34fb'; // Heart Rate
  const charUuidStr = '00002a37-0000-1000-8000-00805f9b34fb'; // HR Measurement

  Device deviceFor() =>
      Device(id: deviceId, address: deviceAddress, name: 'Test Device');

  void simulatePeripheralWithReadableChar({Uint8List? value}) {
    fakePlatform.simulatePeripheral(
      id: deviceAddress,
      name: 'Test Device',
      services: [
        platform.PlatformService(
          uuid: serviceUuidStr,
          isPrimary: true,
          characteristics: const [
            platform.PlatformCharacteristic(
              uuid: charUuidStr,
              properties: platform.PlatformCharacteristicProperties(
                canRead: true,
                canWrite: true,
                canWriteWithoutResponse: false,
                canNotify: true,
                canIndicate: false,
              ),
              descriptors: [],
              handle: 0,
            ),
          ],
          includedServices: [],
        ),
      ],
      characteristicValues: {
        charUuidStr: value ?? Uint8List.fromList([0x42]),
      },
    );
  }

  setUp(() {
    fakePlatform = FakeBlueyPlatform();
    platform.BlueyPlatform.instance = fakePlatform;
    bluey = Bluey();
  });

  tearDown(() async {
    await bluey.dispose();
    await fakePlatform.dispose();
  });

  group('GATT-op events on bluey.events (I054)', () {
    test('services() emits DiscoveringServicesEvent then '
        'ServicesDiscoveredEvent', () async {
      simulatePeripheralWithReadableChar();
      final events = <BlueyEvent>[];
      final sub = bluey.events.listen(events.add);

      final connection = await bluey.connect(deviceFor());
      final services = await connection.services();

      // Yield so any trailing emissions land before assertions.
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      await connection.disconnect();

      final discovering = events.whereType<DiscoveringServicesEvent>().toList();
      final discovered = events.whereType<ServicesDiscoveredEvent>().toList();
      expect(discovering, hasLength(1));
      expect(discovering.single.deviceId, equals(deviceId));
      expect(discovered, hasLength(1));
      expect(discovered.single.deviceId, equals(deviceId));
      expect(discovered.single.serviceCount, equals(services.length));
    });

    test('read() emits CharacteristicReadEvent with valueLength', () async {
      simulatePeripheralWithReadableChar(value: Uint8List.fromList([1, 2, 3]));
      final events = <BlueyEvent>[];
      final sub = bluey.events.listen(events.add);

      final connection = await bluey.connect(deviceFor());
      final char =
          (await connection.services()).single.characteristics().single;
      final value = await char.read();

      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      await connection.disconnect();

      final reads = events.whereType<CharacteristicReadEvent>().toList();
      expect(reads, hasLength(1));
      expect(reads.single.deviceId, equals(deviceId));
      expect(reads.single.characteristicId, equals(UUID(charUuidStr)));
      expect(reads.single.valueLength, equals(value.length));
    });

    test('write() emits CharacteristicWrittenEvent with valueLength + '
        'withResponse flag', () async {
      simulatePeripheralWithReadableChar();
      final events = <BlueyEvent>[];
      final sub = bluey.events.listen(events.add);

      final connection = await bluey.connect(deviceFor());
      final char =
          (await connection.services()).single.characteristics().single;
      final payload = Uint8List.fromList([0x10, 0x20, 0x30, 0x40]);
      await char.write(payload, withResponse: true);

      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      await connection.disconnect();

      final writes = events.whereType<CharacteristicWrittenEvent>().toList();
      expect(writes, hasLength(1));
      expect(writes.single.deviceId, equals(deviceId));
      expect(writes.single.characteristicId, equals(UUID(charUuidStr)));
      expect(writes.single.valueLength, equals(payload.length));
      expect(writes.single.withResponse, isTrue);
    });

    test('subscribing to a notifiable characteristic emits '
        'NotificationSubscriptionEvent(enabled: true)', () async {
      simulatePeripheralWithReadableChar();
      final events = <BlueyEvent>[];
      final sub = bluey.events.listen(events.add);

      final connection = await bluey.connect(deviceFor());
      final char =
          (await connection.services()).single.characteristics().single;
      final notifSub = char.notifications.listen((_) {});

      // Allow the platform setNotification call to resolve so the
      // .then(...) emission can fire.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await notifSub.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await sub.cancel();
      await connection.disconnect();

      final subs = events.whereType<NotificationSubscriptionEvent>().toList();
      expect(subs.where((e) => e.enabled), hasLength(1));
      final enable = subs.firstWhere((e) => e.enabled);
      expect(enable.deviceId, equals(deviceId));
      expect(enable.characteristicId, equals(UUID(charUuidStr)));
    });

    test('inbound notification emits NotificationReceivedEvent with '
        'valueLength', () async {
      simulatePeripheralWithReadableChar();
      final events = <BlueyEvent>[];
      final sub = bluey.events.listen(events.add);

      final connection = await bluey.connect(deviceFor());
      final char =
          (await connection.services()).single.characteristics().single;
      final notifSub = char.notifications.listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 5));

      // Inject an inbound notification on the platform.
      fakePlatform.simulateNotification(
        deviceId: deviceAddress,
        characteristicUuid: charUuidStr,
        value: Uint8List.fromList([0xAA, 0xBB, 0xCC]),
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));

      await notifSub.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await sub.cancel();
      await connection.disconnect();

      final received = events.whereType<NotificationReceivedEvent>().toList();
      expect(received, hasLength(1));
      expect(received.single.deviceId, equals(deviceId));
      expect(received.single.characteristicId, equals(UUID(charUuidStr)));
      expect(received.single.valueLength, equals(3));
    });
  });
}
