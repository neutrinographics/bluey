import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';
import '../fakes/test_helpers.dart';

/// Tests for the disconnect path on an upgraded Bluey peer connection.
/// Specifically: the courtesy `sendDisconnectCommand` write must not be
/// allowed to block the platform disconnect indefinitely (I074).
void main() {
  late FakeBlueyPlatform fakePlatform;

  setUp(() {
    fakePlatform = FakeBlueyPlatform();
    platform.BlueyPlatform.instance = fakePlatform;
  });

  group('BlueyConnection.disconnect on upgraded peer', () {
    test(
        'I074: disconnect proceeds even when the courtesy '
        'sendDisconnectCommand write hangs', () async {
      fakePlatform.simulateBlueyServer(
        address: TestDeviceIds.device1,
        serverId: ServerId.generate(),
      );

      final bluey = Bluey();
      final conn = await bluey.connect(Device(
        id: UUID('00000000-0000-0000-0000-aabbccddee01'),
        address: TestDeviceIds.device1,
        name: 'Test Device',
      ));

      // Let the initial heartbeat + interval-read settle so subsequent
      // writes are observable as the disconnect command.
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Hold the next write — that will be the courtesy disconnect-command
      // write fired from BlueyConnection.disconnect().
      fakePlatform.holdNextWriteCharacteristic();

      // The bug: BlueyConnection.disconnect awaits sendDisconnectCommand
      // unconditionally; with a hung write, disconnect itself hangs for
      // the platform's full per-op timeout (~10s). Bound the test wait
      // at 3 seconds — well under that timeout, well over the 1s
      // courtesy budget the fix introduces.
      await conn.disconnect().timeout(
            const Duration(seconds: 3),
            onTimeout: () =>
                fail('disconnect did not return within 3s; the '
                    'courtesy sendDisconnectCommand write blocked it'),
          );

      expect(
        conn.state,
        ConnectionState.disconnected,
        reason: 'connection state must reach disconnected after the '
            'platform-level disconnect runs',
      );

      bluey.dispose();
    });
  });
}
