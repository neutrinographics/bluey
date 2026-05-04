import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';
import '../fakes/test_helpers.dart';

/// Integration tests for the end-to-end log pipeline (I307 / Phase A.10).
///
/// These tests drive a representative connect → discover → disconnect
/// flow against [FakeBlueyPlatform] and assert that the expected log
/// sequence emerges on `bluey.logEvents`. They are the load-bearing
/// proof that the logger is wired through the [Bluey] and
/// [BlueyConnection] subsystems and emits the right events at the
/// right points.
void main() {
  late FakeBlueyPlatform fakePlatform;

  setUp(() {
    fakePlatform = FakeBlueyPlatform();
    platform.BlueyPlatform.instance = fakePlatform;
    Bluey.resetShared();

    // A device with a couple of services so service discovery has
    // something to resolve.
    fakePlatform.simulatePeripheral(
      id: TestDeviceIds.device1,
      name: 'Logger Test Device',
      services: [
        TestServiceBuilder(
          TestUuids.heartRateService,
        ).withNotifiable(TestUuids.heartRateMeasurement).build(),
        TestServiceBuilder(
          TestUuids.batteryService,
        ).withReadable(TestUuids.batteryLevel).build(),
      ],
    );
  });

  /// Helper: render an event as `'context:message'` for sequence assertions.
  String tag(BlueyLogEvent e) => '${e.context}:${e.message}';

  group('Log integration: connect → services → disconnect', () {
    test('emits the expected log sequence at trace level', () async {
      final bluey = Bluey();
      bluey.setLogLevel(BlueyLogLevel.trace);

      final events = <BlueyLogEvent>[];
      final sub = bluey.logEvents.listen(events.add);

      final device = await scanFirstDevice(bluey);
      final connection = await bluey.connect(device);
      await connection.services();
      await connection.disconnect();

      // Allow the broadcast stream to deliver any remaining events.
      await Future<void>.delayed(Duration.zero);

      final tags = events.map(tag).toList();

      // The expected ordered milestones. Other events may interleave
      // (e.g. state transitions, peer probes), so we use containsAllInOrder.
      expect(
        tags,
        containsAllInOrder([
          'bluey:connect entered',
          'bluey.connection:services discovery started',
          'bluey.connection:services discovery resolved',
          'bluey.connection:disconnect entered',
        ]),
      );

      // Every event should have a timestamp set close to now (within
      // a generous slack window — exact value isn't load-bearing).
      final now = DateTime.now();
      for (final e in events) {
        expect(
          now.difference(e.timestamp).abs(),
          lessThan(const Duration(seconds: 30)),
          reason: 'event timestamp should be set: $e',
        );
      }

      await sub.cancel();
      await bluey.dispose();
    });

    test('warn level filters out the happy-path info events', () async {
      final bluey = Bluey();
      bluey.setLogLevel(BlueyLogLevel.warn);

      final events = <BlueyLogEvent>[];
      final sub = bluey.logEvents.listen(events.add);

      final device = await scanFirstDevice(bluey);
      final connection = await bluey.connect(device);
      await connection.services();
      await connection.disconnect();

      await Future<void>.delayed(Duration.zero);

      // Whatever leaks through must be at warn or error severity.
      // The happy path emits only info/debug/trace events, so this list
      // is expected to be empty — but we assert the level invariant in
      // case future emissions add a legitimate warn (e.g. capability
      // gating).
      for (final e in events) {
        expect(
          e.level.index,
          greaterThanOrEqualTo(BlueyLogLevel.warn.index),
          reason: 'unexpected event below warn at warn-level filter: $e',
        );
      }

      await sub.cancel();
      await bluey.dispose();
    });

    test('multiple subscribers each receive the same events', () async {
      final bluey = Bluey();
      bluey.setLogLevel(BlueyLogLevel.trace);

      final a = <BlueyLogEvent>[];
      final b = <BlueyLogEvent>[];
      final subA = bluey.logEvents.listen(a.add);
      final subB = bluey.logEvents.listen(b.add);

      final device = await scanFirstDevice(bluey);
      final connection = await bluey.connect(device);
      await connection.disconnect();

      await Future<void>.delayed(Duration.zero);

      // Both lists should be non-empty (the connect flow emits at least
      // one info-level event) and equal in content.
      expect(a, isNotEmpty);
      expect(b, isNotEmpty);
      expect(a.map(tag).toList(), equals(b.map(tag).toList()));

      await subA.cancel();
      await subB.cancel();
      await bluey.dispose();
    });
  });
}
