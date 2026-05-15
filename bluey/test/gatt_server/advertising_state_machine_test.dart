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
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await server.stopAdvertising();
        await Future<void>.delayed(const Duration(milliseconds: 10));

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
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await server.stopAdvertising();
      await Future<void>.delayed(const Duration(milliseconds: 5));

      expect(events.whereType<AdvertisingStartingEvent>().length, equals(1));
      expect(events.whereType<AdvertisingStartedEvent>().length, equals(1));
      expect(events.whereType<AdvertisingStoppingEvent>().length, equals(1));
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
      await Future<void>.delayed(const Duration(milliseconds: 5));

      final started = events.whereType<AdvertisingStartedEvent>().single;
      expect(started.name, equals('My Device'));
      expect(started.services, equals(services));
    });
  });
}
