import 'package:bluey/bluey.dart';
import 'package:bluey/src/lifecycle.dart' as lifecycle;
import 'package:bluey/src/shared/device_id_coercion.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';

/// Tests for the C.4 APIs: `Bluey.connectAsPeer` and `Bluey.tryUpgrade`.
///
/// These build a [PeerConnection] *wrapper* around a raw [Connection]
/// without mutating the raw via `BlueyConnection.upgrade`. The legacy
/// auto-upgrade path on `Bluey.connect` is unchanged — its removal is
/// scheduled for C.5.
void main() {
  late FakeBlueyPlatform fakePlatform;
  late Bluey bluey;

  setUp(() {
    fakePlatform = FakeBlueyPlatform();
    platform.BlueyPlatform.instance = fakePlatform;
    bluey = Bluey();
  });

  tearDown(() async {
    await bluey.dispose();
  });

  Device deviceFromAddress(String address, {String? name}) {
    return Device(
      id: deviceIdToUuid(address),
      address: address,
      name: name,
    );
  }

  group('Bluey.connectAsPeer', () {
    test('returns a PeerConnection with the correct serverId for a Bluey '
        'peer device', () async {
      final id = ServerId.generate();
      const address = 'AA:BB:CC:DD:EE:01';
      fakePlatform.simulateBlueyServer(address: address, serverId: id);

      final device = deviceFromAddress(address);

      final peerConn = await bluey.connectAsPeer(device);

      expect(peerConn, isA<PeerConnection>());
      expect(peerConn.serverId, equals(id));

      await peerConn.disconnect();
    });

    test('peer.connection is the raw GATT Connection (not the peer wrapper)',
        () async {
      final id = ServerId.generate();
      const address = 'AA:BB:CC:DD:EE:02';
      fakePlatform.simulateBlueyServer(address: address, serverId: id);

      final device = deviceFromAddress(address);
      final peerConn = await bluey.connectAsPeer(device);

      // The exposed `connection` is the raw Connection — distinct from
      // the PeerConnection wrapper.
      expect(peerConn.connection, isA<Connection>());
      expect(identical(peerConn.connection, peerConn), isFalse);

      await peerConn.disconnect();
    });

    test('sendDisconnectCommand writes 0x00 to the lifecycle control '
        'characteristic via the wrapper\'s LifecycleClient before the '
        'underlying disconnect runs (regression: fast path must reuse the '
        'running LifecycleClient, not construct a fresh unstarted one)',
        () async {
      final id = ServerId.generate();
      const address = 'AA:BB:CC:DD:EE:0A';
      fakePlatform.simulateBlueyServer(address: address, serverId: id);

      final device = deviceFromAddress(address);
      final peerConn = await bluey.connectAsPeer(device);

      // Snapshot the writes BEFORE sendDisconnectCommand so we don't
      // confuse pre-existing heartbeat writes (which the running
      // LifecycleClient emits) with the disconnect-command write.
      final before = fakePlatform.writeCharacteristicCalls.length;

      await peerConn.sendDisconnectCommand();

      final newWrites = fakePlatform.writeCharacteristicCalls
          .skip(before)
          .where(
            (w) =>
                w.deviceId == address &&
                w.characteristicUuid.toLowerCase() ==
                    lifecycle.heartbeatCharUuid &&
                w.value.length == 1 &&
                w.value.first == 0x00,
          )
          .toList();
      // We expect TWO 0x00 writes:
      //   1. From the wrapper's LifecycleClient (the path under test).
      //   2. From BlueyConnection.disconnect()'s own lifecycle send
      //      (the legacy auto-upgrade lifecycle, which currently still
      //      coexists until C.5 collapses the two paths).
      // Pre-fix, the wrapper's LifecycleClient is a fresh, unstarted
      // instance whose `_heartbeatCharUuid` is null, so its
      // sendDisconnectCommand is a silent no-op — only the disconnect
      // path's write is observed (count == 1).
      expect(
        newWrites.length,
        equals(2),
        reason:
            'Both the wrapper\'s LifecycleClient AND the connection\'s '
            'own legacy LifecycleClient should write 0x00 to the '
            'control characteristic. Observed 0x00 writes after '
            'sendDisconnectCommand: ${newWrites.length} '
            '(expected 2; 1 indicates the wrapper\'s lifecycle was a '
            'fresh, unstarted client — see C.4 follow-up).',
      );
    });

    test('throws NotABlueyPeerException and disconnects the underlying '
        'connection when the device is not a Bluey peer', () async {
      const address = 'AA:BB:CC:DD:EE:03';
      // Plain peripheral with no control service.
      fakePlatform.simulatePeripheral(id: address, name: 'Plain Device');

      final device = deviceFromAddress(address);

      await expectLater(
        bluey.connectAsPeer(device),
        throwsA(isA<NotABlueyPeerException>()),
      );

      // The raw connection should have been disconnected as cleanup.
      expect(fakePlatform.connectedDeviceIds, isNot(contains(address)));
    });
  });

  group('Bluey.tryUpgrade', () {
    test('returns a PeerConnection wrapping the input when the connection '
        'is a Bluey peer', () async {
      final id = ServerId.generate();
      const address = 'AA:BB:CC:DD:EE:04';
      fakePlatform.simulateBlueyServer(address: address, serverId: id);

      final device = deviceFromAddress(address);
      final rawConnection = await bluey.connect(device);

      final peerConn = await bluey.tryUpgrade(rawConnection);

      expect(peerConn, isNotNull);
      expect(peerConn!.serverId, equals(id));
      // The PeerConnection wraps the input — peerConn.connection is
      // the same Connection we passed in.
      expect(identical(peerConn.connection, rawConnection), isTrue);

      await peerConn.disconnect();
    });

    test('returns null when the connection is not a Bluey peer', () async {
      const address = 'AA:BB:CC:DD:EE:05';
      fakePlatform.simulatePeripheral(id: address, name: 'Plain Device');

      final device = deviceFromAddress(address);
      final rawConnection = await bluey.connect(device);

      final peerConn = await bluey.tryUpgrade(rawConnection);

      expect(peerConn, isNull);
      // tryUpgrade does NOT disconnect on miss — caller owns the
      // connection.
      expect(fakePlatform.connectedDeviceIds, contains(address));

      await rawConnection.disconnect();
    });
  });
}
