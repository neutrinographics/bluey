import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import 'fake_platform.dart';

/// I346 — the iOS shared-physical-link trap, modeled.
///
/// On iOS one physical link is shared per peer pair across GAP roles
/// (cross-platform-quirks.md §1). When B already serves A as a client
/// and B then also connects OUT to A, disconnecting that outbound
/// handle tears down the one shared link — killing the inbound serving
/// relationship too. `FakeBleLink.shareOnePhysicalLink` binds two links
/// into that iOS topology so the documented address-dedup pattern is
/// finally regression-testable.
void main() {
  const addrA = 'shared-addr-A';
  const addrB = 'shared-addr-B';

  late FakeBlueyPlatform fakeA;
  late FakeBlueyPlatform fakeB;
  late Bluey blueyA;
  late Bluey blueyB;
  late Server serverB;
  late FakeBleLink linkAtoB;
  late FakeBleLink linkBtoA;

  setUp(() async {
    fakeA = FakeBlueyPlatform();
    platform.BlueyPlatform.instance = fakeA;
    blueyA = await Bluey.create();

    fakeB = FakeBlueyPlatform();
    platform.BlueyPlatform.instance = fakeB;
    blueyB = await Bluey.create();
    serverB = blueyB.server()!;

    // A→B and B→A links over the SAME raw addresses in both roles —
    // one physical peer pair.
    linkAtoB = FakeBleLink(
      central: fakeA,
      peripheral: fakeB,
      deviceId: addrB,
      centralId: addrA,
    );
    linkBtoA = FakeBleLink(
      central: fakeB,
      peripheral: fakeA,
      deviceId: addrA,
      centralId: addrB,
    );
    FakeBleLink.shareOnePhysicalLink(linkAtoB, linkBtoA);

    await serverB.startAdvertising(name: 'B');
    linkAtoB.announce();
    // A also advertises (bidirectional discovery scenario).
    final serverA = blueyA.server()!;
    await serverA.startAdvertising(name: 'A');
    linkBtoA.announce();
  });

  tearDown(() async {
    await blueyA.dispose();
    await blueyB.dispose();
    await fakeA.dispose();
    await fakeB.dispose();
  });

  test('the trap: B disconnecting its outbound handle tears down the '
      'shared link, killing A\'s inbound serving relationship', () async {
    // A → B: established serving relationship.
    final connA = await blueyA.connect(Device(address: const DeviceAddress(addrB)));
    await pumpEventQueue();
    expect(serverB.connectedClients, hasLength(1));

    // B's scanner sees A advertising and connects out — the naive loop
    // from the quirks doc, without the dedup guard.
    final connB = await blueyB.connect(Device(address: const DeviceAddress(addrA)));
    await pumpEventQueue();

    // B "dedups" by disconnecting the new handle. On iOS this tears
    // down the ONE physical link.
    await connB.disconnect();
    await pumpEventQueue();

    expect(
      connA.state,
      ConnectionState.disconnected,
      reason: 'A\'s outbound connection rode the same physical link',
    );
    expect(
      serverB.connectedClients,
      isEmpty,
      reason: 'B\'s server lost its client with the shared link',
    );
  });

  test('the documented dedup pattern avoids the trap: check '
      'isClientConnected before connecting out', () async {
    final connA = await blueyA.connect(Device(address: const DeviceAddress(addrB)));
    await pumpEventQueue();
    expect(serverB.connectedClients, hasLength(1));

    // B's scanner sees A — but the recommended guard notices A is
    // already attached as a client and skips connectAsPeer entirely
    // (cross-platform-quirks.md, "address-based dedup").
    final alreadyAttached =
        serverB.isClientConnected(const ClientAddress(addrA));
    expect(alreadyAttached, isTrue);
    // No outbound connect happens; the serving relationship survives.

    await pumpEventQueue();
    expect(connA.state, ConnectionState.linked);
    expect(serverB.connectedClients, hasLength(1));
  });
}
