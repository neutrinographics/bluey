import 'dart:async';

import 'package:bluey/bluey.dart';
import 'package:bluey/src/api/connection/android_connection.dart';
import 'package:bluey/src/features/connection/application/bonding_session.dart';
import 'package:bluey/src/features/connection/application/link_session.dart';
import 'package:bluey/src/features/connection/application/mtu_session.dart';
import 'package:bluey/src/features/connection/application/parameter_session.dart';
import 'package:bluey/src/features/connection/application/phy_session.dart';
import 'package:bluey/src/features/connection/domain/link_end.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_platform.dart';
import '../../fakes/test_helpers.dart';
import '../../fixtures/features/connection/application/ports/in_memory_bonding.dart';
import '../../fixtures/features/connection/application/ports/in_memory_connection_ports.dart';
import '../../fixtures/features/connection/application/ports/in_memory_links.dart';
import '../../fixtures/features/connection/application/ports/in_memory_mtu_negotiation.dart';
import '../../fixtures/features/connection/application/ports/in_memory_parameter_control.dart';
import '../../fixtures/features/connection/application/ports/in_memory_phy_control.dart';
import '../../fixtures/features/connection/application/up_session.dart';
import '../../fixtures/shared/application/recording_log.dart';

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
  Device deviceFor(String address) =>
      Device(address: DeviceAddress(address), name: 'Test Device');

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

      final bluey = await Bluey.create();
      final conn = await bluey.connect(deviceFor(TestDeviceIds.device1));

      expect(conn.android, isNotNull);

      await conn.disconnect();
      bluey.dispose();
    });

    test('is null when platformKind == ios', () async {
      final fakePlatform = FakeBlueyPlatform(capabilities: iosFlavored);
      platform.BlueyPlatform.instance = fakePlatform;

      fakePlatform.simulatePeripheral(id: TestDeviceIds.device1, name: 'Test');

      final bluey = await Bluey.create();
      final conn = await bluey.connect(deviceFor(TestDeviceIds.device1));

      expect(conn.android, isNull);

      await conn.disconnect();
      bluey.dispose();
    });

    test('returns the same instance on repeated reads (lazy cache)', () async {
      final fakePlatform = FakeBlueyPlatform(capabilities: androidFlavored);
      platform.BlueyPlatform.instance = fakePlatform;

      fakePlatform.simulatePeripheral(id: TestDeviceIds.device1, name: 'Test');

      final bluey = await Bluey.create();
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

        final bluey = await Bluey.create();
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

      final bluey = await Bluey.create();
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

      final bluey = await Bluey.create();
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

      final bluey = await Bluey.create();
      final conn = await bluey.connect(deviceFor(TestDeviceIds.device1));

      expect(conn.ios, isNotNull);

      await conn.disconnect();
      bluey.dispose();
    });

    test('is null when platformKind == android', () async {
      final fakePlatform = FakeBlueyPlatform(capabilities: androidFlavored);
      platform.BlueyPlatform.instance = fakePlatform;

      fakePlatform.simulatePeripheral(id: TestDeviceIds.device1, name: 'Test');

      final bluey = await Bluey.create();
      final conn = await bluey.connect(deviceFor(TestDeviceIds.device1));

      expect(conn.ios, isNull);

      await conn.disconnect();
      bluey.dispose();
    });

    test('returns the same singleton instance on repeated reads', () async {
      final fakePlatform = FakeBlueyPlatform(capabilities: iosFlavored);
      platform.BlueyPlatform.instance = fakePlatform;

      fakePlatform.simulatePeripheral(id: TestDeviceIds.device1, name: 'Test');

      final bluey = await Bluey.create();
      final conn = await bluey.connect(deviceFor(TestDeviceIds.device1));

      final first = conn.ios;
      final second = conn.ios;
      expect(identical(first, second), isTrue);

      await conn.disconnect();
      bluey.dispose();
    });
  });

  group('AndroidConnection over in-memory ports', () {
    const device = DeviceAddress('AA:BB:CC:DD:EE:01');
    final timing = ConnectionParameters(
      interval: ConnectionInterval(45),
      latency: PeripheralLatency(2),
      timeout: SupervisionTimeout(6000),
    );

    late InMemoryLinks links;
    late InMemoryBonding bonding;
    late InMemoryPhyControl phy;
    late InMemoryParameterControl parameters;
    late InMemoryMtuNegotiation mtu;
    late LinkSession session;
    late AndroidConnection android;

    setUp(() async {
      links = InMemoryLinks();
      final ports = inMemoryConnectionPorts(links: links);
      bonding = ports.bonding as InMemoryBonding;
      phy = ports.phy as InMemoryPhyControl;
      parameters = ports.parameters as InMemoryParameterControl;
      mtu = ports.mtu as InMemoryMtuNegotiation;
      session = await upSession(links, device);
      final log = RecordingLog();
      android = AndroidConnection(
        session: session,
        bonding: BondingSession(
          session: session,
          bonding: bonding,
          features: ports.features,
          log: log,
        ),
        phy: PhySession(
          session: session,
          phy: phy,
          features: ports.features,
          log: log,
        ),
        parameters: ParameterSession(
          session: session,
          parameters: parameters,
          features: ports.features,
          log: log,
        ),
        mtu: MtuSession(
          session: session,
          negotiation: mtu,
          features: ports.features,
          log: log,
          now: DateTime.now,
        ),
        platform: 'android',
      );
    });

    test('each member answers what its session holds', () async {
      // arrange
      bonding.report(session.id, BondState.bonded);
      phy.report(session.id, (tx: Phy.le2m, rx: Phy.leCoded));
      mtu.settleAt(185);

      // act
      await android.requestConnectionParameters(timing);
      final negotiated = await android.requestMtu(Mtu(247));
      await pumpEventQueue();

      // assert
      expect(android.bondState, BondState.bonded);
      expect((android.txPhy, android.rxPhy), (Phy.le2m, Phy.leCoded));
      expect(android.connectionParameters, timing);
      expect((negotiated, android.mtu), (Mtu(185), Mtu(185)));
    });

    test('bond and removeBond ask the bonding session', () async {
      // act
      await android.bond();
      await android.removeBond();

      // assert
      expect(bonding.asked.map((asked) => asked.$1.name).toList().sublist(2), [
        'bond',
        'removeBond',
      ]);
    });

    test('bondStateChanges and phyChanges end without an error on a '
        'disconnect', () async {
      // arrange
      final bondErrors = <Object>[];
      final phyErrors = <Object>[];
      final bondEnded = Completer<void>();
      final phyEnded = Completer<void>();
      android.bondStateChanges.listen(
        (_) {},
        onError: bondErrors.add,
        onDone: bondEnded.complete,
      );
      android.phyChanges.listen(
        (_) {},
        onError: phyErrors.add,
        onDone: phyEnded.complete,
      );

      // act
      await session.disconnect();
      await Future.wait([bondEnded.future, phyEnded.future]);

      // assert
      expect(bondErrors, isEmpty);
      expect(phyErrors, isEmpty);
    });

    test('a listener after a radio outage gets StaleHandleException and no '
        'value', () async {
      // arrange
      links.outage(RadioOutage.off);
      await pumpEventQueue();
      final seen = <Object?>[];

      // act
      await android.bondStateChanges.handleError(seen.add).forEach(seen.add);
      await android.phyChanges.handleError(seen.add).forEach(seen.add);

      // assert
      expect(seen, [isA<StaleHandleException>(), isA<StaleHandleException>()]);
    });

    test('a listener before a radio outage gets its values, then '
        'StaleHandleException, then the end', () async {
      // arrange
      final seen = <Object?>[];
      final ended = android.bondStateChanges
          .handleError((Object error) => seen.add(error))
          .forEach(seen.add);
      bonding.report(session.id, BondState.bonding);
      await pumpEventQueue();

      // act
      links.outage(RadioOutage.off);
      await ended;

      // assert
      expect(seen, [
        BondState.none,
        BondState.bonding,
        isA<StaleHandleException>(),
      ]);
    });

    test('requestPhy passes each direction to the session under its own '
        'name', () async {
      // act
      await android.requestPhy(txPhy: Phy.le2m);

      // assert
      expect(phy.requests, [(tx: Phy.le2m, rx: null)]);
    });
  });
}
