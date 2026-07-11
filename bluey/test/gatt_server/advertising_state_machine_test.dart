import 'dart:async';

import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';

void main() {
  late FakeBlueyPlatform fakePlatform;
  late Bluey bluey;

  setUp(() async {
    fakePlatform = FakeBlueyPlatform(
      capabilities: platform.Capabilities.android,
    );
    platform.BlueyPlatform.instance = fakePlatform;
    fakePlatform.setState(platform.BluetoothState.on);
    bluey = await Bluey.create();
  });

  tearDown(() async {
    await bluey.dispose();
    await fakePlatform.dispose();
  });

  group('Server advertising state machine', () {
    test('initial state is idle', () {
      final server = bluey.server()!;
      expect(server.advertisingState, equals(AdvertisingState.idle));
    });

    test(
      'startAdvertising / stopAdvertising drive transitions',
      () async {
        final server = bluey.server()!;
        final observed = <AdvertisingState>[];
        final sub = server.advertisingStateChanges.listen(observed.add);

        await server.startAdvertising();
        await pumpEventQueue();
        await server.stopAdvertising();
        await pumpEventQueue();

        expect(
          observed,
          containsAllInOrder([
            AdvertisingState.idle, // replay
            AdvertisingState.starting,
            AdvertisingState.advertising,
            AdvertisingState.stopping,
            AdvertisingState.idle,
          ]),
        );

        await sub.cancel();
      },
    );

    test('isAdvertising derived from state', () async {
      final server = bluey.server()!;
      expect(server.isAdvertising, isFalse);

      await server.startAdvertising();
      expect(server.isAdvertising, isTrue);
      expect(server.advertisingState, equals(AdvertisingState.advertising));

      await server.stopAdvertising();
      expect(server.isAdvertising, isFalse);
    });

    test('transitions to invalidated on adapter off', () async {
      final server = bluey.server()!;
      await server.startAdvertising();
      final observed = <AdvertisingState>[];
      final closed = Completer<void>();
      server.advertisingStateChanges.listen(
        observed.add,
        onDone: closed.complete,
      );

      fakePlatform.setState(platform.BluetoothState.off);
      await closed.future;

      expect(observed.last, equals(AdvertisingState.invalidated));
      expect(server.advertisingState, equals(AdvertisingState.invalidated));
    });

    test('emits AdvertisingStarting/AdvertisingStopping events', () async {
      final server = bluey.server()!;
      final events = <BlueyEvent>[];
      bluey.events.listen(events.add);

      await server.startAdvertising();
      await pumpEventQueue();
      await server.stopAdvertising();
      await pumpEventQueue();

      expect(events.whereType<AdvertisingStartingEvent>().length, equals(1));
      expect(events.whereType<AdvertisingStartedEvent>().length, equals(1));
      expect(events.whereType<AdvertisingStoppingEvent>().length, equals(1));
      expect(events.whereType<AdvertisingStoppedEvent>().length, equals(1));
    });

    // H2 — late subscriber after invalidation observes the terminal
    // `AdvertisingState.invalidated` value followed by onDone. Without
    // this guard, a refactor of `_invalidate`'s ordering or of the
    // `advertisingStateChanges` factory could silently regress late-
    // subscriber semantics (Convention 3).
    test(
      'late subscriber after invalidation receives AdvertisingState.invalidated and onDone',
      () async {
        final server = bluey.server()!;
        fakePlatform.setState(platform.BluetoothState.off);
        await pumpEventQueue();

        final received = <AdvertisingState>[];
        final completer = Completer<void>();
        server.advertisingStateChanges.listen(
          received.add,
          onDone: completer.complete,
        );
        await completer.future;

        expect(received, equals([AdvertisingState.invalidated]));
      },
    );

    // M3 — Stream.multi runs its factory per subscriber so every late
    // subscriber gets the replay. A regression to
    // `StreamController.broadcast(onListen:)` would only fire the
    // replay on the 0→1 transition.
    test('multiple sequential subscribers each receive replay', () async {
      final server = bluey.server()!;

      final firstReplay = await server.advertisingStateChanges.first;
      expect(firstReplay, equals(AdvertisingState.idle));

      final secondReplay = await server.advertisingStateChanges.first;
      expect(secondReplay, equals(AdvertisingState.idle));
    });

    // L1 — same-state writes to _setAdvertisingState must not emit
    // duplicate events on the stream or event bus.
    test('same-state transitions are idempotent', () async {
      final server = bluey.server()!;
      final observed = <AdvertisingState>[];
      final sub = server.advertisingStateChanges.listen(observed.add);

      // Two stopAdvertising calls back-to-back; both short-circuit
      // because we're not currently advertising. No duplicate idle
      // events beyond the single replay value.
      await server.stopAdvertising();
      await server.stopAdvertising();
      await pumpEventQueue();

      expect(observed, equals([AdvertisingState.idle]));

      await sub.cancel();
    });

    // M2 — when the platform rejects startAdvertising, the state
    // machine must roll back to `idle`. The emitted events on
    // `bluey.events` should be Starting → Stopped with no intervening
    // Started; the rethrow must surface to the caller.
    test('rolls back to idle when platform start fails', () async {
      final server = bluey.server()!;
      final events = <BlueyEvent>[];
      bluey.events.listen(events.add);

      fakePlatform.advertisingShouldFail = true;
      await expectLater(
        server.startAdvertising(name: 'Boom'),
        throwsA(isA<StateError>()),
      );
      await pumpEventQueue();

      expect(server.advertisingState, equals(AdvertisingState.idle));
      expect(events.whereType<AdvertisingStartingEvent>().length, equals(1));
      expect(events.whereType<AdvertisingStartedEvent>().length, equals(0));
      expect(events.whereType<AdvertisingStoppedEvent>().length, equals(1));
    });

    // Regression guard (PR #32 Codex P2): AdvertisingStartedEvent must
    // carry the `name` and `services` arguments passed to
    // startAdvertising. Without this, consumers of `bluey.events` lose
    // audit information about which name / service UUIDs were
    // advertised.
    test('AdvertisingStartedEvent carries name and services', () async {
      final server = bluey.server()!;
      final events = <BlueyEvent>[];
      bluey.events.listen(events.add);

      final services = [UUID.short(0x180F)];
      await server.startAdvertising(name: 'My Device', services: services);
      await pumpEventQueue();

      final started = events.whereType<AdvertisingStartedEvent>().single;
      expect(started.name, equals('My Device'));
      expect(started.services, equals(services));
    });
  });
}
