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

  group('Scanner state machine', () {
    test('initial state is stopped', () {
      final scanner = bluey.scanner();
      expect(scanner.state, equals(ScanState.stopped));
    });

    test(
      'transitions stopped -> starting -> scanning -> stopping -> stopped',
      () async {
        final scanner = bluey.scanner();
        final observed = <ScanState>[];
        final sub = scanner.stateChanges.listen(observed.add);

        final scanSub = scanner.scan().listen((_) {});
        await Future<void>.delayed(const Duration(milliseconds: 20));

        await scanSub.cancel();
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(
          observed,
          containsAllInOrder([
            ScanState.stopped, // replay
            ScanState.starting,
            ScanState.scanning,
            ScanState.stopping,
            ScanState.stopped,
          ]),
        );

        await sub.cancel();
      },
    );

    test('isScanning is derived from state', () async {
      final scanner = bluey.scanner();
      expect(scanner.isScanning, isFalse);

      final scanSub = scanner.scan().listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(scanner.isScanning, isTrue);
      expect(scanner.state, equals(ScanState.scanning));

      await scanSub.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(scanner.isScanning, isFalse);
    });

    test('transitions to invalidated on adapter off', () async {
      final scanner = bluey.scanner();
      final observed = <ScanState>[];
      final closed = Completer<void>();
      scanner.stateChanges.listen(
        observed.add,
        onDone: closed.complete,
      );

      fakePlatform.setState(platform.BluetoothState.off);
      await closed.future;

      expect(observed.last, equals(ScanState.invalidated));
      expect(scanner.state, equals(ScanState.invalidated));
    });

    test('emits ScanStarting/ScanStopping events at transitions', () async {
      final scanner = bluey.scanner();
      final events = <BlueyEvent>[];
      bluey.events.listen(events.add);

      final scanSub = scanner.scan().listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await scanSub.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(events.whereType<ScanStartingEvent>().length, equals(1));
      expect(events.whereType<ScanStartedEvent>().length, equals(1));
      expect(events.whereType<ScanStoppingEvent>().length, equals(1));
      expect(events.whereType<ScanStoppedEvent>().length, equals(1));
    });

    // Regression guard (PR #32 Codex P2): the transition helper must
    // carry the active scan's `services` filter and `timeout` through
    // to ScanStartingEvent and ScanStartedEvent. Without this, consumers
    // of `bluey.events` lose audit information about which filter / cap
    // was applied to a scan.
    test('ScanStarting/Started events carry serviceFilter and timeout',
        () async {
      final scanner = bluey.scanner();
      final events = <BlueyEvent>[];
      bluey.events.listen(events.add);

      final filter = [UUID.short(0x180F)];
      const timeout = Duration(seconds: 30);

      final scanSub =
          scanner.scan(services: filter, timeout: timeout).listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await scanSub.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final starting = events.whereType<ScanStartingEvent>().single;
      expect(starting.serviceFilter, equals(filter));
      expect(starting.timeout, equals(timeout));

      final started = events.whereType<ScanStartedEvent>().single;
      expect(started.serviceFilter, equals(filter));
      expect(started.timeout, equals(timeout));
    });
  });
}
