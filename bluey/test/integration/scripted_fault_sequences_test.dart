import 'dart:typed_data';

import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';
import '../fakes/test_helpers.dart';

/// Canned scripted fault sequences from the 2026-07-10 audit addendum
/// (R11 / scenarios B.6–B.8), built on the R1 connect seams and the R2
/// fault-rule queue.
void main() {
  group('B.6 — remote peer force-kill profile', () {
    test('sustained write timeouts drive the death watch: dead-peer signals '
        'accumulate, the peer is declared unreachable, the link is torn down',
        () {
      fakeAsync((async) {
        final fakePlatform = FakeBlueyPlatform();
        platform.BlueyPlatform.instance = fakePlatform;
        late Bluey bluey;
        Bluey.create(localIdentity: TestServerIds.localIdentity)
            .then((b) => bluey = b);
        async.flushMicrotasks();

        fakePlatform.simulateBlueyServer(
          address: 'FORCEKILL-PEER',
          serverId: TestServerIds.remoteIdentity,
        );

        final deadSignals = <HeartbeatFailedEvent>[];
        final unreachable = <PeerDeclaredUnreachableEvent>[];

        PeerConnection? peerConn;
        bluey
            .peer(TestServerIds.remoteIdentity)
            .connect()
            .then((c) => peerConn = c);
        async.elapse(const Duration(seconds: 6)); // scan window (I349)
        expect(peerConn, isNotNull);

        bluey.events.listen((event) {
          if (event is HeartbeatFailedEvent && event.isDeadPeerSignal) {
            deadSignals.add(event);
          }
          if (event is PeerDeclaredUnreachableEvent) {
            unreachable.add(event);
          }
        });

        // The remote app is force-killed: no callbacks fire, the OS
        // keeps the link "up", and every write runs into its timeout
        // (ANDROID_BLE_NOTES "Force-Kill Behavior"). Unlimited rule —
        // the peer never comes back.
        fakePlatform.enqueueFault(
          FakeOp.writeCharacteristic,
          const platform.GattOperationTimeoutException('writeCharacteristic'),
          deviceId: 'FORCEKILL-PEER',
          times: null,
        );

        // Heartbeat probes (every lifecycleInterval/2 = 5 s) now fail
        // as dead-peer signals; the death watch declares the peer gone
        // after peerSilenceTimeout (30 s) and tears the link down.
        async.elapse(const Duration(seconds: 40));

        expect(
          deadSignals,
          isNotEmpty,
          reason: 'timed-out heartbeat probes are dead-peer signals',
        );
        expect(unreachable, hasLength(1));
        expect(
          peerConn!.connection.state,
          ConnectionState.disconnected,
          reason: 'the death watch tears the connection down',
        );

        bluey.dispose();
        fakePlatform.dispose();
        async.flushMicrotasks();
      });
    });
  });

  group('B.7 — connect flapping and connection limits', () {
    late FakeBlueyPlatform fakePlatform;
    late Bluey bluey;

    setUp(() async {
      fakePlatform = FakeBlueyPlatform();
      platform.BlueyPlatform.instance = fakePlatform;
      bluey = await Bluey.create();
      fakePlatform.simulatePeripheral(
        id: TestDeviceIds.device1,
        name: 'Flappy',
      );
    });

    tearDown(() async {
      await bluey.dispose();
      await fakePlatform.dispose();
    });

    test('a flaky link that rejects two attempts connects on the third '
        '(app-level retry loop)', () async {
      fakePlatform.enqueueFault(
        FakeOp.connect,
        const platform.PlatformConnectFailedException(
          platform.PlatformConnectFailureReason.unknown,
          status: 133,
        ),
        deviceId: TestDeviceIds.device1,
        times: 2,
      );

      final failures = <ConnectionException>[];
      Connection? connection;
      for (var attempt = 0; attempt < 3 && connection == null; attempt++) {
        try {
          connection = await bluey.connect(
            Device(address: const DeviceAddress(TestDeviceIds.device1)),
          );
        } on ConnectionException catch (e) {
          failures.add(e);
        }
      }

      expect(failures, hasLength(2));
      expect(connection, isNotNull);
      expect(connection!.state, ConnectionState.linked);
      await connection.disconnect();
    });

    test('an exhausted connection budget surfaces as '
        'ConnectionFailureReason.connectionLimitReached', () async {
      fakePlatform.enqueueFault(
        FakeOp.connect,
        const platform.PlatformConnectFailedException(
          platform.PlatformConnectFailureReason.connectionLimitReached,
        ),
        deviceId: TestDeviceIds.device1,
      );

      await expectLater(
        bluey.connect(Device(address: const DeviceAddress(TestDeviceIds.device1))),
        throwsA(
          isA<ConnectionException>().having(
            (e) => e.reason,
            'reason',
            ConnectionFailureReason.connectionLimitReached,
          ),
        ),
      );
    });
  });

  group('B.8 — 512-octet attribute cap (I343 regression)', () {
    test('maxWritePayload clamps to 512 even when the platform over-reports '
        'MTU - 3', () async {
      // iOS over-reports the write-without-response maximum as MTU - 3
      // (514 at MTU 517); the spec caps a single attribute value at 512
      // octets and spec-conforming peers silently truncate the overflow
      // (cross-platform-quirks.md, I343). The domain clamp is what
      // makes chunked-write sizing safe — pin it.
      final fakePlatform = FakeBlueyPlatform();
      platform.BlueyPlatform.instance = fakePlatform;
      final bluey = await Bluey.create();

      fakePlatform.simulatePeripheral(
        id: TestDeviceIds.device1,
        name: 'BigMtu',
        services: [
          TestServiceBuilder(TestUuids.heartRateService)
              .withCharacteristic(
                TestUuids.heartRateMeasurement,
                TestProperties.writeWithoutResponse,
              )
              .build(),
        ],
      );
      fakePlatform.setMaxWriteLengthOverride(
        TestDeviceIds.device1,
        withResponse: 514,
        withoutResponse: 514,
      );

      final connection = await bluey.connect(
        Device(address: const DeviceAddress(TestDeviceIds.device1)),
      );

      final limit = await connection.maxWritePayload(withResponse: false);
      expect(limit.value, equals(512));
      final limitWithResponse =
          await connection.maxWritePayload(withResponse: true);
      expect(limitWithResponse.value, equals(512));

      // A payload sized from the clamped limit round-trips intact.
      final services = await connection.services();
      final characteristic = services.first.characteristics().first;
      final payload = Uint8List.fromList(
        List.generate(limit.value, (i) => i & 0xFF),
      );
      await characteristic.write(payload, withResponse: false);
      expect(
        fakePlatform.writeCharacteristicCalls.single.value,
        equals(payload),
      );

      await connection.disconnect();
      await bluey.dispose();
      await fakePlatform.dispose();
    });
  });
}
