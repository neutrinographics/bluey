import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';

/// Scanner.scan gains a ScanMode (Android duty-cycle control): a consumer
/// whose mesh is fully connected can drop from continuous scanning
/// (~10-15% battery/hour on phones) to a sparse duty cycle without
/// stopping discovery entirely.
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

  group('Scanner.scan mode', () {
    test('passes the requested mode through to the platform', () async {
      final scanner = bluey.scanner();
      final sub = scanner.scan(mode: ScanMode.balanced).listen((_) {});
      addTearDown(sub.cancel);
      await pumpEventQueue();

      expect(
        fakePlatform.lastScanConfig?.scanMode,
        platform.PlatformScanMode.balanced,
      );
    });

    test('defaults to null — the platform default (lowLatency) applies, '
        'preserving behavior for every existing caller', () async {
      final scanner = bluey.scanner();
      final sub = scanner.scan().listen((_) {});
      addTearDown(sub.cancel);
      await pumpEventQueue();

      expect(fakePlatform.lastScanConfig, isNotNull);
      expect(fakePlatform.lastScanConfig?.scanMode, isNull);
    });

    test('each mode maps to its platform counterpart', () async {
      for (final (mode, expected) in [
        (ScanMode.lowPower, platform.PlatformScanMode.lowPower),
        (ScanMode.balanced, platform.PlatformScanMode.balanced),
        (ScanMode.lowLatency, platform.PlatformScanMode.lowLatency),
      ]) {
        final scanner = bluey.scanner();
        final sub = scanner.scan(mode: mode).listen((_) {});
        await pumpEventQueue();
        expect(fakePlatform.lastScanConfig?.scanMode, expected);
        await sub.cancel();
        await pumpEventQueue();
        scanner.dispose();
      }
    });
  });
}
