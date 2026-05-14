import 'dart:async';

import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';
import '../fakes/test_helpers.dart';

/// Tests for Convention 2 (replay-on-subscribe) on Connection's four
/// Type A streams: `stateChanges`, `servicesChanges`, `bondStateChanges`,
/// and `phyChanges`. Each new subscriber must receive the connection's
/// current cached value as the first event.
///
/// The dual-subscriber tests are load-bearing: they catch the
/// `StreamController.broadcast(onListen: ...)` antipattern (where
/// `onListen` only fires on the 0→1 subscriber transition). Subscribing
/// a second listener after a first must still replay the value.
/// Android-flavored profile with every Android-specific capability
/// enabled so `connection.android.bondStateChanges` /
/// `connection.android.phyChanges` are reachable without tripping
/// the per-capability gates.
const _androidFlavored = platform.Capabilities(
  platformKind: platform.PlatformKind.android,
  canScan: true,
  canConnect: true,
  canAdvertise: true,
  canBond: true,
  canRequestPhy: true,
  canRequestConnectionParameters: true,
);

void main() {
  late FakeBlueyPlatform fakePlatform;
  late Bluey bluey;

  Future<Connection> establish() async {
    fakePlatform.simulatePeripheral(
      id: TestDeviceIds.device1,
      name: 'Sensor',
      services: const [],
    );
    final device = Device(
      id: UUID('00000000-0000-0000-0000-aabbccddee01'),
      address: TestDeviceIds.device1,
      name: 'Sensor',
    );
    return bluey.connect(device);
  }

  setUp(() async {
    fakePlatform = FakeBlueyPlatform(capabilities: _androidFlavored);
    platform.BlueyPlatform.instance = fakePlatform;
    fakePlatform.setState(platform.BluetoothState.on);
    bluey = await Bluey.create();
  });

  tearDown(() async {
    await bluey.dispose();
    await fakePlatform.dispose();
  });

  group('Connection Type A streams (replay on subscribe)', () {
    // ---------------------------------------------------------------
    // stateChanges
    // ---------------------------------------------------------------

    test('stateChanges: single subscriber receives current value', () async {
      final connection = await establish();
      final received = <ConnectionState>[];
      final sub = connection.stateChanges.listen(received.add);
      await Future<void>.delayed(Duration.zero);
      expect(received, isNotEmpty);
      expect(received.first, equals(connection.state));
      await sub.cancel();
    });

    test('stateChanges: two subscribers each get replay', () async {
      final connection = await establish();
      final r1 = <ConnectionState>[];
      final r2 = <ConnectionState>[];
      final s1 = connection.stateChanges.listen(r1.add);
      await Future<void>.delayed(Duration.zero);
      final s2 = connection.stateChanges.listen(r2.add);
      await Future<void>.delayed(Duration.zero);
      expect(r1, isNotEmpty, reason: 'first subscriber should see replay');
      expect(r2, isNotEmpty, reason: 'second subscriber should also see replay');
      expect(r1.first, equals(connection.state));
      expect(r2.first, equals(connection.state));
      await s1.cancel();
      await s2.cancel();
    });

    // ---------------------------------------------------------------
    // servicesChanges
    // ---------------------------------------------------------------

    test('servicesChanges: single subscriber receives current services',
        () async {
      final connection = await establish();
      final current = await connection.services();
      final received = <List<RemoteService>>[];
      final sub = connection.servicesChanges.listen(received.add);
      await Future<void>.delayed(Duration.zero);
      expect(received, isNotEmpty);
      expect(received.first.length, equals(current.length));
      await sub.cancel();
    });

    test('servicesChanges: two subscribers each get replay', () async {
      final connection = await establish();
      final current = await connection.services();
      final r1 = <List<RemoteService>>[];
      final r2 = <List<RemoteService>>[];
      final s1 = connection.servicesChanges.listen(r1.add);
      await Future<void>.delayed(Duration.zero);
      final s2 = connection.servicesChanges.listen(r2.add);
      await Future<void>.delayed(Duration.zero);
      expect(r1, isNotEmpty, reason: 'first subscriber should see replay');
      expect(r2, isNotEmpty, reason: 'second subscriber should also see replay');
      expect(r1.first.length, equals(current.length));
      expect(r2.first.length, equals(current.length));
      await s1.cancel();
      await s2.cancel();
    });

    // ---------------------------------------------------------------
    // bondStateChanges (Android-only)
    // ---------------------------------------------------------------

    test('bondStateChanges: single subscriber receives current value',
        () async {
      final connection = await establish();
      final android = connection.android!;
      final received = <BondState>[];
      final sub = android.bondStateChanges.listen(received.add);
      await Future<void>.delayed(Duration.zero);
      expect(received, isNotEmpty);
      expect(received.first, equals(android.bondState));
      await sub.cancel();
    });

    test('bondStateChanges: two subscribers each get replay', () async {
      final connection = await establish();
      final android = connection.android!;
      final r1 = <BondState>[];
      final r2 = <BondState>[];
      final s1 = android.bondStateChanges.listen(r1.add);
      await Future<void>.delayed(Duration.zero);
      final s2 = android.bondStateChanges.listen(r2.add);
      await Future<void>.delayed(Duration.zero);
      expect(r1, isNotEmpty, reason: 'first subscriber should see replay');
      expect(r2, isNotEmpty, reason: 'second subscriber should also see replay');
      expect(r1.first, equals(android.bondState));
      expect(r2.first, equals(android.bondState));
      await s1.cancel();
      await s2.cancel();
    });

    // ---------------------------------------------------------------
    // phyChanges (Android-only)
    // ---------------------------------------------------------------

    test('phyChanges: single subscriber receives current value', () async {
      final connection = await establish();
      final android = connection.android!;
      final received = <({Phy tx, Phy rx})>[];
      final sub = android.phyChanges.listen(received.add);
      await Future<void>.delayed(Duration.zero);
      expect(received, isNotEmpty);
      expect(received.first.tx, equals(android.txPhy));
      expect(received.first.rx, equals(android.rxPhy));
      await sub.cancel();
    });

    test('phyChanges: two subscribers each get replay', () async {
      final connection = await establish();
      final android = connection.android!;
      final r1 = <({Phy tx, Phy rx})>[];
      final r2 = <({Phy tx, Phy rx})>[];
      final s1 = android.phyChanges.listen(r1.add);
      await Future<void>.delayed(Duration.zero);
      final s2 = android.phyChanges.listen(r2.add);
      await Future<void>.delayed(Duration.zero);
      expect(r1, isNotEmpty, reason: 'first subscriber should see replay');
      expect(r2, isNotEmpty, reason: 'second subscriber should also see replay');
      expect(r1.first.tx, equals(android.txPhy));
      expect(r2.first.tx, equals(android.txPhy));
      await s1.cancel();
      await s2.cancel();
    });
  });

  group('Connection.stateChanges (Convention 3 — terminal signal)', () {
    test(
      'emits ConnectionState.invalidated then closes on adapter invalidation',
      () async {
        final connection = await establish();
        final received = <ConnectionState>[];
        final completer = Completer<void>();

        connection.stateChanges.listen(
          received.add,
          onDone: completer.complete,
        );
        await Future<void>.delayed(Duration.zero);

        fakePlatform.setState(platform.BluetoothState.off);
        await completer.future;

        expect(received.last, equals(ConnectionState.invalidated));
      },
    );

    test('connection.state returns invalidated after adapter invalidation', () async {
      final connection = await establish();
      fakePlatform.setState(platform.BluetoothState.off);
      await Future<void>.delayed(const Duration(milliseconds: 5));

      expect(connection.state, equals(ConnectionState.invalidated));
    });
  });

  group('Connection non-enum streams (Convention 3 — addError + close)', () {
    test(
      'servicesChanges errors with StaleHandleException then closes on invalidation',
      () async {
        final connection = await establish();
        Object? errorReceived;
        final completer = Completer<void>();

        connection.servicesChanges.listen(
          (_) {},
          onError: (e) => errorReceived = e,
          onDone: completer.complete,
        );
        await Future<void>.delayed(Duration.zero);

        fakePlatform.setState(platform.BluetoothState.off);
        await completer.future;

        expect(errorReceived, isA<StaleHandleException>());
      },
    );

    test(
      'bondStateChanges errors with StaleHandleException then closes',
      () async {
        final connection = await establish();
        final android = connection.android!;
        Object? errorReceived;
        final completer = Completer<void>();

        android.bondStateChanges.listen(
          (_) {},
          onError: (e) => errorReceived = e,
          onDone: completer.complete,
        );
        await Future<void>.delayed(Duration.zero);

        fakePlatform.setState(platform.BluetoothState.off);
        await completer.future;

        expect(errorReceived, isA<StaleHandleException>());
      },
    );

    test(
      'phyChanges errors with StaleHandleException then closes',
      () async {
        final connection = await establish();
        final android = connection.android!;
        Object? errorReceived;
        final completer = Completer<void>();

        android.phyChanges.listen(
          (_) {},
          onError: (e) => errorReceived = e,
          onDone: completer.complete,
        );
        await Future<void>.delayed(Duration.zero);

        fakePlatform.setState(platform.BluetoothState.off);
        await completer.future;

        expect(errorReceived, isA<StaleHandleException>());
      },
    );
  });
}
