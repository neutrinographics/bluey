import 'dart:typed_data';

import 'package:bluey/bluey.dart';
import 'package:bluey/src/connection/bluey_connection.dart';
import 'package:bluey/src/connection/lifecycle_client.dart';
import 'package:bluey/src/lifecycle.dart' as lifecycle;
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';
import '../fakes/test_helpers.dart';

/// Verifies that successful GATT ops on the connection record
/// activity on the lifecycle client. Task 4 covers connection-level
/// methods (services, requestMtu, readRssi); Task 5 adds tests for
/// remote characteristic / descriptor ops via direct construction.
void main() {
  late FakeBlueyPlatform fakePlatform;

  setUp(() {
    fakePlatform = FakeBlueyPlatform();
    platform.BlueyPlatform.instance = fakePlatform;
  });

  group('BlueyConnection activity — own methods', () {
    test('requestMtu on success records activity so the probe deadline resets',
        () {
      fakeAsync((async) {
        fakePlatform.simulateBlueyServer(
          address: TestDeviceIds.device1,
          serverId: ServerId.generate(),
        );

        final bluey = Bluey();
        late Connection conn;
        bluey
            .connect(Device(
              id: UUID('00000000-0000-0000-0000-aabbccddee01'),
              address: TestDeviceIds.device1,
              name: 'Test Device',
            ))
            .then((c) => conn = c);
        async.flushMicrotasks();

        // Let the initial heartbeat + interval read settle so the
        // periodic timer is up with a known activity baseline.
        async.elapse(const Duration(seconds: 3));
        async.flushMicrotasks();

        // Baseline: clear prior heartbeats.
        fakePlatform.writeCharacteristicCalls.clear();

        // requestMtu — records activity on success.
        conn.requestMtu(Mtu(247, capabilities: platform.Capabilities.android));
        async.flushMicrotasks();

        // Advance just under one activity window (4s of 5s). The deadline-
        // driven scheduler reset the probe deadline to T+5s when requestMtu
        // recorded activity, so at T+4s no probe has fired yet.
        async.elapse(const Duration(seconds: 4));
        async.flushMicrotasks();

        final heartbeatWrites = fakePlatform.writeCharacteristicCalls.where(
          (c) => c.characteristicUuid == lifecycle.heartbeatCharUuid,
        );
        expect(heartbeatWrites, isEmpty,
            reason: 'within the activity window after requestMtu, no probe');

        conn.disconnect();
        bluey.dispose();
        async.flushMicrotasks();
      });
    });
  });

  group('BlueyRemoteCharacteristic activity hook', () {
    LifecycleClient buildStartedLifecycle() {
      final lc = LifecycleClient(
        platformApi: fakePlatform,
        connectionId: TestDeviceIds.device1,
        peerSilenceTimeout: const Duration(seconds: 20),
        onServerUnreachable: () {},
      )..debugStartForTest();
      return lc;
    }

    test('write records activity on success', () async {
      fakePlatform.simulatePeripheral(
        id: TestDeviceIds.device1,
        name: 'Test',
        services: [
          TestServiceBuilder(TestUuids.customService)
              .withWritable(TestUuids.customChar1)
              .build(),
        ],
      );
      await fakePlatform.connect(
        TestDeviceIds.device1,
        const platform.PlatformConnectConfig(timeoutMs: null, mtu: null),
      );

      final lc = buildStartedLifecycle();
      final char = BlueyRemoteCharacteristic(
        platform: fakePlatform,
        connectionId: TestDeviceIds.device1,
        deviceId: UUID('00000000-0000-0000-0000-aabbccddee01'),
        uuid: UUID(TestUuids.customChar1),
        handle: AttributeHandle(1),
        properties: const CharacteristicProperties(
          canRead: false,
          canWrite: true,
          canWriteWithoutResponse: false,
          canNotify: false,
          canIndicate: false,
        ),
        descriptors: const [],
        lifecycleClient: () => lc,
      );

      await char.write(Uint8List.fromList([0x42]));
      expect(lc.lastActivityAtForTest, isNotNull,
          reason: 'successful write must record activity on lifecycle');
      lc.stop();
    });

    test('BlueyRemoteCharacteristic.read records activity on success',
        () async {
      fakePlatform.simulatePeripheral(
        id: TestDeviceIds.device1,
        name: 'Test',
        services: [
          TestServiceBuilder(TestUuids.customService)
              .withReadable(TestUuids.customChar1)
              .build(),
        ],
        characteristicValues: {
          TestUuids.customChar1: Uint8List.fromList([0x77]),
        },
      );
      await fakePlatform.connect(
        TestDeviceIds.device1,
        const platform.PlatformConnectConfig(timeoutMs: null, mtu: null),
      );

      final lc = buildStartedLifecycle();
      final char = BlueyRemoteCharacteristic(
        platform: fakePlatform,
        connectionId: TestDeviceIds.device1,
        deviceId: UUID('00000000-0000-0000-0000-aabbccddee01'),
        uuid: UUID(TestUuids.customChar1),
        handle: AttributeHandle(1),
        properties: const CharacteristicProperties(
          canRead: true,
          canWrite: false,
          canWriteWithoutResponse: false,
          canNotify: false,
          canIndicate: false,
        ),
        descriptors: const [],
        lifecycleClient: () => lc,
      );

      await char.read();
      expect(lc.lastActivityAtForTest, isNotNull);
      lc.stop();
    });

    test('BlueyRemoteCharacteristic.write failure does NOT record activity',
        () async {
      fakePlatform.simulatePeripheral(
        id: TestDeviceIds.device1,
        name: 'Test',
        services: [
          TestServiceBuilder(TestUuids.customService)
              .withWritable(TestUuids.customChar1)
              .build(),
        ],
      );
      await fakePlatform.connect(
        TestDeviceIds.device1,
        const platform.PlatformConnectConfig(timeoutMs: null, mtu: null),
      );
      fakePlatform.simulateWriteTimeout = true;

      final lc = buildStartedLifecycle();
      final char = BlueyRemoteCharacteristic(
        platform: fakePlatform,
        connectionId: TestDeviceIds.device1,
        deviceId: UUID('00000000-0000-0000-0000-aabbccddee01'),
        uuid: UUID(TestUuids.customChar1),
        handle: AttributeHandle(1),
        properties: const CharacteristicProperties(
          canRead: false,
          canWrite: true,
          canWriteWithoutResponse: false,
          canNotify: false,
          canIndicate: false,
        ),
        descriptors: const [],
        lifecycleClient: () => lc,
      );

      await expectLater(
        () => char.write(Uint8List.fromList([0x42])),
        throwsA(isA<GattTimeoutException>()),
      );
      expect(lc.lastActivityAtForTest, isNull);

      fakePlatform.simulateWriteTimeout = false;
      lc.stop();
    });
  }); // end group('BlueyRemoteCharacteristic activity hook')

  group('BlueyConnection user-op wrapping (I097)', () {
    BlueyRemoteCharacteristic buildWritableChar(LifecycleClient lc) {
      return BlueyRemoteCharacteristic(
        platform: fakePlatform,
        connectionId: TestDeviceIds.device1,
        deviceId: UUID('00000000-0000-0000-0000-aabbccddee01'),
        uuid: UUID(TestUuids.customChar1),
        handle: AttributeHandle(1),
        properties: const CharacteristicProperties(
          canRead: false,
          canWrite: true,
          canWriteWithoutResponse: false,
          canNotify: false,
          canIndicate: false,
        ),
        descriptors: const [],
        lifecycleClient: () => lc,
      );
    }

    Future<void> setupWritablePeripheral() async {
      fakePlatform.simulatePeripheral(
        id: TestDeviceIds.device1,
        name: 'Test',
        services: [
          TestServiceBuilder(TestUuids.customService)
              .withWritable(TestUuids.customChar1)
              .build(),
        ],
      );
      await fakePlatform.connect(
        TestDeviceIds.device1,
        const platform.PlatformConnectConfig(timeoutMs: null, mtu: null),
      );
    }

    LifecycleClient newStartedLifecycle() {
      return LifecycleClient(
        platformApi: fakePlatform,
        connectionId: TestDeviceIds.device1,
        peerSilenceTimeout: const Duration(seconds: 20),
        onServerUnreachable: () {},
      )..debugStartForTest();
    }

    test('user op success wraps with start/end and records activity',
        () async {
      await setupWritablePeripheral();
      final lc = newStartedLifecycle();
      final char = buildWritableChar(lc);

      final write = char.write(Uint8List.fromList([0x42]));
      // While the await is in flight, the counter is incremented.
      expect(lc.pendingUserOpsForTest, 1,
          reason: 'markUserOpStarted ran before the body awaited');
      await write;

      expect(lc.pendingUserOpsForTest, 0,
          reason: 'markUserOpEnded ran after the body returned');
      expect(lc.lastActivityAtForTest, isNotNull);
      expect(lc.firstFailureAtForTest, isNull,
          reason: 'success path must not arm the silence detector');

      lc.stop();
    });

    test('user op timeout wraps with start/end and arms the silence detector',
        () async {
      await setupWritablePeripheral();
      fakePlatform.simulateWriteTimeout = true;

      final lc = newStartedLifecycle();
      final char = buildWritableChar(lc);

      await expectLater(
        () => char.write(Uint8List.fromList([0x42])),
        throwsA(isA<GattTimeoutException>()),
        reason: 'translated domain exception still propagates to caller',
      );

      expect(lc.pendingUserOpsForTest, 0,
          reason: 'markUserOpEnded ran in finally even on failure');
      expect(lc.lastActivityAtForTest, isNull);
      expect(lc.firstFailureAtForTest, isNotNull,
          reason: 'timeout user op must arm the silence detector');

      fakePlatform.simulateWriteTimeout = false;
      lc.stop();
    });

    test(
        'user op status-failed wraps with start/end but does not arm the '
        'silence detector', () async {
      await setupWritablePeripheral();
      fakePlatform.simulateWriteStatusFailed = 0x03;

      final lc = newStartedLifecycle();
      final char = buildWritableChar(lc);

      await expectLater(
        () => char.write(Uint8List.fromList([0x42])),
        throwsA(isA<GattOperationFailedException>()),
      );

      expect(lc.pendingUserOpsForTest, 0);
      expect(lc.lastActivityAtForTest, isNull);
      expect(lc.firstFailureAtForTest, isNull,
          reason:
              'non-timeout user-op failure is filtered out of recordUserOpFailure');

      fakePlatform.simulateWriteStatusFailed = null;
      lc.stop();
    });

    test(
        'characteristic constructed before upgrade picks up lifecycle once '
        'installed', () async {
      // Regression for I097: a characteristic may be constructed before
      // an external LifecycleClient is wired up (e.g. by a peer-protocol
      // wrapper that installs activity feedback after service discovery).
      // If the characteristic captured the (null) lifecycle by value at
      // construction time, user ops on those cached characteristics
      // would never feed the silence detector — the exact behaviour
      // I097 was meant to fix. The `lifecycleClient` parameter is a
      // getter for this reason.
      await setupWritablePeripheral();

      LifecycleClient? installedLifecycle;
      final char = BlueyRemoteCharacteristic(
        platform: fakePlatform,
        connectionId: TestDeviceIds.device1,
        deviceId: UUID('00000000-0000-0000-0000-aabbccddee01'),
        uuid: UUID(TestUuids.customChar1),
        handle: AttributeHandle(1),
        properties: const CharacteristicProperties(
          canRead: false,
          canWrite: true,
          canWriteWithoutResponse: false,
          canNotify: false,
          canIndicate: false,
        ),
        descriptors: const [],
        lifecycleClient: () => installedLifecycle,
      );

      // Before "upgrade" — getter returns null, write succeeds without
      // recording anything anywhere.
      await char.write(Uint8List.fromList([0x01]));

      // Simulate upgrade by installing a started lifecycle.
      installedLifecycle = newStartedLifecycle();

      // Now a write should feed activity into the lifecycle.
      await char.write(Uint8List.fromList([0x02]));
      expect(installedLifecycle.lastActivityAtForTest, isNotNull,
          reason:
              'characteristic must read lifecycleClient at call time so it '
              'picks up the lifecycle installed after construction');

      installedLifecycle.stop();
    });
  }); // end group('BlueyConnection user-op wrapping (I097)')
}
