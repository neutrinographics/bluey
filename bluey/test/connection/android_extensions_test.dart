import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';
import '../fakes/test_helpers.dart';

/// Tests for the [Connection.android] / [Connection.ios] accessors that
/// gate platform-specific extensions by [Capabilities] (B.2 / I089).
///
/// The accessors return non-null only on the matching capability profile:
///   * `connection.android` — non-null when at least one of `canBond`,
///     `canRequestPhy`, or `canRequestConnectionParameters` is true.
///   * `connection.ios` — non-null when ALL three of those flags are
///     false (heuristic: "no Android-only features" means iOS-flavored).
///
/// Both accessors return null on the opposite profile, and lazy-cache the
/// underlying impl so repeated reads return the same instance.
void main() {
  Device deviceFor(String address) => Device(
        id: UUID('00000000-0000-0000-0000-aabbccddee01'),
        address: address,
        name: 'Test Device',
      );

  /// Capabilities profile where at least one Android-only flag is true.
  /// `Capabilities.android` itself currently has all three false (post-I035
  /// Stage A), so we construct an explicit profile here.
  const androidFlavored = platform.Capabilities(
    platformKind: platform.PlatformKind.android,
    canScan: true,
    canConnect: true,
    canAdvertise: true,
    canBond: true,
    canRequestPhy: true,
    canRequestConnectionParameters: true,
  );

  /// Capabilities profile with all three Android-only flags false. This is
  /// the iOS-flavored profile under the B.2 heuristic.
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
    test(
        'is non-null when at least one of canBond / canRequestPhy / '
        'canRequestConnectionParameters is true', () async {
      final fakePlatform = FakeBlueyPlatform(capabilities: androidFlavored);
      platform.BlueyPlatform.instance = fakePlatform;

      fakePlatform.simulatePeripheral(id: TestDeviceIds.device1, name: 'Test');

      final bluey = Bluey();
      final conn = await bluey.connect(deviceFor(TestDeviceIds.device1));

      expect(conn.android, isNotNull);

      await conn.disconnect();
      bluey.dispose();
    });

    test('is null when all three Android-only flags are false', () async {
      final fakePlatform = FakeBlueyPlatform(capabilities: iosFlavored);
      platform.BlueyPlatform.instance = fakePlatform;

      fakePlatform.simulatePeripheral(id: TestDeviceIds.device1, name: 'Test');

      final bluey = Bluey();
      final conn = await bluey.connect(deviceFor(TestDeviceIds.device1));

      expect(conn.android, isNull);

      await conn.disconnect();
      bluey.dispose();
    });

    test('returns the same instance on repeated reads (lazy cache)',
        () async {
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

    test('android.bond() resolves without throwing on a canBond=true fake',
        () async {
      final fakePlatform = FakeBlueyPlatform(capabilities: androidFlavored);
      platform.BlueyPlatform.instance = fakePlatform;

      fakePlatform.simulatePeripheral(id: TestDeviceIds.device1, name: 'Test');

      final bluey = Bluey();
      final conn = await bluey.connect(deviceFor(TestDeviceIds.device1));

      // Post-B.3, `connection.bond()` is gone — bonding is reachable
      // only via `connection.android?.bond()`.
      await conn.android?.bond();

      await conn.disconnect();
      bluey.dispose();
    });

    test(
        'android?.bond() short-circuits to null on iOS-flavored caps and '
        'never reaches the platform', () async {
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
    test('is non-null when all three Android-only flags are false', () async {
      final fakePlatform = FakeBlueyPlatform(capabilities: iosFlavored);
      platform.BlueyPlatform.instance = fakePlatform;

      fakePlatform.simulatePeripheral(id: TestDeviceIds.device1, name: 'Test');

      final bluey = Bluey();
      final conn = await bluey.connect(deviceFor(TestDeviceIds.device1));

      expect(conn.ios, isNotNull);

      await conn.disconnect();
      bluey.dispose();
    });

    test('is null when any Android-only flag is true', () async {
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
