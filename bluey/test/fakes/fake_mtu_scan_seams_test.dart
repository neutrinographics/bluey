import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';

import 'fake_platform.dart';
import 'test_helpers.dart';

/// Contract tests for the MTU negotiate-down and scan-failure seams
/// (audit R7 / NT-7, NT-8).
void main() {
  const deviceId = TestDeviceIds.device1;

  group('MTU negotiation outcomes', () {
    late FakeBlueyPlatform fakePlatform;
    late Bluey bluey;

    setUp(() async {
      // MTU lives on the Android-only extensions (post-I325).
      fakePlatform = FakeBlueyPlatform(
        capabilities: platform.Capabilities.android,
      );
      platform.BlueyPlatform.instance = fakePlatform;
      bluey = await Bluey.create();
      fakePlatform.simulatePeripheral(id: deviceId, name: 'MTU Test');
    });

    tearDown(() async {
      await bluey.dispose();
      await fakePlatform.dispose();
    });

    test('the peer negotiates DOWN: requestMtu returns the peer cap, not '
        'the requested value', () async {
      fakePlatform.simulateMtuNegotiationCap(deviceId, 185);

      final connection = await bluey.connect(
        Device(address: const DeviceAddress(deviceId)),
      );

      final mtu = await connection.android!.requestMtu(
        Mtu(512, capabilities: platform.Capabilities.android),
      );

      expect(mtu, equals(Mtu.fromPlatform(185)));
    });

    test('a request under the cap is granted as asked', () async {
      fakePlatform.simulateMtuNegotiationCap(deviceId, 247);

      final connection = await bluey.connect(
        Device(address: const DeviceAddress(deviceId)),
      );

      final mtu = await connection.android!.requestMtu(
        Mtu(185, capabilities: platform.Capabilities.android),
      );

      expect(mtu, equals(Mtu.fromPlatform(185)));
    });

    test('requestMtu failure injects through the fault queue as a typed '
        'domain error', () async {
      fakePlatform.enqueueFault(
        FakeOp.requestMtu,
        const platform.GattOperationTimeoutException('requestMtu'),
        deviceId: deviceId,
      );

      final connection = await bluey.connect(
        Device(address: const DeviceAddress(deviceId)),
      );

      await expectLater(
        connection.android!.requestMtu(
          Mtu(512, capabilities: platform.Capabilities.android),
        ),
        throwsA(isA<GattTimeoutException>()),
      );
    });
  });

  group('scan failures', () {
    late FakeBlueyPlatform fakePlatform;
    late Bluey bluey;

    setUp(() async {
      fakePlatform = FakeBlueyPlatform();
      platform.BlueyPlatform.instance = fakePlatform;
      bluey = await Bluey.create();
    });

    tearDown(() async {
      await bluey.dispose();
      await fakePlatform.dispose();
    });

    test('a scan failure surfaces as a translated error on the scan stream '
        'and the scanner lands in stopped', () async {
      // Fake side of I013: the seam exists so that when Android scan
      // failure codes are propagated (the open production fix), the
      // domain reaction is already testable.
      fakePlatform.simulateScanFailure(
        PlatformException(code: 'bluey-unknown', message: 'scan failed: 2'),
      );

      final scanner = bluey.scanner();
      final errors = <Object>[];
      var done = false;
      scanner.scan().listen(
            (_) {},
            onError: errors.add,
            onDone: () => done = true,
          );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(errors, hasLength(1));
      expect(errors.single, isA<BlueyException>());
      expect(done, isTrue, reason: 'a failed scan ends the stream');
      expect(scanner.state, ScanState.stopped);
    });

    test('the scan-failure seam is one-shot: the next scan succeeds',
        () async {
      fakePlatform.simulatePeripheral(id: deviceId, name: 'Scan OK');
      fakePlatform.simulateScanFailure(
        PlatformException(code: 'bluey-unknown', message: 'scan failed: 2'),
      );

      final failing = bluey.scanner();
      await expectLater(
        failing.scan(),
        emitsError(isA<BlueyException>()),
      );

      final working = bluey.scanner();
      final result = await working.scan().first;
      expect(result.device.address, const DeviceAddress(deviceId));
      await working.stop();
    });
  });
}
