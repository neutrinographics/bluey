import 'dart:typed_data';
import 'package:bluey/bluey.dart';
import 'package:flutter_test/flutter_test.dart';

// Mock implementations for testing the interfaces
class MockRemoteDescriptor implements RemoteDescriptor {
  @override
  final UUID uuid;

  Uint8List _value = Uint8List(0);

  MockRemoteDescriptor(this.uuid);

  @override
  Future<Uint8List> read() async => _value;

  @override
  Future<void> write(Uint8List value) async {
    _value = value;
  }
}

class MockRemoteCharacteristic implements RemoteCharacteristic {
  @override
  final UUID uuid;

  @override
  final CharacteristicProperties properties;

  @override
  final List<RemoteDescriptor> descriptors;

  Uint8List _value = Uint8List(0);

  MockRemoteCharacteristic({
    required this.uuid,
    required this.properties,
    this.descriptors = const [],
  });

  @override
  Future<Uint8List> read() async {
    if (!properties.canRead) {
      throw const OperationNotSupportedException('read');
    }
    return _value;
  }

  @override
  Future<void> write(Uint8List value, {bool withResponse = true}) async {
    if (withResponse && !properties.canWrite) {
      throw const OperationNotSupportedException('write');
    }
    if (!withResponse && !properties.canWriteWithoutResponse) {
      throw const OperationNotSupportedException('writeWithoutResponse');
    }
    _value = value;
  }

  @override
  Stream<Uint8List> get notifications {
    if (!properties.canSubscribe) {
      throw const OperationNotSupportedException('notify');
    }
    return Stream.empty();
  }

  @override
  RemoteDescriptor descriptor(UUID uuid) {
    final desc = descriptors.where((d) => d.uuid == uuid).firstOrNull;
    if (desc == null) {
      throw CharacteristicNotFoundException(uuid);
    }
    return desc;
  }

  void setValue(Uint8List value) {
    _value = value;
  }
}

class MockRemoteService implements RemoteService {
  @override
  final UUID uuid;

  @override
  final bool isPrimary;

  @override
  final List<RemoteCharacteristic> characteristics;

  @override
  final List<RemoteService> includedServices;

  MockRemoteService({
    required this.uuid,
    this.isPrimary = true,
    this.characteristics = const [],
    this.includedServices = const [],
  });

  @override
  RemoteCharacteristic characteristic(UUID uuid) {
    final char = characteristics.where((c) => c.uuid == uuid).firstOrNull;
    if (char == null) {
      throw CharacteristicNotFoundException(uuid);
    }
    return char;
  }
}

