import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import 'fake_platform.dart';
import 'test_helpers.dart';

/// I348 — inherited/ghost centrals before advertising starts.
///
/// Real platforms deliver centrals regardless of advertising state: iOS
/// caches its connection to a peer, and when the peer's app restarts
/// and opens a fresh GATT server the cached connection "reconnects"
/// instantly — before advertising begins (ANDROID_BLE_NOTES, "iOS
/// Connection Caching"). The fake used to forbid this with a
/// StateError, modeling a false invariant.
void main() {
  test('a central can appear before advertising starts and is reported to '
      'the server (inherited connection)', () async {
    final fakePlatform = FakeBlueyPlatform();
    platform.BlueyPlatform.instance = fakePlatform;
    final bluey = await Bluey.create();
    final server = bluey.server()!;

    final clients = <Client>[];
    final sub = server.connections.listen(clients.add);

    // The iOS-cached connection "reconnects" the moment the manager is
    // live — no advertising has started.
    expect(fakePlatform.isAdvertising, isFalse);
    fakePlatform.simulateCentralConnection(
      centralId: TestDeviceIds.central1,
    );
    await pumpEventQueue();

    expect(clients, hasLength(1));
    expect(server.connectedClients, hasLength(1));

    await sub.cancel();
    await server.dispose();
    await bluey.dispose();
    await fakePlatform.dispose();
  });
}
