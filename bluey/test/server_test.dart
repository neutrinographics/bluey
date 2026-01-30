import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:bluey/bluey.dart';

void main() {
  group('GattPermission', () {
    test('has all expected values', () {
      expect(GattPermission.values, contains(GattPermission.read));
      expect(GattPermission.values, contains(GattPermission.readEncrypted));
      expect(GattPermission.values, contains(GattPermission.write));
      expect(GattPermission.values, contains(GattPermission.writeEncrypted));
    });
  });

  group('LocalDescriptor', () {
    test('creates with uuid and permissions', () {
      final descriptor = LocalDescriptor(
        uuid: UUID.short(0x2902), // CCCD
        permissions: [GattPermission.read, GattPermission.write],
      );

      expect(descriptor.uuid, equals(UUID.short(0x2902)));
      expect(descriptor.permissions, contains(GattPermission.read));
      expect(descriptor.permissions, contains(GattPermission.write));
    });

    test('immutable creates read-only descriptor with value', () {
      final value = Uint8List.fromList([0x01, 0x02, 0x03]);
      final descriptor = LocalDescriptor.immutable(
        uuid: UUID.short(0x2901), // Characteristic User Description
        value: value,
      );

      expect(descriptor.uuid, equals(UUID.short(0x2901)));
      expect(descriptor.value, equals(value));
      expect(descriptor.permissions, contains(GattPermission.read));
      expect(descriptor.permissions.length, equals(1));
    });

    test('equality based on uuid', () {
      final d1 = LocalDescriptor(
        uuid: UUID.short(0x2902),
        permissions: [GattPermission.read],
      );
      final d2 = LocalDescriptor(
        uuid: UUID.short(0x2902),
        permissions: [GattPermission.write],
      );
      final d3 = LocalDescriptor(
        uuid: UUID.short(0x2901),
        permissions: [GattPermission.read],
      );

      expect(d1, equals(d2)); // Same UUID
      expect(d1, isNot(equals(d3))); // Different UUID
    });
  });

  group('LocalCharacteristic', () {
    test('creates with uuid, properties, and permissions', () {
      final characteristic = LocalCharacteristic(
        uuid: UUID.short(0x2A37), // Heart Rate Measurement
        properties: CharacteristicProperties(canNotify: true),
        permissions: [GattPermission.read],
      );

      expect(characteristic.uuid, equals(UUID.short(0x2A37)));
      expect(characteristic.properties.canNotify, isTrue);
      expect(characteristic.permissions, contains(GattPermission.read));
    });

    test('can include descriptors', () {
      final descriptor = LocalDescriptor(
        uuid: UUID.short(0x2902),
        permissions: [GattPermission.read, GattPermission.write],
      );
      final characteristic = LocalCharacteristic(
        uuid: UUID.short(0x2A37),
        properties: CharacteristicProperties(canNotify: true),
        permissions: [GattPermission.read],
        descriptors: [descriptor],
      );

      expect(characteristic.descriptors.length, equals(1));
      expect(characteristic.descriptors.first.uuid, equals(UUID.short(0x2902)));
    });

    test('readable factory creates read-only characteristic', () {
      final characteristic = LocalCharacteristic.readable(
        uuid: UUID.short(0x2A19), // Battery Level
      );

      expect(characteristic.properties.canRead, isTrue);
      expect(characteristic.properties.canWrite, isFalse);
      expect(characteristic.permissions, contains(GattPermission.read));
    });

    test('writable factory creates writable characteristic', () {
      final characteristic = LocalCharacteristic.writable(
        uuid: UUID.short(0x2A06), // Alert Level
      );

      expect(characteristic.properties.canWrite, isTrue);
      expect(characteristic.permissions, contains(GattPermission.write));
    });

    test('notifiable factory creates notifiable characteristic', () {
      final characteristic = LocalCharacteristic.notifiable(
        uuid: UUID.short(0x2A37), // Heart Rate Measurement
      );

      expect(characteristic.properties.canNotify, isTrue);
      expect(characteristic.permissions, contains(GattPermission.read));
    });

    test('equality based on uuid', () {
      final c1 = LocalCharacteristic(
        uuid: UUID.short(0x2A37),
        properties: CharacteristicProperties(canNotify: true),
        permissions: [GattPermission.read],
      );
      final c2 = LocalCharacteristic(
        uuid: UUID.short(0x2A37),
        properties: CharacteristicProperties(canRead: true),
        permissions: [GattPermission.write],
      );

      expect(c1, equals(c2)); // Same UUID
    });
  });

  group('LocalService', () {
    test('creates with uuid and characteristics', () {
      final characteristic = LocalCharacteristic.readable(
        uuid: UUID.short(0x2A19),
      );
      final service = LocalService(
        uuid: UUID.short(0x180F), // Battery Service
        characteristics: [characteristic],
      );

      expect(service.uuid, equals(UUID.short(0x180F)));
      expect(service.characteristics.length, equals(1));
      expect(service.isPrimary, isTrue); // Default
    });

    test('can be secondary service', () {
      final service = LocalService(
        uuid: UUID.short(0x1801),
        isPrimary: false,
        characteristics: [],
      );

      expect(service.isPrimary, isFalse);
    });

    test('can include other services', () {
      final includedService = LocalService(
        uuid: UUID.short(0x1801),
        characteristics: [],
      );
      final service = LocalService(
        uuid: UUID.short(0x180F),
        characteristics: [],
        includedServices: [includedService],
      );

      expect(service.includedServices.length, equals(1));
      expect(service.includedServices.first.uuid, equals(UUID.short(0x1801)));
    });

    test('equality based on uuid', () {
      final s1 = LocalService(
        uuid: UUID.short(0x180F),
        characteristics: [],
      );
      final s2 = LocalService(
        uuid: UUID.short(0x180F),
        isPrimary: false,
        characteristics: [],
      );

      expect(s1, equals(s2)); // Same UUID
    });
  });

  group('Central', () {
    test('has id property', () {
      final central = MockCentral(
        id: UUID.short(0x1234),
        mtu: 23,
      );

      expect(central.id, equals(UUID.short(0x1234)));
    });

    test('has mtu property', () {
      final central = MockCentral(
        id: UUID.short(0x1234),
        mtu: 512,
      );

      expect(central.mtu, equals(512));
    });

    test('can disconnect', () async {
      final central = MockCentral(
        id: UUID.short(0x1234),
        mtu: 23,
      );

      await expectLater(central.disconnect(), completes);
    });
  });

  group('Server', () {
    late MockServer server;

    setUp(() {
      server = MockServer();
    });

    test('has isAdvertising property', () {
      expect(server.isAdvertising, isFalse);
    });

    test('has connections stream', () {
      expect(server.connections, isA<Stream<Central>>());
    });

    test('has connectedCentrals list', () {
      expect(server.connectedCentrals, isA<List<Central>>());
    });

    test('can add service', () {
      final service = LocalService(
        uuid: UUID.short(0x180F),
        characteristics: [],
      );

      server.addService(service);
      expect(server.services.length, equals(1));
    });

    test('can remove service', () {
      final service = LocalService(
        uuid: UUID.short(0x180F),
        characteristics: [],
      );

      server.addService(service);
      server.removeService(UUID.short(0x180F));
      expect(server.services.length, equals(0));
    });

    test('can start advertising', () async {
      await server.startAdvertising();
      expect(server.isAdvertising, isTrue);
    });

    test('can stop advertising', () async {
      await server.startAdvertising();
      await server.stopAdvertising();
      expect(server.isAdvertising, isFalse);
    });

    test('can notify all subscribed centrals', () async {
      final data = Uint8List.fromList([0x01, 0x02]);
      await expectLater(
        server.notify(UUID.short(0x2A37), data: data),
        completes,
      );
    });

    test('can notify specific central', () async {
      final central = MockCentral(id: UUID.short(0x1234), mtu: 23);
      final data = Uint8List.fromList([0x01, 0x02]);
      await expectLater(
        server.notifyTo(central, UUID.short(0x2A37), data: data),
        completes,
      );
    });

    test('can dispose', () async {
      await expectLater(server.dispose(), completes);
    });
  });
}

