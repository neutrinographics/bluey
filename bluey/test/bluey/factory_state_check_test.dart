import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';
import '../fakes/test_helpers.dart';

/// Pumps the microtask queue so the `Bluey` state-stream listener
/// receives the fake's most recently broadcast `BluetoothState` and
/// updates its cached `_currentState`. The synchronous factory
/// pre-check reads that cache.
Future<void> flushState() async {
  await Future<void>.delayed(const Duration(milliseconds: 5));
}

void main() {
  late FakeBlueyPlatform fakePlatform;
  late Bluey bluey;

  setUp(() async {
    fakePlatform = FakeBlueyPlatform(
      capabilities: platform.Capabilities.android,
    );
    platform.BlueyPlatform.instance = fakePlatform;
    bluey = await Bluey.create();
  });

  tearDown(() async {
    await bluey.dispose();
    await fakePlatform.dispose();
  });

  group('Bluey.server() factory pre-checks adapter state', () {
    test('throws BluetoothDisabledException when state is off', () async {
      fakePlatform.setState(platform.BluetoothState.off);
      await flushState();

      expect(() => bluey.server(), throwsA(isA<BluetoothDisabledException>()));
    });

    test(
      'throws PermissionDeniedException when state is unauthorized',
      () async {
        fakePlatform.setState(platform.BluetoothState.unauthorized);
        await flushState();

        expect(() => bluey.server(), throwsA(isA<PermissionDeniedException>()));
      },
    );

    test(
      'throws BluetoothUnavailableException when state is unsupported',
      () async {
        fakePlatform.setState(platform.BluetoothState.unsupported);
        await flushState();

        expect(
          () => bluey.server(),
          throwsA(isA<BluetoothUnavailableException>()),
        );
      },
    );

    test(
      'throws BluetoothUnavailableException when state is unknown',
      () async {
        fakePlatform.setState(platform.BluetoothState.unknown);
        await flushState();

        expect(
          () => bluey.server(),
          throwsA(isA<BluetoothUnavailableException>()),
        );
      },
    );

    test('returns a Server when state is on', () async {
      fakePlatform.setState(platform.BluetoothState.on);
      await flushState();

      final server = bluey.server();
      expect(server, isNotNull);
    });
  });

  group('Bluey.scanner() factory pre-checks adapter state', () {
    test('throws BluetoothDisabledException when state is off', () async {
      fakePlatform.setState(platform.BluetoothState.off);
      await flushState();

      expect(() => bluey.scanner(), throwsA(isA<BluetoothDisabledException>()));
    });

    test('returns a Scanner when state is on', () async {
      fakePlatform.setState(platform.BluetoothState.on);
      await flushState();

      final scanner = bluey.scanner();
      expect(scanner, isNotNull);
    });
  });

  group('Bluey.connect() factory pre-checks adapter state', () {
    test('throws BluetoothDisabledException when state is off', () async {
      fakePlatform.setState(platform.BluetoothState.off);
      await flushState();
      final device = Device(
        address: DeviceAddress(TestDeviceIds.device1),
        name: 'Test',
      );

      await expectLater(
        bluey.connect(device),
        throwsA(isA<BluetoothDisabledException>()),
      );
    });
  });
}
