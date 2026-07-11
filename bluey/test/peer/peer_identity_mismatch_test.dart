import 'package:bluey/bluey.dart';
import 'package:bluey/src/lifecycle.dart' as lifecycle;
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';
import '../fakes/test_helpers.dart';

/// A.2 follow-up — identity mismatch is a disconnect.
///
/// A Service Changed on a live peer connection is the signal that the
/// remote GATT database was rebuilt (typically: the server app
/// restarted while the ACL stayed up). The lifecycle client re-verifies
/// the peer's ServerId on that signal; a *different* identity means the
/// session's peer is gone — the connection is torn down and
/// [PeerIdentityMismatchException] surfaces on the event bus, so the
/// app reconnects deliberately to the new identity.
void main() {
  const address = 'IDENTITY-PEER';

  late FakeBlueyPlatform fakePlatform;
  late Bluey bluey;

  setUp(() async {
    fakePlatform = FakeBlueyPlatform();
    platform.BlueyPlatform.instance = fakePlatform;
    bluey = await Bluey.create(localIdentity: TestServerIds.localIdentity);
    fakePlatform.simulateBlueyServer(
      address: address,
      serverId: TestServerIds.remoteIdentity,
    );
  });

  tearDown(() async {
    await bluey.dispose();
    await fakePlatform.dispose();
  });

  test('a changed ServerId after Service Changed tears the peer connection '
      'down and surfaces PeerIdentityMismatchException', () async {
    final peer = await bluey.connectAsPeer(
      Device(address: const DeviceAddress(address)),
    );
    expect(peer.serverId, equals(TestServerIds.remoteIdentity));

    final mismatches = <PeerIdentityMismatchException>[];
    bluey.events.listen((event) {
      if (event is ErrorEvent && event.error is PeerIdentityMismatchException) {
        mismatches.add(event.error! as PeerIdentityMismatchException);
      }
    });

    // The remote app reinstalled/regenerated identity while the link
    // stayed up: the GATT database is rebuilt and the serverId
    // characteristic now carries a different identity.
    fakePlatform.simulateServiceChange(
      address,
      newCharacteristicValues: {
        lifecycle.serverIdCharUuid: lifecycle.lifecycleCodec
            .encodeAdvertisedIdentity(TestServerIds.thirdParty),
        lifecycle.intervalCharUuid: lifecycle.encodeInterval(
          const Duration(seconds: 10),
        ),
      },
    );
    await pumpEventQueue();
    await pumpEventQueue();

    expect(mismatches, hasLength(1));
    expect(mismatches.single.expected, equals(TestServerIds.remoteIdentity));
    expect(mismatches.single.actual, equals(TestServerIds.thirdParty));
    expect(
      peer.connection.state,
      ConnectionState.disconnected,
      reason: 'a changed identity means the session\'s peer is gone',
    );
  });

  test('an unchanged ServerId after Service Changed keeps the session up',
      () async {
    final peer = await bluey.connectAsPeer(
      Device(address: const DeviceAddress(address)),
    );

    final errors = <ErrorEvent>[];
    bluey.events.listen((event) {
      if (event is ErrorEvent) errors.add(event);
    });

    // Same identity re-served after a GATT rebuild (e.g. the server
    // re-registered its services without restarting).
    fakePlatform.simulateServiceChange(
      address,
      newCharacteristicValues: {
        lifecycle.serverIdCharUuid: lifecycle.lifecycleCodec
            .encodeAdvertisedIdentity(TestServerIds.remoteIdentity),
        lifecycle.intervalCharUuid: lifecycle.encodeInterval(
          const Duration(seconds: 10),
        ),
      },
    );
    await pumpEventQueue();
    await pumpEventQueue();

    expect(errors, isEmpty);
    expect(peer.connection.state, isNot(ConnectionState.disconnected));
  });

  test('a failed verification read is treated as transient: the session '
      'survives', () async {
    final peer = await bluey.connectAsPeer(
      Device(address: const DeviceAddress(address)),
    );

    final errors = <ErrorEvent>[];
    bluey.events.listen((event) {
      if (event is ErrorEvent) errors.add(event);
    });

    // The verification read itself fails (flaky link mid-rebuild) —
    // no evidence of a different peer, so no teardown.
    fakePlatform.enqueueFault(
      FakeOp.readCharacteristic,
      const platform.GattOperationTimeoutException('readCharacteristic'),
      deviceId: address,
      characteristicUuid: lifecycle.serverIdCharUuid,
      times: null,
    );

    fakePlatform.simulateServiceChange(address);
    await pumpEventQueue();
    await pumpEventQueue();

    expect(errors, isEmpty);
    expect(peer.connection.state, isNot(ConnectionState.disconnected));
    fakePlatform.clearFaults();
  });
}
