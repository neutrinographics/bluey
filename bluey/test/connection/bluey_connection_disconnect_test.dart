import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';
import '../fakes/test_helpers.dart';

/// Tests for the disconnect path on a peer connection. Specifically:
/// the courtesy lifecycle write must not be allowed to block the
/// platform disconnect indefinitely (I074).
///
/// `BlueyConnection.disconnect` is purely raw GATT — the courtesy
/// disconnect-command write lives on the peer-protocol surface
/// (`PeerConnection.disconnect`). The I074 invariant is therefore
/// exercised against the peer wrapper instead of the raw connection.
void main() {
  late FakeBlueyPlatform fakePlatform;

  setUp(() {
    fakePlatform = FakeBlueyPlatform();
    platform.BlueyPlatform.instance = fakePlatform;
  });

  group('PeerConnection.disconnect', () {
    test(
        'I074: disconnect proceeds with platform disconnect even '
        'when the courtesy lifecycle write hangs', () async {
      fakePlatform.simulateBlueyServer(
        address: TestDeviceIds.device1,
        serverId: ServerId.generate(),
      );

      final bluey = Bluey();
      final peerConn = await bluey.connectAsPeer(Device(
        id: UUID('00000000-0000-0000-0000-aabbccddee01'),
        address: TestDeviceIds.device1,
        name: 'Test Device',
      ));

      // Let any initial heartbeat traffic settle so the next held write
      // is unambiguously the disconnect-command write.
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Hold the next write — that will be the courtesy 0x00 emitted
      // during disconnect.
      fakePlatform.holdNextWriteCharacteristic();

      // disconnect must not block forever on a hung write. Bound the
      // test wait at 3 seconds. The lifecycle-client disconnect-command
      // call swallows its own timeout, then proceeds to platform
      // disconnect.
      await peerConn.disconnect().timeout(
            const Duration(seconds: 3),
            onTimeout: () =>
                fail('peer.disconnect() did not return within 3s; '
                    'the courtesy lifecycle write blocked it'),
          );

      expect(
        peerConn.connection.state,
        ConnectionState.disconnected,
        reason: 'underlying connection must reach disconnected after '
            'peer.disconnect() returns',
      );

      bluey.dispose();
    });
  });
}
