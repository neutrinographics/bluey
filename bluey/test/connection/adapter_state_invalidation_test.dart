import 'dart:async';

import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';
import '../fakes/test_helpers.dart';

void main() {
  late FakeBlueyPlatform fakePlatform;
  late Bluey bluey;

  Device deviceFor(String address) => Device(
    id: UUID('00000000-0000-0000-0000-aabbccddee01'),
    address: address,
    name: 'Test',
  );

  setUp(() async {
    fakePlatform = FakeBlueyPlatform(
      capabilities: platform.Capabilities.android,
    );
    platform.BlueyPlatform.instance = fakePlatform;
    bluey = await Bluey.create();
    fakePlatform.simulatePeripheral(id: TestDeviceIds.device1, name: 'Test');
  });

  tearDown(() async {
    await bluey.dispose();
    await fakePlatform.dispose();
  });

  group('Full adapter-cycle scenarios', () {
    test('Server: alive -> off -> stale -> fresh after on', () async {
      final firstServer = bluey.server()!;
      await firstServer.addService(
        HostedService(uuid: UUID.short(0x180D), characteristics: const []),
      );

      // Adapter cycles off.
      fakePlatform.setState(platform.BluetoothState.off);
      await Future<void>.delayed(const Duration(milliseconds: 5));

      // Old server is dead.
      expect(
        () => firstServer.startAdvertising(),
        throwsA(isA<StaleHandleException>()),
      );

      // Adapter comes back on.
      fakePlatform.setState(platform.BluetoothState.on);
      await Future<void>.delayed(const Duration(milliseconds: 5));

      // Old server stays dead.
      expect(
        () => firstServer.startAdvertising(),
        throwsA(isA<StaleHandleException>()),
      );

      // Fresh server works.
      final secondServer = bluey.server()!;
      await expectLater(
        secondServer.addService(
          HostedService(uuid: UUID.short(0x180D), characteristics: const []),
        ),
        completes,
      );
    });

    test('Connection: alive -> off -> stale -> fresh after on', () async {
      final firstConnection = await bluey.connect(
        deviceFor(TestDeviceIds.device1),
      );

      fakePlatform.setState(platform.BluetoothState.off);
      await Future<void>.delayed(const Duration(milliseconds: 5));

      await expectLater(
        firstConnection.services(),
        throwsA(isA<StaleHandleException>()),
      );

      fakePlatform.setState(platform.BluetoothState.on);
      await Future<void>.delayed(const Duration(milliseconds: 5));

      await expectLater(
        firstConnection.services(),
        throwsA(isA<StaleHandleException>()),
      );

      final secondConnection = await bluey.connect(
        deviceFor(TestDeviceIds.device1),
      );
      await expectLater(secondConnection.services(), completes);
    });

    test('Scanner: alive -> off -> stale -> fresh after on', () async {
      final firstScanner = bluey.scanner();

      fakePlatform.setState(platform.BluetoothState.off);
      await Future<void>.delayed(const Duration(milliseconds: 5));

      expect(() => firstScanner.scan(), throwsA(isA<StaleHandleException>()));

      fakePlatform.setState(platform.BluetoothState.on);
      await Future<void>.delayed(const Duration(milliseconds: 5));

      expect(() => firstScanner.scan(), throwsA(isA<StaleHandleException>()));

      final secondScanner = bluey.scanner();
      // scan() returns a stream, not a Future — just verify it can be called.
      final stream = secondScanner.scan();
      expect(stream, isA<Stream<ScanResult>>());
    });

    // H1 — defensive: if the platform's stateStream surfaces an error
    // (e.g. native channel glitch), the live Connection must invalidate
    // rather than let an unhandled async error escape.
    test('Connection: platform stateStream error invalidates', () async {
      final connection = await bluey.connect(deviceFor(TestDeviceIds.device1));
      expect(connection.state, isNot(equals(ConnectionState.invalidated)));

      fakePlatform.simulateStateError(StateError('platform glitch'));
      await Future<void>.delayed(const Duration(milliseconds: 5));

      expect(connection.state, equals(ConnectionState.invalidated));
    });

    // H1 — defensive: if the platform's stateStream surfaces an error,
    // the live Server must invalidate rather than let an unhandled
    // async error escape.
    test('Server: platform stateStream error invalidates', () async {
      final server = bluey.server()!;
      expect(
        server.advertisingState,
        isNot(equals(AdvertisingState.invalidated)),
      );

      fakePlatform.simulateStateError(StateError('platform glitch'));
      await Future<void>.delayed(const Duration(milliseconds: 5));

      expect(server.advertisingState, equals(AdvertisingState.invalidated));
    });
  });
}
