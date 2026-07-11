import 'dart:typed_data';

import 'package:bluey/bluey.dart';
import 'package:bluey/src/lifecycle.dart' as lifecycle;
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';
import '../fakes/test_helpers.dart';

/// Networking-scenario coverage from the 2026-07-10 audit addendum
/// (R10 / scenarios A.1–A.5): peer identity across address rotation,
/// identity change under a stable address, the heartbeat-silence
/// boundary race, hostile peer inputs, and the duplicate-UUID
/// notification demux hazard.
void main() {
  group('A.1 — peer identity survives address rotation', () {
    test('the same ServerId reconnects after re-advertising at a new address',
        () {
      // Virtual time so the scan/probe machinery is deterministic.
      // (Post-I349, connect completes as soon as the peer is found —
      // the generous elapses below are upper bounds, not waits.)
      fakeAsync((async) {
        final fakePlatform = FakeBlueyPlatform();
        platform.BlueyPlatform.instance = fakePlatform;
        late Bluey bluey;
        Bluey.create(localIdentity: TestServerIds.localIdentity)
            .then((b) => bluey = b);
        async.flushMicrotasks();

        // The peer first appears at address X (e.g. an iOS device whose
        // identifier is stable for this connection)...
        fakePlatform.simulateBlueyServer(
          address: 'ADDR-BEFORE-ROTATION',
          serverId: TestServerIds.remoteIdentity,
        );

        final peer = bluey.peer(TestServerIds.remoteIdentity);
        PeerConnection? first;
        peer.connect().then((c) => first = c);
        async.elapse(const Duration(seconds: 6));
        expect(first, isNotNull);
        expect(
          first!.connection.deviceAddress,
          const DeviceAddress('ADDR-BEFORE-ROTATION'),
        );
        first!.disconnect();
        async.elapse(const Duration(seconds: 2));

        // ...then drops and re-advertises under a rotated address (iOS
        // mints a random address per connection; IOS_BLE_NOTES
        // limitation 9). The stable ServerId is the only continuity.
        fakePlatform.removePeripheral('ADDR-BEFORE-ROTATION');
        fakePlatform.simulateBlueyServer(
          address: 'ADDR-AFTER-ROTATION',
          serverId: TestServerIds.remoteIdentity,
        );

        PeerConnection? second;
        peer.connect().then((c) => second = c);
        async.elapse(const Duration(seconds: 6));
        expect(second, isNotNull);
        expect(second!.serverId, equals(TestServerIds.remoteIdentity));
        expect(
          second!.connection.deviceAddress,
          const DeviceAddress('ADDR-AFTER-ROTATION'),
          reason: 'the peer was found at its new address by identity, '
              'not by remembered address',
        );

        second!.disconnect();
        bluey.dispose();
        fakePlatform.dispose();
        async.flushMicrotasks();
      });
    });
  });

  group('A.2 — ServerId changes under a stable address', () {
    test('peer-targeted connect refuses an address now serving a different '
        'identity (PeerNotFoundException at scan timeout)', () {
      fakeAsync((async) {
        final fakePlatform = FakeBlueyPlatform();
        platform.BlueyPlatform.instance = fakePlatform;
        late Bluey bluey;
        Bluey.create(localIdentity: TestServerIds.localIdentity)
            .then((b) => bluey = b);
        async.flushMicrotasks();

        // The address is alive but its app reinstalled / regenerated
        // identity: it now serves thirdParty, not remoteIdentity.
        fakePlatform.simulateBlueyServer(
          address: 'ADDR-STABLE',
          serverId: TestServerIds.thirdParty,
        );

        Object? error;
        bluey
            .peer(TestServerIds.remoteIdentity)
            .connect(scanTimeout: const Duration(seconds: 2))
            .then<void>((_) => fail('must not connect to the wrong identity'))
            .catchError((Object e) {
          error = e;
        });
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 3));

        expect(error, isA<PeerNotFoundException>());

        bluey.dispose();
        fakePlatform.dispose();
        async.flushMicrotasks();
      });
    });

    test('connectAsPeer adopts whatever identity the address serves now '
        '(pins current behavior — no mismatch signal exists yet)', () async {
      // Documents the A.2 design gap: PeerIdentityMismatchException is
      // defined but nothing constructs it. An address-based connect
      // reads the identity fresh and hands it to the caller; comparing
      // against a remembered identity is the caller's job today.
      final fakePlatform = FakeBlueyPlatform();
      platform.BlueyPlatform.instance = fakePlatform;
      final bluey = await Bluey.create(
        localIdentity: TestServerIds.localIdentity,
      );

      fakePlatform.simulateBlueyServer(
        address: 'ADDR-STABLE',
        serverId: TestServerIds.thirdParty,
      );

      final peerConn = await bluey.connectAsPeer(
        Device(address: const DeviceAddress('ADDR-STABLE')),
      );
      expect(peerConn.serverId, equals(TestServerIds.thirdParty));

      await peerConn.disconnect();
      await bluey.dispose();
      await fakePlatform.dispose();
    });
  });

  group('A.3 — heartbeat-silence boundary', () {
    const interval = Duration(seconds: 10);
    const central = TestDeviceIds.central1;

    test('a heartbeat just before the boundary re-arms; crossing it emits '
        'the advisory timeout without evicting the client', () async {
      final fakePlatform = FakeBlueyPlatform();
      platform.BlueyPlatform.instance = fakePlatform;
      final bluey = await Bluey.create();

      fakeAsync((async) {
        final server = bluey.server(lifecycleInterval: interval)!;
        server.startAdvertising(name: 'boundary');
        async.flushMicrotasks();

        final timeouts = <ClientLifecycleTimeoutEvent>[];
        bluey.events
            .where((e) => e is ClientLifecycleTimeoutEvent)
            .cast<ClientLifecycleTimeoutEvent>()
            .listen(timeouts.add);
        final gone = <ClientAddress>[];
        server.disconnections.listen(gone.add);

        fakePlatform.simulateCentralConnection(centralId: central);
        async.flushMicrotasks();

        // Arm the silence timer, then heartbeat again just before the
        // boundary: the timer must re-arm, not fire.
        fakePlatform.fireLifecycleSilence(central);
        async.flushMicrotasks();
        async.elapse(interval - const Duration(milliseconds: 1));
        expect(timeouts, isEmpty, reason: 'boundary not yet crossed');

        fakePlatform.fireLifecycleSilence(central);
        async.flushMicrotasks();
        async.elapse(interval - const Duration(milliseconds: 1));
        expect(
          timeouts,
          isEmpty,
          reason: 'the near-boundary heartbeat re-armed the timer',
        );

        // Now cross it.
        async.elapse(const Duration(milliseconds: 2));
        expect(timeouts, hasLength(1));
        expect(
          gone,
          isEmpty,
          reason: 'silence is advisory on an authoritative platform '
              '(reportsCentralDisconnects=true) — no eviction',
        );
        expect(server.connectedClients, hasLength(1));

        // A late heartbeat after the advisory re-arms cleanly: the
        // paused peer resumed. Another full silence fires again.
        fakePlatform.fireLifecycleSilence(central);
        async.flushMicrotasks();
        async.elapse(interval + const Duration(milliseconds: 1));
        expect(timeouts, hasLength(2));
        expect(gone, isEmpty);

        server.dispose();
        bluey.dispose();
        fakePlatform.dispose();
        async.flushMicrotasks();
      });
    });
  });

  group('A.4 — hostile peer inputs over a real link', () {
    test('malformed and wrong-version lifecycle writes are dropped without '
        'disturbing the server', () async {
      final serverFake = FakeBlueyPlatform();
      platform.BlueyPlatform.instance = serverFake;
      final serverBluey = await Bluey.create(
        localIdentity: TestServerIds.remoteIdentity,
      );
      final server = serverBluey.server()!;

      final clientFake = FakeBlueyPlatform();
      platform.BlueyPlatform.instance = clientFake;
      final clientBluey = await Bluey.create();

      final link = FakeBleLink(
        central: clientFake,
        peripheral: serverFake,
        deviceId: 'hostile-target',
        centralId: 'hostile-client',
      );

      await server.startAdvertising(name: 'victim');
      link.announce();

      final appRequests = <WriteRequest>[];
      final sub = server.writeRequests.listen(appRequests.add);

      // A raw (non-peer) client connects and writes garbage straight at
      // the lifecycle control characteristics.
      final connection = await clientBluey.connect(
        Device(address: const DeviceAddress('hostile-target')),
      );
      final controlService = (await connection.services()).firstWhere(
        (s) => s.uuid == UUID(lifecycle.controlServiceUuid),
      );
      final heartbeatChar = controlService
          .characteristics(uuid: UUID(lifecycle.heartbeatCharUuid))
          .first;

      // Not even a valid header.
      await heartbeatChar.write(Uint8List.fromList([0xDE, 0xAD]));

      // Valid message shape, unsupported protocol version.
      final wrongVersion = lifecycle.lifecycleCodec.encodeMessage(
        lifecycle.Heartbeat(TestServerIds.thirdParty),
      );
      wrongVersion[0] = 0x7F;
      await heartbeatChar.write(wrongVersion);

      await Future<void>.delayed(Duration.zero);

      expect(
        appRequests,
        isEmpty,
        reason: 'control-service garbage is dropped by the lifecycle '
            'layer, never leaked to the app',
      );
      expect(server.connectedClients, hasLength(1),
          reason: 'the server survives hostile input with the link up');

      // The server still functions: the serverId characteristic answers
      // a legitimate read with the real identity.
      final serverIdChar = controlService
          .characteristics(uuid: UUID(lifecycle.serverIdCharUuid))
          .first;
      final identityBytes = await serverIdChar.read();
      expect(
        lifecycle.lifecycleCodec.decodeAdvertisedIdentity(identityBytes),
        equals(TestServerIds.remoteIdentity),
      );

      await sub.cancel();
      await connection.disconnect();
      await server.dispose();
      await serverBluey.dispose();
      await clientBluey.dispose();
      await serverFake.dispose();
      await clientFake.dispose();
    });
  });

  group('A.5 — duplicate-UUID notification demux (DA-02)', () {
    test('a notification for a duplicated UUID cross-delivers to every '
        'instance (pins the current hazard)', () async {
      // DA-02: PlatformNotification carries no handle, so the domain
      // demuxes by UUID string. Two characteristic instances sharing a
      // UUID cannot be told apart on the notification path — both
      // streams receive every notification for that UUID. This test
      // pins the hazard so any future fix (handle-carrying
      // notifications) must consciously flip these assertions.
      final fakePlatform = FakeBlueyPlatform();
      platform.BlueyPlatform.instance = fakePlatform;
      final bluey = await Bluey.create();

      const dupUuid = TestUuids.heartRateMeasurement;
      fakePlatform.simulatePeripheral(
        id: TestDeviceIds.device1,
        name: 'Dup Device',
        services: [
          TestServiceBuilder(TestUuids.heartRateService)
              .withNotifiable(dupUuid)
              .build(),
          TestServiceBuilder(TestUuids.batteryService)
              .withNotifiable(dupUuid)
              .build(),
        ],
      );

      final connection = await bluey.connect(
        Device(address: const DeviceAddress(TestDeviceIds.device1)),
      );
      final services = await connection.services();
      final instanceA = services[0].characteristics().single;
      final instanceB = services[1].characteristics().single;
      expect(instanceA.handle, isNot(equals(instanceB.handle)),
          reason: 'distinct instances under distinct services');

      final receivedA = <Uint8List>[];
      final receivedB = <Uint8List>[];
      final subA = instanceA.notifications.listen(receivedA.add);
      final subB = instanceB.notifications.listen(receivedB.add);
      await Future<void>.delayed(Duration.zero);

      fakePlatform.simulateNotification(
        deviceId: TestDeviceIds.device1,
        characteristicUuid: dupUuid,
        value: Uint8List.fromList([0x55]),
      );
      await Future<void>.delayed(Duration.zero);

      expect(receivedA, hasLength(1));
      expect(
        receivedB,
        hasLength(1),
        reason: 'DA-02 cross-delivery: instance B receives a notification '
            'that may have been meant only for instance A',
      );

      await subA.cancel();
      await subB.cancel();
      await bluey.dispose();
      await fakePlatform.dispose();
    });
  });
}
