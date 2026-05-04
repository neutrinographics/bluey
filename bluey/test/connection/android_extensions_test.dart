import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';
import '../fakes/test_helpers.dart';

/// Tests for the [Connection.android] / [Connection.ios] accessors that
/// gate platform-specific extensions by [Capabilities.platformKind]
/// (I089 / Task 3 of the capabilities-matrix bundle).
///
/// The accessors dispatch on `capabilities.platformKind`:
///   * `connection.android` — non-null when `platformKind == android`.
///   * `connection.ios`     — non-null when `platformKind == ios`.
///
/// The opposite-side accessor is null in each case, and `platformKind`
/// values of `fake` / `other` expose neither extension. Both accessors
/// lazy-cache the underlying impl so repeated reads return the same
/// instance.
///
/// The capability-flag-level gating of the methods *on* `connection.android`
/// (e.g. `bond()` requires `canBond`) is covered in
/// `capability_gating_test.dart`; this file focuses on the accessor
/// dispatch and the "still wired up" smoke tests for an Android-flavored
/// connection.
void main() {
  Device deviceFor(String address) => Device(
    id: UUID('00000000-0000-0000-0000-aabbccddee01'),
    address: address,
    name: 'Test Device',
  );

  /// Android-flavored profile: `platformKind == android` plus every
  /// Android-specific feature flag enabled, so the methods on
  /// `connection.android` are reachable without tripping the
  /// per-capability gates.
  const androidFlavored = platform.Capabilities(
    platformKind: platform.PlatformKind.android,
    canScan: true,
    canConnect: true,
    canAdvertise: true,
    canBond: true,
    canRequestPhy: true,
    canRequestConnectionParameters: true,
  );

  /// iOS-flavored profile: `platformKind == ios`, with the
  /// Android-specific flags off (matching the real iOS implementation).
  const iosFlavored = platform.Capabilities(
    platformKind: platform.PlatformKind.ios,
    canScan: true,
    canConnect: true,
    canAdvertise: true,
    canBond: false,
    canRequestPhy: false,
    canRequestConnectionParameters: false,
  );

  group('Connection.android accessor', () {
    test('is non-null when platformKind == android', () async {
      final fakePlatform = FakeBlueyPlatform(capabilities: androidFlavored);
      platform.BlueyPlatform.instance = fakePlatform;

      fakePlatform.simulatePeripheral(id: TestDeviceIds.device1, name: 'Test');

      final bluey = Bluey();
      final conn = await bluey.connect(deviceFor(TestDeviceIds.device1));

      expect(conn.android, isNotNull);

      await conn.disconnect();
      bluey.dispose();
    });

    test('is null when platformKind == ios', () async {
      final fakePlatform = FakeBlueyPlatform(capabilities: iosFlavored);
      platform.BlueyPlatform.instance = fakePlatform;

      fakePlatform.simulatePeripheral(id: TestDeviceIds.device1, name: 'Test');

      final bluey = Bluey();
      final conn = await bluey.connect(deviceFor(TestDeviceIds.device1));

      expect(conn.android, isNull);

      await conn.disconnect();
      bluey.dispose();
    });

    test('returns the same instance on repeated reads (lazy cache)', () async {
      final fakePlatform = FakeBlueyPlatform(capabilities: androidFlavored);
      platform.BlueyPlatform.instance = fakePlatform;

      fakePlatform.simulatePeripheral(id: TestDeviceIds.device1, name: 'Test');

      final bluey = Bluey();
      final conn = await bluey.connect(deviceFor(TestDeviceIds.device1));

      final first = conn.android;
      final second = conn.android;
      expect(identical(first, second), isTrue);

      await conn.disconnect();
      bluey.dispose();
    });

    test(
      'android.bond() resolves without throwing on a canBond=true fake',
      () async {
        final fakePlatform = FakeBlueyPlatform(capabilities: androidFlavored);
        platform.BlueyPlatform.instance = fakePlatform;

        fakePlatform.simulatePeripheral(
          id: TestDeviceIds.device1,
          name: 'Test',
        );

        final bluey = Bluey();
        final conn = await bluey.connect(deviceFor(TestDeviceIds.device1));

        // Post-B.3, `connection.bond()` is gone — bonding is reachable
        // only via `connection.android?.bond()`.
        await conn.android?.bond();

        await conn.disconnect();
        bluey.dispose();
      },
    );

    test('android?.bond() short-circuits to null when platformKind == ios '
        'and never reaches the platform', () async {
      final fakePlatform = FakeBlueyPlatform(capabilities: iosFlavored);
      platform.BlueyPlatform.instance = fakePlatform;

      fakePlatform.simulatePeripheral(id: TestDeviceIds.device1, name: 'Test');

      final bluey = Bluey();
      final conn = await bluey.connect(deviceFor(TestDeviceIds.device1));

      // `connection.android` is null, so `?.bond()` evaluates to null and
      // the platform's `bond` (which would throw UnimplementedError on a
      // canBond=false fake) is never called.
      final result = conn.android?.bond();
      expect(result, isNull);

      await conn.disconnect();
      bluey.dispose();
    });

    test('exposes bond/PHY/connection-parameter delegates with sensible '
        'initial values', () async {
      final fakePlatform = FakeBlueyPlatform(capabilities: androidFlavored);
      platform.BlueyPlatform.instance = fakePlatform;

      fakePlatform.simulatePeripheral(id: TestDeviceIds.device1, name: 'Test');

      final bluey = Bluey();
      final conn = await bluey.connect(deviceFor(TestDeviceIds.device1));

      // Post-B.3 (I089), bond/PHY/conn-params live behind
      // `connection.android` and are no longer reachable via the
      // top-level `Connection` API. Verify the facade exposes the
      // expected initial values from BlueyConnection's private state.
      final android = conn.android!;
      expect(android.bondState, equals(BondState.none));
      expect(android.txPhy, equals(Phy.le1m));
      expect(android.rxPhy, equals(Phy.le1m));
      expect(android.connectionParameters.interval.milliseconds, 30.0);
      expect(android.connectionParameters.latency.events, 0);
      expect(android.connectionParameters.timeout.milliseconds, 4000);

      await conn.disconnect();
      bluey.dispose();
    });
  });

  group('Connection.ios accessor', () {
    test('is non-null when platformKind == ios', () async {
      final fakePlatform = FakeBlueyPlatform(capabilities: iosFlavored);
      platform.BlueyPlatform.instance = fakePlatform;

      fakePlatform.simulatePeripheral(id: TestDeviceIds.device1, name: 'Test');

      final bluey = Bluey();
      final conn = await bluey.connect(deviceFor(TestDeviceIds.device1));

      expect(conn.ios, isNotNull);

      await conn.disconnect();
      bluey.dispose();
    });

    test('is null when platformKind == android', () async {
      final fakePlatform = FakeBlueyPlatform(capabilities: androidFlavored);
      platform.BlueyPlatform.instance = fakePlatform;

      fakePlatform.simulatePeripheral(id: TestDeviceIds.device1, name: 'Test');

      final bluey = Bluey();
      final conn = await bluey.connect(deviceFor(TestDeviceIds.device1));

      expect(conn.ios, isNull);

      await conn.disconnect();
      bluey.dispose();
    });

    test('returns the same singleton instance on repeated reads', () async {
      final fakePlatform = FakeBlueyPlatform(capabilities: iosFlavored);
      platform.BlueyPlatform.instance = fakePlatform;

      fakePlatform.simulatePeripheral(id: TestDeviceIds.device1, name: 'Test');

      final bluey = Bluey();
      final conn = await bluey.connect(deviceFor(TestDeviceIds.device1));

      final first = conn.ios;
      final second = conn.ios;
      expect(identical(first, second), isTrue);

      await conn.disconnect();
      bluey.dispose();
    });
  });
}
