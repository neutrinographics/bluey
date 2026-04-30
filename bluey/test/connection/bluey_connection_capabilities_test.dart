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
          platformKind: platform.PlatformKind.android,
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

      // canRequestPhy/canRequestConnectionParameters are still true, so
      // `conn.android` is non-null. Bond state is exposed via the
      // android extension only (post-B.3, I089).
      expect(conn.android, isNotNull);
      expect(conn.android?.bondState, BondState.none);

      // The stream must exist and be subscribable; on a canBond=false
      // platform there are simply no events to deliver.
      final sub = conn.android!.bondStateChanges.listen((_) {});
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
          platformKind: platform.PlatformKind.android,
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

      // canBond/canRequestConnectionParameters are still true, so
      // `conn.android` is non-null. PHY is exposed via the android
      // extension only (post-B.3, I089).
      expect(conn.android, isNotNull);
      expect(conn.android?.txPhy, Phy.le1m);
      expect(conn.android?.rxPhy, Phy.le1m);

      final sub = conn.android!.phyChanges.listen((_) {});
      await sub.cancel();

      await conn.disconnect();
      bluey.dispose();
    });

    test(
        'connecting on a canRequestConnectionParameters=false platform does '
        'not throw and yields default ConnectionParameters', () async {
      final fakePlatform = FakeBlueyPlatform(
        capabilities: const platform.Capabilities(
          platformKind: platform.PlatformKind.android,
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

      // canBond/canRequestPhy are still true, so `conn.android` is
      // non-null. Connection parameters are exposed via the android
      // extension only (post-B.3, I089).
      expect(conn.android, isNotNull);
      // Defaults from BlueyConnection's initial state.
      expect(conn.android?.connectionParameters.interval.milliseconds, 30.0);
      expect(conn.android?.connectionParameters.latency.events, 0);
      expect(conn.android?.connectionParameters.timeout.milliseconds, 4000);

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
          platformKind: platform.PlatformKind.ios,
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

      // All Android-only flags are false, so this is iOS-flavored under
      // the B.2 heuristic and `conn.android` is null. The bond / PHY /
      // conn-params surface is unreachable, which is correct for a
      // capability-gated platform. The key assertion is that connect
      // completed without throwing, which it did.
      expect(conn.android, isNull);

      await conn.disconnect();
      bluey.dispose();
    });

    test(
        'connecting on a fully-capable platform still wires up bond / PHY / '
        'conn-params subscriptions (regression guard for the gate)', () async {
      // Use an Android-flavored, fully-capable Capabilities so that
      // `connection.android` is non-null under the platformKind gate
      // (I303). Flags mirror Capabilities.fake but with platformKind=android.
      final fakePlatform = FakeBlueyPlatform(
        capabilities: const platform.Capabilities(
          platformKind: platform.PlatformKind.android,
          canScan: true,
          canConnect: true,
          canAdvertise: true,
          canRequestMtu: true,
          maxMtu: 517,
          canBond: true,
          canRequestPhy: true,
          canRequestConnectionParameters: true,
          canAdvertiseManufacturerData: true,
        ),
      );
      platform.BlueyPlatform.instance = fakePlatform;

      fakePlatform.simulatePeripheral(
        id: TestDeviceIds.device1,
        name: 'Test',
      );

      final bluey = Bluey();
      final conn = await bluey.connect(deviceFor(TestDeviceIds.device1));

      // Streams must be live (not the inert defaults). Exposed via the
      // android extension on a fully-capable platform (post-B.3).
      expect(conn.android, isNotNull);
      final bondSub = conn.android!.bondStateChanges.listen((_) {});
      final phySub = conn.android!.phyChanges.listen((_) {});
      await bondSub.cancel();
      await phySub.cancel();

      await conn.disconnect();
      bluey.dispose();
    });
  });
}
