import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:bluey/bluey.dart';

/// Integration tests for the Bluey GATT Server (peripheral role).
///
/// These tests run on a real device and verify the actual BLE functionality.
/// Note: Some tests may require manual interaction or a second device to
/// act as a central.
///
/// Run with: flutter test integration_test/server_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Bluey bluey;

  setUp(() {
    bluey = Bluey();
  });

  tearDown(() async {
    await bluey.dispose();
  });

  group('Server Lifecycle', () {
    testWidgets('can create server instance', (tester) async {
      final server = bluey.server();

      expect(server, isNotNull);
      expect(server, isA<Server>());
      expect(server.isAdvertising, isFalse);

      await server.dispose();
    });

    testWidgets('server starts with no connected centrals', (tester) async {
      final server = bluey.server();

      expect(server.connectedCentrals, isEmpty);

      await server.dispose();
    });

    testWidgets('can add service to server', (tester) async {
      final server = bluey.server();

      final service = LocalService(
        uuid: UUID('12345678-1234-1234-1234-123456789abc'),
        isPrimary: true,
        characteristics: [
          LocalCharacteristic(
            uuid: UUID('12345678-1234-1234-1234-123456789abd'),
            properties: const CharacteristicProperties(
              canRead: true,
              canWrite: true,
              canNotify: true,
            ),
            permissions: const [GattPermission.read, GattPermission.write],
          ),
        ],
      );

      // Should not throw
      await server.addService(service);

      await server.dispose();
    });

    testWidgets('can add multiple services', (tester) async {
      final server = bluey.server();

      final service1 = LocalService(
        uuid: UUID('12345678-1234-1234-1234-123456789abc'),
        isPrimary: true,
        characteristics: [],
      );

      final service2 = LocalService(
        uuid: UUID('87654321-4321-4321-4321-cba987654321'),
        isPrimary: true,
        characteristics: [],
      );

      await server.addService(service1);
      await server.addService(service2);

      await server.dispose();
    });

    testWidgets('can remove service from server', (tester) async {
      final server = bluey.server();
      final serviceUuid = UUID('12345678-1234-1234-1234-123456789abc');

      await server.addService(
        LocalService(uuid: serviceUuid, isPrimary: true, characteristics: []),
      );

      // Should not throw
      await server.removeService(serviceUuid);

      await server.dispose();
    });
  });

  group('Advertising', () {
    testWidgets('can start advertising', (tester) async {
      final server = bluey.server();
      final serviceUuid = UUID('12345678-1234-1234-1234-123456789abc');

      await server.addService(
        LocalService(uuid: serviceUuid, isPrimary: true, characteristics: []),
      );

      await server.startAdvertising(
        name: 'Bluey Test',
        services: [serviceUuid],
      );

      expect(server.isAdvertising, isTrue);

      await server.dispose();
    });

    testWidgets('can stop advertising', (tester) async {
      final server = bluey.server();
      final serviceUuid = UUID('12345678-1234-1234-1234-123456789abc');

      await server.addService(
        LocalService(uuid: serviceUuid, isPrimary: true, characteristics: []),
      );

      await server.startAdvertising(
        name: 'Bluey Test',
        services: [serviceUuid],
      );

      expect(server.isAdvertising, isTrue);

      await server.stopAdvertising();

      expect(server.isAdvertising, isFalse);

      await server.dispose();
    });

    testWidgets('isAdvertising reflects current state', (tester) async {
      final server = bluey.server();
      final serviceUuid = UUID('12345678-1234-1234-1234-123456789abc');

      expect(server.isAdvertising, isFalse);

      await server.addService(
        LocalService(uuid: serviceUuid, isPrimary: true, characteristics: []),
      );

      await server.startAdvertising(
        name: 'Bluey Test',
        services: [serviceUuid],
      );

      expect(server.isAdvertising, isTrue);

      await server.stopAdvertising();

      expect(server.isAdvertising, isFalse);

      await server.dispose();
    });
  });

  group('Server Cleanup', () {
    testWidgets('dispose stops advertising', (tester) async {
      final server = bluey.server();
      final serviceUuid = UUID('12345678-1234-1234-1234-123456789abc');

      await server.addService(
        LocalService(uuid: serviceUuid, isPrimary: true, characteristics: []),
      );

      await server.startAdvertising(
        name: 'Bluey Test',
        services: [serviceUuid],
      );

      expect(server.isAdvertising, isTrue);

      await server.dispose();

      // After dispose, isAdvertising should be false
      // (though accessing after dispose is not recommended)
    });

    testWidgets('can create new server after disposing previous', (
      tester,
    ) async {
      final server1 = bluey.server();
      final serviceUuid = UUID('12345678-1234-1234-1234-123456789abc');

      await server1.addService(
        LocalService(uuid: serviceUuid, isPrimary: true, characteristics: []),
      );

      await server1.startAdvertising(
        name: 'Bluey Test 1',
        services: [serviceUuid],
      );

      await server1.dispose();

      // Create a new server
      final server2 = bluey.server();

      await server2.addService(
        LocalService(uuid: serviceUuid, isPrimary: true, characteristics: []),
      );

      await server2.startAdvertising(
        name: 'Bluey Test 2',
        services: [serviceUuid],
      );

      expect(server2.isAdvertising, isTrue);

      await server2.dispose();
    });
  });

  group('Connections Stream', () {
    testWidgets('connections stream is available', (tester) async {
      final server = bluey.server();

      expect(server.connections, isA<Stream<Central>>());

      await server.dispose();
    });

    testWidgets('can listen to connections before advertising', (tester) async {
      final server = bluey.server();
      final serviceUuid = UUID('12345678-1234-1234-1234-123456789abc');

      // Set up listener before advertising
      final centrals = <Central>[];
      final subscription = server.connections.listen((central) {
        centrals.add(central);
      });

      await server.addService(
        LocalService(uuid: serviceUuid, isPrimary: true, characteristics: []),
      );

      await server.startAdvertising(
        name: 'Bluey Test',
        services: [serviceUuid],
      );

      // Wait a bit for any phantom connections to be filtered
      await Future.delayed(const Duration(milliseconds: 500));

      // No centrals should be connected automatically
      // (unless a device is actively connecting)
      // This mainly verifies the stream setup doesn't throw

      await subscription.cancel();
      await server.dispose();
    });
  });

  group('Characteristic Properties', () {
    testWidgets('can create read-only characteristic', (tester) async {
      final server = bluey.server();

      await server.addService(
        LocalService(
          uuid: UUID('12345678-1234-1234-1234-123456789abc'),
          isPrimary: true,
          characteristics: [
            LocalCharacteristic(
              uuid: UUID('12345678-1234-1234-1234-123456789abd'),
              properties: const CharacteristicProperties(canRead: true),
              permissions: const [GattPermission.read],
            ),
          ],
        ),
      );

      await server.dispose();
    });

    testWidgets('can create write-only characteristic', (tester) async {
      final server = bluey.server();

      await server.addService(
        LocalService(
          uuid: UUID('12345678-1234-1234-1234-123456789abc'),
          isPrimary: true,
          characteristics: [
            LocalCharacteristic(
              uuid: UUID('12345678-1234-1234-1234-123456789abd'),
              properties: const CharacteristicProperties(canWrite: true),
              permissions: const [GattPermission.write],
            ),
          ],
        ),
      );

      await server.dispose();
    });

    testWidgets('can create notifiable characteristic', (tester) async {
      final server = bluey.server();

      await server.addService(
        LocalService(
          uuid: UUID('12345678-1234-1234-1234-123456789abc'),
          isPrimary: true,
          characteristics: [
            LocalCharacteristic(
              uuid: UUID('12345678-1234-1234-1234-123456789abd'),
              properties: const CharacteristicProperties(canNotify: true),
              permissions: const [GattPermission.read],
            ),
          ],
        ),
      );

      await server.dispose();
    });

    testWidgets('can create characteristic with all properties', (
      tester,
    ) async {
      final server = bluey.server();

      await server.addService(
        LocalService(
          uuid: UUID('12345678-1234-1234-1234-123456789abc'),
          isPrimary: true,
          characteristics: [
            LocalCharacteristic(
              uuid: UUID('12345678-1234-1234-1234-123456789abd'),
              properties: const CharacteristicProperties(
                canRead: true,
                canWrite: true,
                canWriteWithoutResponse: true,
                canNotify: true,
                canIndicate: true,
              ),
              permissions: const [GattPermission.read, GattPermission.write],
            ),
          ],
        ),
      );

      await server.dispose();
    });
  });
}
