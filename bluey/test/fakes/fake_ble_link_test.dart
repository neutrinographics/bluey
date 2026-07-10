import 'dart:typed_data';

import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import 'fake_platform.dart';
import 'test_helpers.dart';

/// Contract tests for [FakeBleLink] (audit R4 / NT-6): a virtual BLE
/// link cross-wiring two [FakeBlueyPlatform]s so that two *real* Bluey
/// endpoints — one acting as GATT server, one as client — exchange
/// traffic end-to-end: client writes/reads surface as real server
/// requests, server responses complete the client's futures, server
/// notifications land on the client's characteristic streams, and
/// disconnects propagate both ways.
void main() {
  const deviceId = 'link-server-as-device';
  const centralId = 'link-client-as-central';

  final serviceUuid = UUID(TestUuids.heartRateService);
  final charUuid = UUID(TestUuids.heartRateMeasurement);

  late FakeBlueyPlatform serverFake;
  late FakeBlueyPlatform clientFake;
  late Bluey serverBluey;
  late Bluey clientBluey;
  late Server server;
  late FakeBleLink link;

  setUp(() async {
    serverFake = FakeBlueyPlatform();
    platform.BlueyPlatform.instance = serverFake;
    serverBluey = await Bluey.create();
    server = serverBluey.server()!;

    clientFake = FakeBlueyPlatform();
    platform.BlueyPlatform.instance = clientFake;
    clientBluey = await Bluey.create();

    link = FakeBleLink(
      central: clientFake,
      peripheral: serverFake,
      deviceId: deviceId,
      centralId: centralId,
    );
  });

  tearDown(() async {
    await server.dispose();
    await serverBluey.dispose();
    await clientBluey.dispose();
    await serverFake.dispose();
    await clientFake.dispose();
  });

  Future<void> hostAndAnnounce(HostedCharacteristic characteristic) async {
    await server.addService(
      HostedService(uuid: serviceUuid, characteristics: [characteristic]),
    );
    await server.startAdvertising(name: 'Link Server');
    link.announce();
  }

  Future<Connection> connectClient() =>
      clientBluey.connect(Device(address: const DeviceAddress(deviceId)));

  group('FakeBleLink', () {
    test('client connect surfaces as a real server connection', () async {
      await hostAndAnnounce(HostedCharacteristic.writable(uuid: charUuid));

      final clients = <Client>[];
      final sub = server.connections.listen(clients.add);

      final connection = await connectClient();
      await Future<void>.delayed(Duration.zero);

      expect(connection.state, ConnectionState.linked);
      expect(clients, hasLength(1));
      expect(server.connectedClients, hasLength(1));

      await sub.cancel();
    });

    test('client write arrives as a WriteRequest and the server response '
        'completes the write', () async {
      await hostAndAnnounce(HostedCharacteristic.writable(uuid: charUuid));

      final received = <WriteRequest>[];
      final sub = server.writeRequests.listen((request) {
        received.add(request);
        server.respondToWrite(request, status: GattResponseStatus.success);
      });

      final connection = await connectClient();
      // Select by UUID: the server also hosts the Bluey lifecycle
      // control service, so `.first` would grab that instead.
      final characteristic = (await connection.services())
          .firstWhere((s) => s.uuid == serviceUuid)
          .characteristics()
          .first;

      await characteristic.write(Uint8List.fromList([0x42, 0x43]));

      expect(received, hasLength(1));
      expect(received.single.value, equals([0x42, 0x43]));
      expect(received.single.characteristicId, equals(charUuid));

      await sub.cancel();
    });

    test('a server error response fails the client write with a typed '
        'exception', () async {
      await hostAndAnnounce(HostedCharacteristic.writable(uuid: charUuid));

      final sub = server.writeRequests.listen((request) {
        server.respondToWrite(
          request,
          status: GattResponseStatus.writeNotPermitted,
        );
      });

      final connection = await connectClient();
      // Select by UUID: the server also hosts the Bluey lifecycle
      // control service, so `.first` would grab that instead.
      final characteristic = (await connection.services())
          .firstWhere((s) => s.uuid == serviceUuid)
          .characteristics()
          .first;

      await expectLater(
        characteristic.write(Uint8List.fromList([0x01])),
        throwsA(isA<BlueyException>()),
      );

      await sub.cancel();
    });

    test('client read is answered by the server', () async {
      await hostAndAnnounce(HostedCharacteristic.readable(uuid: charUuid));

      final sub = server.readRequests.listen((request) {
        server.respondToRead(
          request,
          status: GattResponseStatus.success,
          value: Uint8List.fromList([0x99]),
        );
      });

      final connection = await connectClient();
      // Select by UUID: the server also hosts the Bluey lifecycle
      // control service, so `.first` would grab that instead.
      final characteristic = (await connection.services())
          .firstWhere((s) => s.uuid == serviceUuid)
          .characteristics()
          .first;

      expect(await characteristic.read(), equals([0x99]));

      await sub.cancel();
    });

    test('server notify lands on the subscribed client characteristic '
        'stream', () async {
      await hostAndAnnounce(HostedCharacteristic.notifiable(uuid: charUuid));

      final connection = await connectClient();
      // Select by UUID: the server also hosts the Bluey lifecycle
      // control service, so `.first` would grab that instead.
      final characteristic = (await connection.services())
          .firstWhere((s) => s.uuid == serviceUuid)
          .characteristics()
          .first;

      final received = <Uint8List>[];
      final sub = characteristic.notifications.listen(received.add);
      await Future<void>.delayed(Duration.zero);

      await server.notify(charUuid, data: Uint8List.fromList([0x07]));
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(1));
      expect(received.single, equals([0x07]));

      await sub.cancel();
    });

    test('server notify does NOT reach an unsubscribed client', () async {
      await hostAndAnnounce(HostedCharacteristic.notifiable(uuid: charUuid));

      final connection = await connectClient();
      // Select by UUID: the server also hosts the Bluey lifecycle
      // control service, so `.first` would grab that instead.
      final characteristic = (await connection.services())
          .firstWhere((s) => s.uuid == serviceUuid)
          .characteristics()
          .first;

      final received = <Uint8List>[];
      // Listen at the platform level WITHOUT subscribing through the
      // domain API (no CCCD write) — nothing should be delivered.
      final sub =
          clientFake.notificationStream(deviceId).listen(
                (n) => received.add(n.value),
              );

      await server.notify(charUuid, data: Uint8List.fromList([0x07]));
      await Future<void>.delayed(Duration.zero);

      expect(received, isEmpty);

      await sub.cancel();
      // Silence the unused-variable lint without touching the link state.
      expect(characteristic, isNotNull);
    });

    test('client disconnect propagates to the server as a client '
        'disconnection', () async {
      await hostAndAnnounce(HostedCharacteristic.writable(uuid: charUuid));

      final gone = <ClientAddress>[];
      final sub = server.disconnections.listen(gone.add);

      final connection = await connectClient();
      await Future<void>.delayed(Duration.zero);
      expect(server.connectedClients, hasLength(1));

      await connection.disconnect();
      await Future<void>.delayed(Duration.zero);

      expect(gone, hasLength(1));
      expect(gone.single.value, equals(centralId));
      expect(server.connectedClients, isEmpty);

      await sub.cancel();
    });

    test('connectAsPeer runs the real lifecycle protocol end-to-end: the '
        'client learns the server\'s actual ServerId over the link',
        () async {
      // Rebuild the server endpoint with a local identity so the real
      // LifecycleServer answers the serverId read on the control service.
      await server.dispose();
      await serverBluey.dispose();
      platform.BlueyPlatform.instance = serverFake;
      serverBluey = await Bluey.create(
        localIdentity: TestServerIds.remoteIdentity,
      );
      server = serverBluey.server()!;

      // The client needs its own identity to run the peer protocol.
      await clientBluey.dispose();
      platform.BlueyPlatform.instance = clientFake;
      clientBluey = await Bluey.create(
        localIdentity: TestServerIds.localIdentity,
      );

      await hostAndAnnounce(HostedCharacteristic.writable(uuid: charUuid));

      final peer = await clientBluey.connectAsPeer(
        Device(address: const DeviceAddress(deviceId)),
      );

      expect(peer.serverId, equals(TestServerIds.remoteIdentity));

      await peer.disconnect();
      await Future<void>.delayed(Duration.zero);
      expect(server.connectedClients, isEmpty);
    });

    test('server close propagates to the client as a link drop', () async {
      await hostAndAnnounce(HostedCharacteristic.writable(uuid: charUuid));

      final connection = await connectClient();
      await Future<void>.delayed(Duration.zero);
      expect(connection.state, ConnectionState.linked);

      await server.dispose();
      await Future<void>.delayed(Duration.zero);

      expect(connection.state, ConnectionState.disconnected);
    });
  });
}
