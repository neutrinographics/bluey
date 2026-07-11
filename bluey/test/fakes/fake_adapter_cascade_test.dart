import 'dart:typed_data';

import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import 'fake_platform.dart';
import 'test_helpers.dart';

/// Contract tests for the fake's adapter-off transport cascade
/// (audit R6 / NT-4).
///
/// Real adapters don't just emit a state event when powered off — the
/// transport dies: live links drop, the radio stops scanning and
/// advertising, in-flight operations drain. With
/// `cascadeAdapterTeardown` enabled, `setBluetoothState(off)` models
/// that. The default (`false`) preserves the historical
/// state-event-only behavior existing tests rely on.
void main() {
  const deviceId = TestDeviceIds.device1;

  late FakeBlueyPlatform fakePlatform;
  late Bluey bluey;

  setUp(() async {
    fakePlatform = FakeBlueyPlatform();
    platform.BlueyPlatform.instance = fakePlatform;
    bluey = await Bluey.create();
    fakePlatform.simulatePeripheral(id: deviceId, name: 'Cascade Test');
  });

  tearDown(() async {
    await bluey.dispose();
    await fakePlatform.dispose();
  });

  group('cascadeAdapterTeardown', () {
    test('adapter off drops live connections at the transport level',
        () async {
      fakePlatform.cascadeAdapterTeardown = true;

      final connection = await bluey.connect(
        Device(address: const DeviceAddress(deviceId)),
      );
      expect(fakePlatform.connectedDeviceIds, contains(deviceId));

      fakePlatform.setBluetoothState(platform.BluetoothState.off);
      await Future<void>.delayed(Duration.zero);

      expect(
        fakePlatform.connectedDeviceIds,
        isEmpty,
        reason: 'the transport link is gone, not merely the domain state',
      );
      // The domain connection is dead either way (invalidated by the
      // adapter state or disconnected by the transport drop — whichever
      // signal lands first); it must not report a live state.
      expect(
        connection.state,
        anyOf(ConnectionState.disconnected, ConnectionState.invalidated),
      );
    });

    test('adapter off stops the radio: scanning and advertising cease',
        () async {
      fakePlatform.cascadeAdapterTeardown = true;

      final scanner = bluey.scanner();
      final sub = scanner.scan().listen((_) {});
      await Future<void>.delayed(Duration.zero);
      expect(fakePlatform.isScanning, isTrue);

      final server = bluey.server()!;
      await server.startAdvertising(name: 'cascade');
      expect(fakePlatform.isAdvertising, isTrue);

      fakePlatform.setBluetoothState(platform.BluetoothState.off);
      await Future<void>.delayed(Duration.zero);

      expect(fakePlatform.isScanning, isFalse);
      expect(fakePlatform.isAdvertising, isFalse);

      await sub.cancel();
      await server.dispose();
    });

    test('adapter off disconnects server-side centrals with a transport '
        'signal', () async {
      fakePlatform.cascadeAdapterTeardown = true;

      final server = bluey.server()!;
      await server.startAdvertising(name: 'cascade');
      fakePlatform.simulateCentralConnection(
        centralId: TestDeviceIds.central1,
      );
      await Future<void>.delayed(Duration.zero);
      expect(fakePlatform.connectedCentralIds, hasLength(1));

      fakePlatform.setBluetoothState(platform.BluetoothState.off);
      await Future<void>.delayed(Duration.zero);

      expect(fakePlatform.connectedCentralIds, isEmpty);

      await server.dispose();
    });

    test('a held in-flight write is drained with a disconnect when the '
        'adapter goes off', () async {
      fakePlatform.cascadeAdapterTeardown = true;

      await bluey.connect(Device(address: const DeviceAddress(deviceId)));
      fakePlatform.holdNextWriteCharacteristic();

      // Use a direct platform write so the held op is unambiguous
      // (the hold intercepts before any handle validation).
      Object? error;
      fakePlatform
          .writeCharacteristic(
            deviceId,
            1,
            Uint8List.fromList(const [0x01]),
            true,
          )
          .catchError((Object e) {
        error = e;
      });
      await Future<void>.delayed(Duration.zero);

      fakePlatform.setBluetoothState(platform.BluetoothState.off);
      await Future<void>.delayed(Duration.zero);

      expect(
        error,
        isA<platform.GattOperationDisconnectedException>(),
        reason: 'the platform queue drains in-flight ops on adapter loss',
      );
    });

    test('default behavior (cascade off) is unchanged: only the state '
        'event fires', () async {
      final connection = await bluey.connect(
        Device(address: const DeviceAddress(deviceId)),
      );

      fakePlatform.setBluetoothState(platform.BluetoothState.off);
      await Future<void>.delayed(Duration.zero);

      expect(
        fakePlatform.connectedDeviceIds,
        contains(deviceId),
        reason: 'historical behavior: no transport teardown',
      );
      // The domain still invalidates off the state event.
      expect(connection.state, ConnectionState.invalidated);
    });
  });
}
