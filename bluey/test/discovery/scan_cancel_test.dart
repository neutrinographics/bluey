import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';

void main() {
  late FakeBlueyPlatform fakePlatform;
  late Bluey bluey;

  setUp(() async {
    fakePlatform = FakeBlueyPlatform(
      capabilities: platform.Capabilities.android,
    );
    platform.BlueyPlatform.instance = fakePlatform;
    fakePlatform.setState(platform.BluetoothState.on);
    bluey = await Bluey.create();
  });

  tearDown(() async {
    await bluey.dispose();
    await fakePlatform.dispose();
  });

  group('Scanner.scan() onCancel (Convention 5 — resource-backed cancel)', () {
    test('cancelling the scan subscription stops the platform scan', () async {
      final scanner = bluey.scanner();
      final sub = scanner.scan().listen((_) {});

      // Wait for scan to actually start at the platform layer.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(fakePlatform.isScanning, isTrue);

      await sub.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 5));

      expect(fakePlatform.isScanning, isFalse);
    });
  });
}