/// Mock implementation of Central for testing.
class MockCentral implements Central {
  @override
  final UUID id;

  @override
  final int mtu;

  bool disconnected = false;

  MockCentral({required this.id, required this.mtu});

  @override
  Future<void> disconnect() async {
    disconnected = true;
  }
}

/// Mock implementation of Server for testing.
class MockServer implements Server {
  final List<LocalService> _services = [];
  bool _isAdvertising = false;
  final _connectionsController = StreamController<Central>.broadcast();

  @override
  bool get isAdvertising => _isAdvertising;

  @override
  Stream<Central> get connections => _connectionsController.stream;

  @override
  List<Central> get connectedCentrals => [];

  List<LocalService> get services => _services;

  @override
  void addService(LocalService service) {
    _services.add(service);
  }

  @override
  void removeService(UUID uuid) {
    _services.removeWhere((s) => s.uuid == uuid);
  }

  @override
  Future<void> startAdvertising({
    String? name,
    List<UUID>? services,
    ManufacturerData? manufacturerData,
    Duration? timeout,
  }) async {
    _isAdvertising = true;
  }

  @override
  Future<void> stopAdvertising() async {
    _isAdvertising = false;
  }

  @override
  Future<void> notify(UUID characteristic, {required Uint8List data}) async {}

  @override
  Future<void> notifyTo(
    Central central,
    UUID characteristic, {
    required Uint8List data,
  }) async {}

  @override
  Future<void> dispose() async {
    await _connectionsController.close();
  }
}