void main() {
  group('RemoteDescriptor', () {
    test('has uuid', () {
      final descriptor = MockRemoteDescriptor(UUID.short(0x2902));
      expect(descriptor.uuid, equals(UUID.short(0x2902)));
    });

    test('can read value', () async {
      final descriptor = MockRemoteDescriptor(UUID.short(0x2902));
      final value = await descriptor.read();
      expect(value, isA<Uint8List>());
    });

    test('can write value', () async {
      final descriptor = MockRemoteDescriptor(UUID.short(0x2902));
      await descriptor.write(Uint8List.fromList([0x01, 0x00]));
      final value = await descriptor.read();
      expect(value, equals([0x01, 0x00]));
    });
  });

  group('RemoteCharacteristic', () {
    test('has uuid', () {
      final characteristic = MockRemoteCharacteristic(
        uuid: UUID.short(0x2A37),
        properties: const CharacteristicProperties(canRead: true),
      );
      expect(characteristic.uuid, equals(UUID.short(0x2A37)));
    });

    test('has properties', () {
      final characteristic = MockRemoteCharacteristic(
        uuid: UUID.short(0x2A37),
        properties: const CharacteristicProperties(
          canRead: true,
          canNotify: true,
        ),
      );
      expect(characteristic.properties.canRead, isTrue);
      expect(characteristic.properties.canNotify, isTrue);
      expect(characteristic.properties.canWrite, isFalse);
    });

    test('can read value when readable', () async {
      final characteristic = MockRemoteCharacteristic(
        uuid: UUID.short(0x2A37),
        properties: const CharacteristicProperties(canRead: true),
      );
      characteristic.setValue(Uint8List.fromList([60])); // Heart rate 60 bpm

      final value = await characteristic.read();
      expect(value, equals([60]));
    });

    test('throws when reading non-readable characteristic', () async {
      final characteristic = MockRemoteCharacteristic(
        uuid: UUID.short(0x2A37),
        properties: const CharacteristicProperties(canWrite: true),
      );

      expect(
        () => characteristic.read(),
        throwsA(isA<OperationNotSupportedException>()),
      );
    });

    test('can write value with response when writable', () async {
      final characteristic = MockRemoteCharacteristic(
        uuid: UUID.short(0x2A37),
        properties: const CharacteristicProperties(canWrite: true),
      );

      await characteristic.write(Uint8List.fromList([1, 2, 3]));
      // No exception means success
    });

    test('can write value without response when supported', () async {
      final characteristic = MockRemoteCharacteristic(
        uuid: UUID.short(0x2A37),
        properties:
            const CharacteristicProperties(canWriteWithoutResponse: true),
      );

      await characteristic.write(
        Uint8List.fromList([1, 2, 3]),
        withResponse: false,
      );
      // No exception means success
    });

    test('throws when writing to non-writable characteristic', () async {
      final characteristic = MockRemoteCharacteristic(
        uuid: UUID.short(0x2A37),
        properties: const CharacteristicProperties(canRead: true),
      );

      expect(
        () => characteristic.write(Uint8List.fromList([1, 2, 3])),
        throwsA(isA<OperationNotSupportedException>()),
      );
    });

    test('provides notifications stream when notify supported', () {
      final characteristic = MockRemoteCharacteristic(
        uuid: UUID.short(0x2A37),
        properties: const CharacteristicProperties(canNotify: true),
      );

      expect(characteristic.notifications, isA<Stream<Uint8List>>());
    });

    test('throws when accessing notifications on non-notifiable', () {
      final characteristic = MockRemoteCharacteristic(
        uuid: UUID.short(0x2A37),
        properties: const CharacteristicProperties(canRead: true),
      );

      expect(
        () => characteristic.notifications,
        throwsA(isA<OperationNotSupportedException>()),
      );
    });

    test('can find descriptor by UUID', () {
      final cccd = MockRemoteDescriptor(UUID.short(0x2902));
      final characteristic = MockRemoteCharacteristic(
        uuid: UUID.short(0x2A37),
        properties: const CharacteristicProperties(canNotify: true),
        descriptors: [cccd],
      );

      final found = characteristic.descriptor(UUID.short(0x2902));
      expect(found.uuid, equals(UUID.short(0x2902)));
    });

    test('throws when descriptor not found', () {
      final characteristic = MockRemoteCharacteristic(
        uuid: UUID.short(0x2A37),
        properties: const CharacteristicProperties(canNotify: true),
        descriptors: [],
      );

      expect(
        () => characteristic.descriptor(UUID.short(0x2902)),
        throwsA(isA<CharacteristicNotFoundException>()),
      );
    });

    test('has descriptors list', () {
      final cccd = MockRemoteDescriptor(UUID.short(0x2902));
      final characteristic = MockRemoteCharacteristic(
        uuid: UUID.short(0x2A37),
        properties: const CharacteristicProperties(canNotify: true),
        descriptors: [cccd],
      );

      expect(characteristic.descriptors, hasLength(1));
    });
  });

  group('RemoteService', () {
    test('has uuid', () {
      final service = MockRemoteService(uuid: Services.heartRate);
      expect(service.uuid, equals(Services.heartRate));
    });

    test('can find characteristic by UUID', () {
      final heartRateMeasurement = MockRemoteCharacteristic(
        uuid: UUID.short(0x2A37),
        properties: const CharacteristicProperties(canNotify: true),
      );
      final service = MockRemoteService(
        uuid: Services.heartRate,
        characteristics: [heartRateMeasurement],
      );

      final found = service.characteristic(UUID.short(0x2A37));
      expect(found.uuid, equals(UUID.short(0x2A37)));
    });

    test('throws when characteristic not found', () {
      final service = MockRemoteService(
        uuid: Services.heartRate,
        characteristics: [],
      );

      expect(
        () => service.characteristic(UUID.short(0x2A37)),
        throwsA(isA<CharacteristicNotFoundException>()),
      );
    });

    test('has characteristics list', () {
      final char1 = MockRemoteCharacteristic(
        uuid: UUID.short(0x2A37),
        properties: const CharacteristicProperties(canNotify: true),
      );
      final char2 = MockRemoteCharacteristic(
        uuid: UUID.short(0x2A38),
        properties: const CharacteristicProperties(canRead: true),
      );
      final service = MockRemoteService(
        uuid: Services.heartRate,
        characteristics: [char1, char2],
      );

      expect(service.characteristics, hasLength(2));
    });

    test('has included services list', () {
      final includedService = MockRemoteService(uuid: Services.battery);
      final service = MockRemoteService(
        uuid: Services.heartRate,
        includedServices: [includedService],
      );

      expect(service.includedServices, hasLength(1));
      expect(service.includedServices.first.uuid, equals(Services.battery));
    });
  });
}
