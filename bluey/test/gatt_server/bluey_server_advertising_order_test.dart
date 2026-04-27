import 'dart:async';

import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';

/// I080 — `BlueyServer.startAdvertising` must not begin advertising
/// while user-added services are still being registered. The platform
/// layer's control-service-ready future is awaited; user services
/// added via `BlueyServer.addService` were not. A central connecting
/// while advertising is live but services aren't ready saw an
/// incomplete GATT tree.
void main() {
  late FakeBlueyPlatform fakePlatform;

  setUp(() {
    fakePlatform = FakeBlueyPlatform();
    platform.BlueyPlatform.instance = fakePlatform;
  });

  group('BlueyServer addService → startAdvertising ordering (I080)', () {
    test(
        'startAdvertising waits for an in-flight addService to complete '
        'even when the user does not await between them', () async {
      final bluey = Bluey();
      final server = bluey.server()!;

      // Hold the next platform addService — the user-added service will
      // be in flight when startAdvertising fires.
      fakePlatform.holdNextAddService();

      final hostedService = HostedService(
        uuid: UUID('12345678-1234-1234-1234-123456789abc'),
        isPrimary: true,
        characteristics: const [],
      );

      // Track completion order.
      final order = <String>[];
      final addFuture = server.addService(hostedService).then(
            (_) => order.add('add'),
          );
      final advertiseFuture = server.startAdvertising().then(
            (_) => order.add('advertise'),
          );

      // Let any synchronous microtasks drain.
      await Future<void>.delayed(Duration.zero);
      expect(
        order,
        isEmpty,
        reason:
            'neither addService nor startAdvertising should have completed '
            'while the platform addService is held',
      );

      // Release the held addService → addFuture completes → startAdvertising
      // (which has been awaiting the in-flight add) completes next.
      fakePlatform.resolveHeldAddService();

      await Future.wait([addFuture, advertiseFuture]);

      expect(
        order,
        equals(['add', 'advertise']),
        reason:
            'startAdvertising must complete after the in-flight addService '
            '(I080); pre-fix the order was reversed because startAdvertising '
            'only awaited the control service, not user-added services',
      );

      bluey.dispose();
    });

    test(
        'startAdvertising with no in-flight addService completes normally '
        '(regression guard)', () async {
      final bluey = Bluey();
      final server = bluey.server()!;

      // Add a service and await it before calling startAdvertising.
      // This is the well-behaved sequential pattern that always worked;
      // the I080 fix must not regress it.
      await server.addService(HostedService(
        uuid: UUID('12345678-1234-1234-1234-123456789abc'),
        isPrimary: true,
        characteristics: const [],
      ));

      await server.startAdvertising();
      expect(server.isAdvertising, isTrue);

      bluey.dispose();
    });
  });
}
