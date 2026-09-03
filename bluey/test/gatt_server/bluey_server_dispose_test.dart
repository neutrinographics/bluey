import 'dart:async';

import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';

/// I368 follow-ups: dispose must finish releasing resources no matter what
/// the adapter or the platform does while it is in flight.
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

  group('BlueyServer dispose resilience', () {
    test('an adapter transition during an in-flight dispose still tears '
        'down the server', () {
      fakeAsync((async) {
        final server = bluey.server()!;
        server.startAdvertising();
        async.flushMicrotasks();
        final connectionsClosed = Completer<void>();
        server.connections.listen((_) {}, onDone: connectionsClosed.complete);
        fakePlatform.operationLatency = const Duration(seconds: 1);

        var disposed = false;
        server.dispose().then((_) => disposed = true);
        async.flushMicrotasks();
        fakePlatform.setState(platform.BluetoothState.off);
        async.flushMicrotasks();
        fakePlatform.operationLatency = null;

        expect(
          connectionsClosed.isCompleted,
          isTrue,
          reason: 'adapter teardown must run even while dispose is awaiting '
              'the platform',
        );

        async.elapse(const Duration(seconds: 1));
        expect(disposed, isTrue, reason: 'dispose still completes');
      });
    });

    test('dispose completes its teardown even when the platform stop and '
        'close fail', () async {
      final server = bluey.server()!;
      await server.startAdvertising();
      final connectionsClosed = Completer<void>();
      server.connections.listen((_) {}, onDone: connectionsClosed.complete);
      fakePlatform.enqueueFault(
        FakeOp.stopAdvertising,
        StateError('fake: adapter gone'),
      );
      fakePlatform.enqueueFault(
        FakeOp.closeServer,
        StateError('fake: adapter gone'),
      );

      await server.dispose();

      expect(connectionsClosed.isCompleted, isTrue);
    });
  });
}
