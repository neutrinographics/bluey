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

      final mtu = await connection.android!.requestMtu(Mtu(512));

      expect(mtu, equals(Mtu.fromPlatform(185)));
    });

    test('a request under the cap is granted as asked', () async {
      fakePlatform.simulateMtuNegotiationCap(deviceId, 247);

      final connection = await bluey.connect(
        Device(address: const DeviceAddress(deviceId)),
      );

      final mtu = await connection.android!.requestMtu(Mtu(185));

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
        connection.android!.requestMtu(Mtu(512)),
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

    test('the scan-failure seam is one-shot: the next scan succeeds', () async {
      fakePlatform.simulatePeripheral(id: deviceId, name: 'Scan OK');
      fakePlatform.simulateScanFailure(
        PlatformException(code: 'bluey-unknown', message: 'scan failed: 2'),
      );

      final failing = bluey.scanner();
      await expectLater(failing.scan(), emitsError(isA<BlueyException>()));

      final working = bluey.scanner();
      final result = await working.scan().first;
      expect(result.device.address, const DeviceAddress(deviceId));
      await working.stop();
    });
  });

  group('simulateScanRefusal', () {
    test('puts PlatformScanFailedException on the running scan and stops '
        'the platform scan', () async {
      // arrange
      final fakePlatform = FakeBlueyPlatform();
      final errors = <Object>[];
      fakePlatform
          .scan(
            platform.PlatformScanConfig(
              serviceUuids: const [],
              timeoutMs: null,
            ),
          )
          .listen((_) {}, onError: errors.add);
      await Future<void>.delayed(Duration.zero);

      // act
      fakePlatform.simulateScanRefusal(
        platform.PlatformScanFailureReason.startedTooOften,
      );
      await Future<void>.delayed(Duration.zero);

      // assert
      final error = errors.single as platform.PlatformScanFailedException;
      expect(error.reason, platform.PlatformScanFailureReason.startedTooOften);
      expect(fakePlatform.isScanning, isFalse);
      await fakePlatform.dispose();
    });

    test('after the scan was stopped it delivers nothing', () async {
      // arrange
      final fakePlatform = FakeBlueyPlatform();
      final errors = <Object>[];
      fakePlatform
          .scan(
            platform.PlatformScanConfig(
              serviceUuids: const [],
              timeoutMs: null,
            ),
          )
          .listen((_) {}, onError: errors.add);
      await Future<void>.delayed(Duration.zero);
      await fakePlatform.stopScan();

      // act
      fakePlatform.simulateScanRefusal(
        platform.PlatformScanFailureReason.startedTooOften,
      );
      await Future<void>.delayed(Duration.zero);

      // assert
      expect(errors, isEmpty);
      await fakePlatform.dispose();
    });

    test('with no scan running changes nothing', () async {
      // arrange
      final fakePlatform = FakeBlueyPlatform();

      // act
      fakePlatform.simulateScanRefusal(
        platform.PlatformScanFailureReason.startedTooOften,
      );

      // assert
      expect(fakePlatform.isScanning, isFalse);
      await fakePlatform.dispose();
    });
  });

  group('holdNextStopScan', () {
    test('keeps the stop pending until it is released', () async {
      // arrange
      final fakePlatform = FakeBlueyPlatform();
      fakePlatform.scan(
        platform.PlatformScanConfig(serviceUuids: const [], timeoutMs: null),
      );
      fakePlatform.holdNextStopScan();
      var stopped = false;
      final stop = fakePlatform.stopScan().then((_) => stopped = true);

      // act
      await Future<void>.delayed(Duration.zero);
      final stoppedWhileHeld = stopped;
      final scanningWhileHeld = fakePlatform.isScanning;
      fakePlatform.releaseHeldStopScan();
      await stop;

      // assert
      expect(stoppedWhileHeld, isFalse);
      expect(scanningWhileHeld, isTrue);
      expect(fakePlatform.isScanning, isFalse);
      await fakePlatform.dispose();
    });
  });

  group('simulateScanResult', () {
    const device = platform.PlatformDevice(
      id: 'AA:BB:CC:DD:EE:01',
      name: 'Device',
      rssi: -60,
      serviceUuids: [],
      manufacturerDataCompanyId: null,
      manufacturerData: null,
    );

    test('puts the device on the running scan', () async {
      // arrange
      final fakePlatform = FakeBlueyPlatform();
      final heard = <platform.PlatformDevice>[];
      fakePlatform
          .scan(
            platform.PlatformScanConfig(
              serviceUuids: const [],
              timeoutMs: null,
            ),
          )
          .listen(heard.add);

      // act
      fakePlatform.simulateScanResult(device);
      await Future<void>.delayed(Duration.zero);

      // assert
      expect(heard, [device]);
      await fakePlatform.dispose();
    });

    test('with no scan running delivers nothing and does not throw', () async {
      // arrange
      final fakePlatform = FakeBlueyPlatform();

      // act
      fakePlatform.simulateScanResult(device);

      // assert
      expect(fakePlatform.isScanning, isFalse);
      await fakePlatform.dispose();
    });
  });
}
