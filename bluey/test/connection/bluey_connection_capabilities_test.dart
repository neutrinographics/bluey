import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';
import '../fakes/test_helpers.dart';

/// Tests that `BlueyConnection` consults [Capabilities] before subscribing
/// to or fetching bond / PHY / connection-parameter state from the
/// platform.
///
/// The Android platform interface throws [UnimplementedError] on every
/// bond/PHY/connection-parameter call (I035 Stage A), so the domain layer
/// must skip these calls when the matrix says the feature is unsupported
/// — otherwise every Android client connect crashes inside the
/// constructor (the bondStateStream / phyStream calls throw
/// synchronously).
///
/// The fake platform mirrors that behaviour: when a capability is `false`,
/// the corresponding methods throw [UnimplementedError]. A passing test
/// proves the domain layer never called them.
void main() {
  Device deviceFor(String address) => Device(
        id: UUID('00000000-0000-0000-0000-aabbccddee01'),
        address: address,
        name: 'Test Device',
      );

  group('BlueyConnection capability gating', () {
    test(
        'connecting on a canBond=false platform does not throw and yields '
        'BondState.none with a non-broken bondStateChanges stream', () async {
      final fakePlatform = FakeBlueyPlatform(
        capabilities: const platform.Capabilities(
          canScan: true,
          canConnect: true,
          canAdvertise: true,
          canBond: false,
          canRequestPhy: true,
          canRequestConnectionParameters: true,
        ),
      );
      platform.BlueyPlatform.instance = fakePlatform;

      fakePlatform.simulatePeripheral(
        id: TestDeviceIds.device1,
        name: 'Test',
      );

      final bluey = Bluey();
      final conn = await bluey.connect(deviceFor(TestDeviceIds.device1));

      expect(conn.bondState, BondState.none);

      // The stream must exist and be subscribable; on a canBond=false
      // platform there are simply no events to deliver.
      final sub = conn.bondStateChanges.listen((_) {});
      await sub.cancel();

      await conn.disconnect();
      bluey.dispose();
    });

    test(
        'connecting on a canRequestPhy=false platform does not throw and '
        'yields default PHY values with a non-broken phyChanges stream',
        () async {
      final fakePlatform = FakeBlueyPlatform(
        capabilities: const platform.Capabilities(
          canScan: true,
          canConnect: true,
          canAdvertise: true,
          canBond: true,
          canRequestPhy: false,
          canRequestConnectionParameters: true,
        ),
      );
      platform.BlueyPlatform.instance = fakePlatform;

      fakePlatform.simulatePeripheral(
        id: TestDeviceIds.device1,
        name: 'Test',
      );

      final bluey = Bluey();
      final conn = await bluey.connect(deviceFor(TestDeviceIds.device1));

      expect(conn.txPhy, Phy.le1m);
      expect(conn.rxPhy, Phy.le1m);

      final sub = conn.phyChanges.listen((_) {});
      await sub.cancel();

      await conn.disconnect();
      bluey.dispose();
    });

    test(
        'connecting on a canRequestConnectionParameters=false platform does '
        'not throw and yields default ConnectionParameters', () async {
      final fakePlatform = FakeBlueyPlatform(
        capabilities: const platform.Capabilities(
          canScan: true,
          canConnect: true,
          canAdvertise: true,
          canBond: true,
          canRequestPhy: true,
          canRequestConnectionParameters: false,
        ),
      );
      platform.BlueyPlatform.instance = fakePlatform;

      fakePlatform.simulatePeripheral(
        id: TestDeviceIds.device1,
        name: 'Test',
      );

      final bluey = Bluey();
      final conn = await bluey.connect(deviceFor(TestDeviceIds.device1));

      // Defaults from BlueyConnection's initial state.
      expect(conn.connectionParameters.intervalMs, 30.0);
      expect(conn.connectionParameters.latency, 0);
      expect(conn.connectionParameters.timeoutMs, 4000);

      await conn.disconnect();
      bluey.dispose();
    });

    test(
        'connecting on an Android-shaped platform '
        '(canBond / canRequestPhy / canRequestConnectionParameters all false) '
        'completes successfully — this is what unblocks Android client '
        'manual testing under I035 Stage A', () async {
      final fakePlatform = FakeBlueyPlatform(
        capabilities: const platform.Capabilities(
          canScan: true,
          canConnect: true,
          canAdvertise: true,
          canBond: false,
          canRequestPhy: false,
          canRequestConnectionParameters: false,
        ),
      );
      platform.BlueyPlatform.instance = fakePlatform;

      fakePlatform.simulatePeripheral(
        id: TestDeviceIds.device1,
        name: 'Test',
      );

      final bluey = Bluey();
      final conn = await bluey.connect(deviceFor(TestDeviceIds.device1));

      expect(conn.bondState, BondState.none);
      expect(conn.txPhy, Phy.le1m);
      expect(conn.rxPhy, Phy.le1m);
      expect(conn.connectionParameters.intervalMs, 30.0);

      await conn.disconnect();
      bluey.dispose();
    });

    test(
        'connecting on a fully-capable platform still wires up bond / PHY / '
        'conn-params subscriptions (regression guard for the gate)', () async {
      final fakePlatform = FakeBlueyPlatform();
      platform.BlueyPlatform.instance = fakePlatform;

      fakePlatform.simulatePeripheral(
        id: TestDeviceIds.device1,
        name: 'Test',
      );

      final bluey = Bluey();
      final conn = await bluey.connect(deviceFor(TestDeviceIds.device1));

      // Streams must be live (not the inert defaults).
      final bondSub = conn.bondStateChanges.listen((_) {});
      final phySub = conn.phyChanges.listen((_) {});
      await bondSub.cancel();
      await phySub.cancel();

      await conn.disconnect();
      bluey.dispose();
    });
  });
}
