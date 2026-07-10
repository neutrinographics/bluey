import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';
import '../fakes/test_helpers.dart';

/// Connect-phase failure scenarios (audit R1 / NT-1).
///
/// A connection attempt that fails, times out, or is raced must surface
/// as the documented [ConnectionException] with a mapped
/// [ConnectionFailureReason] — not as a generic platform error. These
/// tests drive the fake's connect-phase seams (`simulateConnectFailure`,
/// `holdNextConnect`) through the public `Bluey.connect` API.
void main() {
  const deviceId = TestDeviceIds.device1;

  Device deviceFor(String id) => Device(address: DeviceAddress(id));

  group('Bluey.connect failure scenarios', () {
    late FakeBlueyPlatform fakePlatform;
    late Bluey bluey;

    setUp(() async {
      fakePlatform = FakeBlueyPlatform();
      platform.BlueyPlatform.instance = fakePlatform;
      bluey = await Bluey.create();
      fakePlatform.simulatePeripheral(id: deviceId, name: 'Test Device');
    });

    tearDown(() async {
      await bluey.dispose();
      await fakePlatform.dispose();
    });

    test('simulated connect failure surfaces as ConnectionException '
        'with the mapped reason and device address', () async {
      fakePlatform.simulateConnectFailure(
        deviceId,
        platform.PlatformConnectFailureReason.notConnectable,
        status: 133,
      );

      await expectLater(
        bluey.connect(deviceFor(deviceId)),
        throwsA(
          isA<ConnectionException>()
              .having(
                (e) => e.reason,
                'reason',
                ConnectionFailureReason.deviceNotConnectable,
              )
              .having(
                (e) => e.deviceAddress,
                'deviceAddress',
                const DeviceAddress(deviceId),
              ),
        ),
      );
    });

    test('connect failure is one-shot: a retry connects normally', () async {
      fakePlatform.simulateConnectFailure(
        deviceId,
        platform.PlatformConnectFailureReason.unknown,
      );

      await expectLater(
        bluey.connect(deviceFor(deviceId)),
        throwsA(isA<ConnectionException>()),
      );

      final connection = await bluey.connect(deviceFor(deviceId));
      expect(connection.state, ConnectionState.linked);
      await connection.disconnect();
    });

    test('connect failure targets only the named device', () async {
      const otherId = TestDeviceIds.device2;
      fakePlatform.simulatePeripheral(id: otherId, name: 'Other Device');
      fakePlatform.simulateConnectFailure(
        otherId,
        platform.PlatformConnectFailureReason.unknown,
      );

      final connection = await bluey.connect(deviceFor(deviceId));
      expect(connection.state, ConnectionState.linked);
      await connection.disconnect();
    });

    test('a held connect that exceeds the configured timeout surfaces as '
        'ConnectionException(timeout) — no real waiting', () {
      fakeAsync((async) {
        final fake = FakeBlueyPlatform();
        platform.BlueyPlatform.instance = fake;
        late Bluey blueyFa;
        Bluey.create().then((b) => blueyFa = b);
        async.flushMicrotasks();
        fake.simulatePeripheral(id: deviceId, name: 'Test Device');

        fake.holdNextConnect();

        Object? caught;
        blueyFa
            .connect(deviceFor(deviceId), timeout: const Duration(seconds: 5))
            .catchError((Object e) {
          caught = e;
          throw e; // keep the future in an error state for hygiene
        }).ignore();
        async.flushMicrotasks();

        // Before the timeout elapses nothing has fired.
        async.elapse(const Duration(seconds: 4));
        expect(caught, isNull);

        // Crossing the timeout fails the held connect.
        async.elapse(const Duration(seconds: 2));
        expect(caught, isA<ConnectionException>());
        expect(
          (caught as ConnectionException).reason,
          ConnectionFailureReason.timeout,
        );

        blueyFa.dispose();
        fake.dispose();
        async.flushMicrotasks();
      });
    });

    test('a held connect that is resolved completes the connection normally',
        () async {
      fakePlatform.holdNextConnect();

      final pending = bluey.connect(deviceFor(deviceId));
      await Future<void>.delayed(Duration.zero);

      fakePlatform.resolveHeldConnect();
      final connection = await pending;

      expect(connection.state, ConnectionState.linked);
      await connection.disconnect();
    });

    test('a held connect failed via the seam surfaces the injected error '
        'translated', () async {
      fakePlatform.holdNextConnect();

      final pending = bluey.connect(deviceFor(deviceId));
      await Future<void>.delayed(Duration.zero);

      fakePlatform.failHeldConnect(
        const platform.PlatformConnectFailedException(
          platform.PlatformConnectFailureReason.deviceNotFound,
        ),
      );

      await expectLater(
        pending,
        throwsA(
          isA<ConnectionException>().having(
            (e) => e.reason,
            'reason',
            ConnectionFailureReason.deviceNotFound,
          ),
        ),
      );
    });
  });
}
