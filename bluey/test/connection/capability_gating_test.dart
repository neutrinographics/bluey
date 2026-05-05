import 'dart:typed_data';

import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';
import '../fakes/test_helpers.dart';

void main() {
  Device deviceFor(String address) => Device(
    id: UUID('00000000-0000-0000-0000-aabbccddee01'),
    address: address,
    name: 'Test Device',
  );

  Future<({Connection conn, Bluey bluey})> connectWith(
    platform.Capabilities caps,
  ) async {
    final fakePlatform = FakeBlueyPlatform(capabilities: caps);
    platform.BlueyPlatform.instance = fakePlatform;
    fakePlatform.simulatePeripheral(id: TestDeviceIds.device1, name: 'Test');
    final bluey = Bluey();
    final conn = await bluey.connect(deviceFor(TestDeviceIds.device1));
    return (conn: conn, bluey: bluey);
  }

  group('connection.android / connection.ios — platform-kind getters', () {
    test('connection.android is non-null when platformKind=android', () async {
      final r = await connectWith(platform.Capabilities.android);
      expect(r.conn.android, isNotNull);
      expect(r.conn.ios, isNull);
      await r.conn.disconnect();
      r.bluey.dispose();
    });

    test('connection.ios is non-null when platformKind=ios', () async {
      final r = await connectWith(platform.Capabilities.iOS);
      expect(r.conn.ios, isNotNull);
      expect(r.conn.android, isNull);
      await r.conn.disconnect();
      r.bluey.dispose();
    });

    test('platformKind=fake exposes neither extension', () async {
      final r = await connectWith(platform.Capabilities.fake);
      expect(r.conn.android, isNull);
      expect(r.conn.ios, isNull);
      await r.conn.disconnect();
      r.bluey.dispose();
    });

    test('platformKind=other exposes neither extension', () async {
      final r = await connectWith(
        const platform.Capabilities(
          platformKind: platform.PlatformKind.other,
          canScan: true,
          canConnect: true,
        ),
      );
      expect(r.conn.android, isNull);
      expect(r.conn.ios, isNull);
      await r.conn.disconnect();
      r.bluey.dispose();
    });
  });

  group('BlueyConnection.requestMtu gating', () {
    test('succeeds when canRequestMtu=true', () async {
      final r = await connectWith(platform.Capabilities.android);
      final negotiated = await r.conn.android!.requestMtu(
        Mtu(247, capabilities: platform.Capabilities.android),
      );
      expect(negotiated.value, greaterThan(0));
      await r.conn.disconnect();
      r.bluey.dispose();
    });
  });

  group('AndroidConnectionExtensions — capability gating', () {
    // Build an Android-flavored fake with each flag individually false.
    platform.Capabilities androidWith({
      bool canBond = true,
      bool canRequestPhy = true,
      bool canRequestConnectionParameters = true,
    }) => platform.Capabilities(
      platformKind: platform.PlatformKind.android,
      canScan: true,
      canConnect: true,
      canAdvertise: true,
      canRequestMtu: true,
      maxMtu: 517,
      canBond: canBond,
      canRequestPhy: canRequestPhy,
      canRequestConnectionParameters: canRequestConnectionParameters,
    );

    group('canBond=false', () {
      test('bond() throws', () async {
        final r = await connectWith(androidWith(canBond: false));
        expect(
          () => r.conn.android!.bond(),
          throwsA(
            isA<UnsupportedOperationException>().having(
              (e) => e.operation,
              'operation',
              'bond',
            ),
          ),
        );
        await r.conn.disconnect();
        r.bluey.dispose();
      });

      test('removeBond() throws', () async {
        final r = await connectWith(androidWith(canBond: false));
        expect(
          () => r.conn.android!.removeBond(),
          throwsA(
            isA<UnsupportedOperationException>().having(
              (e) => e.operation,
              'operation',
              'removeBond',
            ),
          ),
        );
        await r.conn.disconnect();
        r.bluey.dispose();
      });

      test('bondState getter throws synchronously', () async {
        final r = await connectWith(androidWith(canBond: false));
        expect(
          () => r.conn.android!.bondState,
          throwsA(
            isA<UnsupportedOperationException>().having(
              (e) => e.operation,
              'operation',
              'bondState',
            ),
          ),
        );
        await r.conn.disconnect();
        r.bluey.dispose();
      });

      test('bondStateChanges getter throws synchronously', () async {
        final r = await connectWith(androidWith(canBond: false));
        expect(
          () => r.conn.android!.bondStateChanges,
          throwsA(
            isA<UnsupportedOperationException>().having(
              (e) => e.operation,
              'operation',
              'bondStateChanges',
            ),
          ),
        );
        await r.conn.disconnect();
        r.bluey.dispose();
      });
    });

    group('canRequestPhy=false', () {
      test('requestPhy() throws', () async {
        final r = await connectWith(androidWith(canRequestPhy: false));
        expect(
          () => r.conn.android!.requestPhy(),
          throwsA(
            isA<UnsupportedOperationException>().having(
              (e) => e.operation,
              'operation',
              'requestPhy',
            ),
          ),
        );
        await r.conn.disconnect();
        r.bluey.dispose();
      });

      test('txPhy / rxPhy / phyChanges getters throw synchronously', () async {
        final r = await connectWith(androidWith(canRequestPhy: false));
        expect(
          () => r.conn.android!.txPhy,
          throwsA(isA<UnsupportedOperationException>()),
        );
        expect(
          () => r.conn.android!.rxPhy,
          throwsA(isA<UnsupportedOperationException>()),
        );
        expect(
          () => r.conn.android!.phyChanges,
          throwsA(isA<UnsupportedOperationException>()),
        );
        await r.conn.disconnect();
        r.bluey.dispose();
      });
    });

    group('canRequestConnectionParameters=false', () {
      test('requestConnectionParameters() throws', () async {
        final r = await connectWith(
          androidWith(canRequestConnectionParameters: false),
        );
        expect(
          () => r.conn.android!.requestConnectionParameters(
            ConnectionParameters(
              interval: ConnectionInterval(30),
              latency: PeripheralLatency(0),
              timeout: SupervisionTimeout(4000),
            ),
          ),
          throwsA(
            isA<UnsupportedOperationException>().having(
              (e) => e.operation,
              'operation',
              'requestConnectionParameters',
            ),
          ),
        );
        await r.conn.disconnect();
        r.bluey.dispose();
      });

      test('connectionParameters getter throws synchronously', () async {
        final r = await connectWith(
          androidWith(canRequestConnectionParameters: false),
        );
        expect(
          () => r.conn.android!.connectionParameters,
          throwsA(isA<UnsupportedOperationException>()),
        );
        await r.conn.disconnect();
        r.bluey.dispose();
      });
    });
  });

  group('Bluey.bondedDevices — canBond gate', () {
    test(
      'throws UnsupportedOperationException when canBond=false (iOS)',
      () async {
        final fakePlatform = FakeBlueyPlatform(
          capabilities: platform.Capabilities.iOS,
        );
        platform.BlueyPlatform.instance = fakePlatform;
        final bluey = Bluey();
        expect(
          () => bluey.bondedDevices,
          throwsA(
            isA<UnsupportedOperationException>()
                .having((e) => e.operation, 'operation', 'bondedDevices')
                .having((e) => e.platform, 'platform', 'ios'),
          ),
        );
        bluey.dispose();
      },
    );

    test('succeeds (returns a list) when canBond=true (Android)', () async {
      final fakePlatform = FakeBlueyPlatform(
        capabilities: platform.Capabilities(
          platformKind: platform.PlatformKind.android,
          canScan: true,
          canConnect: true,
          canBond: true,
        ),
      );
      platform.BlueyPlatform.instance = fakePlatform;
      final bluey = Bluey();
      final devices = await bluey.bondedDevices;
      expect(devices, isA<List<Device>>());
      bluey.dispose();
    });
  });

  group('Server.startAdvertising — manufacturer data gate', () {
    Future<({Server server, Bluey bluey})> serverWith(
      platform.Capabilities caps,
    ) async {
      final fakePlatform = FakeBlueyPlatform(capabilities: caps);
      platform.BlueyPlatform.instance = fakePlatform;
      final bluey = Bluey();
      final server = bluey.server()!;
      return (server: server, bluey: bluey);
    }

    test('throws when manufacturerData supplied and flag is false', () async {
      final r = await serverWith(platform.Capabilities.iOS);
      // startAdvertising is `async` (it awaits _controlServiceReady), so
      // the gate's synchronous throw surfaces as a Future rejection.
      // Use expectLater to await the assertion.
      await expectLater(
        r.server.startAdvertising(
          name: 'Test',
          manufacturerData: ManufacturerData(
            0xFFFF,
            Uint8List.fromList([1, 2, 3]),
          ),
        ),
        throwsA(
          isA<UnsupportedOperationException>()
              .having(
                (e) => e.operation,
                'operation',
                'startAdvertising(manufacturerData)',
              )
              .having((e) => e.platform, 'platform', 'ios'),
        ),
      );
      r.bluey.dispose();
    });

    test('succeeds when manufacturerData omitted and flag is false', () async {
      final r = await serverWith(platform.Capabilities.iOS);
      await r.server.startAdvertising(name: 'Test');
      r.bluey.dispose();
    });

    test('succeeds when manufacturerData supplied and flag is true', () async {
      final r = await serverWith(platform.Capabilities.android);
      await r.server.startAdvertising(
        name: 'Test',
        manufacturerData: ManufacturerData(
          0xFFFF,
          Uint8List.fromList([1, 2, 3]),
        ),
      );
      r.bluey.dispose();
    });
  });
}
