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
    bluey = await Bluey.create();
  });

  tearDown(() async {
    await bluey.dispose();
    await fakePlatform.dispose();
  });

  group('Scanner adapter-state invalidation', () {
    test('subsequent scan() throws StaleHandleException after off', () async {
      final scanner = bluey.scanner();

      fakePlatform.setState(platform.BluetoothState.off);
      await Future<void>.delayed(const Duration(milliseconds: 5));

      expect(() => scanner.scan(), throwsA(isA<StaleHandleException>()));
    });

    test('active scan stream closes on invalidation', () async {
      final scanner = bluey.scanner();
      final scanClosed = Completer<void>();

      scanner.scan().listen((_) {}, onDone: scanClosed.complete);

      fakePlatform.setState(platform.BluetoothState.off);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(scanClosed.isCompleted, isTrue);
    });

    test('stays invalidated after adapter returns to on', () async {
      final scanner = bluey.scanner();

      fakePlatform.setState(platform.BluetoothState.off);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      fakePlatform.setState(platform.BluetoothState.on);
      await Future<void>.delayed(const Duration(milliseconds: 5));

      expect(() => scanner.scan(), throwsA(isA<StaleHandleException>()));
    });

    test(
      'triggeringState reflects the state that caused invalidation',
      () async {
        final scanner = bluey.scanner();

        fakePlatform.setState(platform.BluetoothState.unauthorized);
        await Future<void>.delayed(const Duration(milliseconds: 5));

        try {
          scanner.scan();
          fail('expected StaleHandleException');
        } on StaleHandleException catch (e) {
          expect(e.triggeringState, equals(BluetoothState.unauthorized));
          expect(e.instanceType, equals(InvalidatedInstance.scanner));
        }
      },
    );

    // H1 — defensive: if the platform's stateStream surfaces an error
    // (e.g. native channel glitch), the scanner must invalidate rather
    // than let an unhandled async error escape.
    test('platform stateStream error invalidates the scanner', () async {
      final scanner = bluey.scanner();

      fakePlatform.simulateStateError(StateError('platform glitch'));
      await Future<void>.delayed(const Duration(milliseconds: 5));

      expect(() => scanner.scan(), throwsA(isA<StaleHandleException>()));
    });
  });
}
