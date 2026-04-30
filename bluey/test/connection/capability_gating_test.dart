import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart' as platform;
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
      final r = await connectWith(const platform.Capabilities(
        platformKind: platform.PlatformKind.other,
        canScan: true,
        canConnect: true,
      ));
      expect(r.conn.android, isNull);
      expect(r.conn.ios, isNull);
      await r.conn.disconnect();
      r.bluey.dispose();
    });
  });

  group('BlueyConnection.requestMtu gating', () {
    test('throws UnsupportedOperationException when canRequestMtu=false', () async {
      final r = await connectWith(platform.Capabilities.iOS);
      expect(
        () => r.conn.requestMtu(
          Mtu(247, capabilities: platform.Capabilities.android),
        ),
        throwsA(isA<UnsupportedOperationException>()
            .having((e) => e.operation, 'operation', 'requestMtu')
            .having((e) => e.platform, 'platform', 'ios')),
      );
      await r.conn.disconnect();
      r.bluey.dispose();
    });

    test('succeeds when canRequestMtu=true', () async {
      final r = await connectWith(platform.Capabilities.android);
      final negotiated = await r.conn.requestMtu(
        Mtu(247, capabilities: platform.Capabilities.android),
      );
      expect(negotiated.value, greaterThan(0));
      await r.conn.disconnect();
      r.bluey.dispose();
    });
  });
}
