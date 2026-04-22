import 'dart:typed_data';

import 'package:bluey/src/gatt_server/lifecycle_server.dart';
import 'package:bluey/src/lifecycle.dart' as lifecycle;
import 'package:bluey/src/peer/server_id.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';

// Control service UUIDs (must match lifecycle.dart).
const _heartbeatCharUuid = 'b1e70002-0000-1000-8000-00805f9b34fb';
const _intervalCharUuid = 'b1e70003-0000-1000-8000-00805f9b34fb';
const _otherCharUuid = '12345678-1234-1234-1234-123456789abc';

// Use proper UUID-format IDs so BlueyClient.id passes them through unchanged.
const _clientId = '00000000-0000-0000-0000-000000000001';

PlatformWriteRequest _writeReq({
  required String characteristicUuid,
  required List<int> value,
  String centralId = _clientId,
  int requestId = 1,
  bool responseNeeded = false,
}) {
  return PlatformWriteRequest(
    requestId: requestId,
    centralId: centralId,
    characteristicUuid: characteristicUuid,
    value: Uint8List.fromList(value),
    offset: 0,
    responseNeeded: responseNeeded,
  );
}

PlatformReadRequest _readReq({
  required String characteristicUuid,
  String centralId = _clientId,
  int requestId = 1,
}) {
  return PlatformReadRequest(
    requestId: requestId,
    centralId: centralId,
    characteristicUuid: characteristicUuid,
    offset: 0,
  );
}

void main() {
  late FakeBlueyPlatform fakePlatform;

  setUp(() {
    fakePlatform = FakeBlueyPlatform();
    BlueyPlatform.instance = fakePlatform;
  });

  group('LifecycleServer', () {
    test('handleWriteRequest returns false for non-control characteristics',
        () {
      final gone = <String>[];
      final server = LifecycleServer(
        platformApi: fakePlatform,
        interval: const Duration(seconds: 5),
        serverId: ServerId.generate(),
        onClientGone: gone.add,
      );

      final req = _writeReq(
        characteristicUuid: _otherCharUuid,
        value: [0x01],
      );

      expect(server.handleWriteRequest(req), isFalse);
      expect(gone, isEmpty);

      server.dispose();
    });

    test('handleWriteRequest returns true and resets timer for heartbeat', () {
      fakeAsync((async) {
        final gone = <String>[];
        final server = LifecycleServer(
          platformApi: fakePlatform,
          interval: const Duration(seconds: 5),
          serverId: ServerId.generate(),
          onClientGone: gone.add,
        );

        final handled = server.handleWriteRequest(
          _writeReq(characteristicUuid: _heartbeatCharUuid, value: [0x01]),
        );
        expect(handled, isTrue);

        // Before the timeout elapses: no disconnect.
        async.elapse(const Duration(seconds: 3));
        expect(gone, isEmpty);

        // Total of 5 seconds since the heartbeat — timer fires.
        async.elapse(const Duration(seconds: 2));
        expect(gone, [_clientId]);

        server.dispose();
      });
    });

    test('disconnect command triggers onClientGone immediately', () {
      final gone = <String>[];
      final server = LifecycleServer(
        platformApi: fakePlatform,
        interval: const Duration(seconds: 5),
        serverId: ServerId.generate(),
        onClientGone: gone.add,
      );

      final handled = server.handleWriteRequest(
        _writeReq(characteristicUuid: _heartbeatCharUuid, value: [0x00]),
      );

      expect(handled, isTrue);
      expect(gone, [_clientId]);

      server.dispose();
    });

    test('handleWriteRequest auto-responds when responseNeeded is true', () {
      final server = LifecycleServer(
        platformApi: fakePlatform,
        interval: const Duration(seconds: 5),
        serverId: ServerId.generate(),
        onClientGone: (_) {},
      );

      server.handleWriteRequest(
        _writeReq(
          characteristicUuid: _heartbeatCharUuid,
          value: [0x01],
          requestId: 42,
          responseNeeded: true,
        ),
      );

      expect(fakePlatform.respondWriteCalls, hasLength(1));
      expect(fakePlatform.respondWriteCalls.single.requestId, 42);
      expect(
        fakePlatform.respondWriteCalls.single.status,
        PlatformGattStatus.success,
      );

      server.dispose();
    });

    test('handleWriteRequest does NOT auto-respond when responseNeeded is false',
        () {
      final server = LifecycleServer(
        platformApi: fakePlatform,
        interval: const Duration(seconds: 5),
        serverId: ServerId.generate(),
        onClientGone: (_) {},
      );

      server.handleWriteRequest(
        _writeReq(
          characteristicUuid: _heartbeatCharUuid,
          value: [0x01],
          responseNeeded: false,
        ),
      );

      expect(fakePlatform.respondWriteCalls, isEmpty);

      server.dispose();
    });

    test(
        'handleReadRequest responds with encoded interval for interval characteristic',
        () {
      final server = LifecycleServer(
        platformApi: fakePlatform,
        interval: const Duration(seconds: 15),
        serverId: ServerId.generate(),
        onClientGone: (_) {},
      );

      final handled = server.handleReadRequest(
        _readReq(characteristicUuid: _intervalCharUuid, requestId: 7),
      );

      expect(handled, isTrue);
      expect(fakePlatform.respondReadCalls, hasLength(1));
      final call = fakePlatform.respondReadCalls.single;
      expect(call.requestId, 7);
      expect(call.status, PlatformGattStatus.success);
      expect(
        call.value,
        lifecycle.encodeInterval(const Duration(seconds: 15)),
      );

      server.dispose();
    });

    test('handleReadRequest returns false for non-control characteristics', () {
      final server = LifecycleServer(
        platformApi: fakePlatform,
        interval: const Duration(seconds: 5),
        serverId: ServerId.generate(),
        onClientGone: (_) {},
      );

      final handled = server.handleReadRequest(
        _readReq(characteristicUuid: _otherCharUuid),
      );

      expect(handled, isFalse);
      expect(fakePlatform.respondReadCalls, isEmpty);

      server.dispose();
    });

    test('handleReadRequest uses default interval when interval is null', () {
      final server = LifecycleServer(
        platformApi: fakePlatform,
        interval: null,
        serverId: ServerId.generate(),
        onClientGone: (_) {},
      );

      final handled = server.handleReadRequest(
        _readReq(characteristicUuid: _intervalCharUuid),
      );

      expect(handled, isTrue);
      expect(
        fakePlatform.respondReadCalls.single.value,
        lifecycle.encodeInterval(lifecycle.defaultLifecycleInterval),
      );

      server.dispose();
    });

    test('cancelTimer prevents a pending heartbeat timer from firing', () {
      fakeAsync((async) {
        final gone = <String>[];
        final server = LifecycleServer(
          platformApi: fakePlatform,
          interval: const Duration(seconds: 5),
          serverId: ServerId.generate(),
          onClientGone: gone.add,
        );

        // Start a timer.
        server.handleWriteRequest(
          _writeReq(characteristicUuid: _heartbeatCharUuid, value: [0x01]),
        );

        server.cancelTimer(_clientId);

        async.elapse(const Duration(seconds: 10));
        expect(gone, isEmpty);

        server.dispose();
      });
    });

    test('dispose cancels all timers without firing callbacks', () {
      fakeAsync((async) {
        final gone = <String>[];
        final server = LifecycleServer(
          platformApi: fakePlatform,
          interval: const Duration(seconds: 5),
          serverId: ServerId.generate(),
          onClientGone: gone.add,
        );

        // Start a timer via a heartbeat write.
        server.handleWriteRequest(
          _writeReq(characteristicUuid: _heartbeatCharUuid, value: [0x01]),
        );

        server.dispose();

        // Advance past the timeout.
        async.elapse(const Duration(seconds: 10));

        expect(gone, isEmpty);
      });
    });

    test('onHeartbeatReceived fires on heartbeat writes', () {
      final gone = <String>[];
      final heartbeats = <String>[];
      final server = LifecycleServer(
        platformApi: fakePlatform,
        interval: const Duration(seconds: 5),
        serverId: ServerId.generate(),
        onClientGone: gone.add,
        onHeartbeatReceived: heartbeats.add,
      );

      server.handleWriteRequest(
        _writeReq(characteristicUuid: _heartbeatCharUuid, value: [0x01]),
      );

      expect(heartbeats, [_clientId]);

      server.dispose();
    });

    test(
        'onHeartbeatReceived also fires on disconnect command '
        '(tracks before disconnect)', () {
      final gone = <String>[];
      final heartbeats = <String>[];
      final server = LifecycleServer(
        platformApi: fakePlatform,
        interval: const Duration(seconds: 5),
        serverId: ServerId.generate(),
        onClientGone: gone.add,
        onHeartbeatReceived: heartbeats.add,
      );

      server.handleWriteRequest(
        _writeReq(characteristicUuid: _heartbeatCharUuid, value: [0x00]),
      );

      // Callback fires BEFORE onClientGone so an untracked client still gets
      // tracked before being removed.
      expect(heartbeats, [_clientId]);
      expect(gone, [_clientId]);

      server.dispose();
    });

    test('null interval means no timer is started on heartbeat', () {
      fakeAsync((async) {
        final gone = <String>[];
        final server = LifecycleServer(
          platformApi: fakePlatform,
          interval: null,
          serverId: ServerId.generate(),
          onClientGone: gone.add,
        );

        final handled = server.handleWriteRequest(
          _writeReq(characteristicUuid: _heartbeatCharUuid, value: [0x01]),
        );

        // Write is still handled (returns true) — the control service just
        // isn't enforcing a timeout.
        expect(handled, isTrue);

        async.elapse(const Duration(seconds: 60));
        expect(gone, isEmpty);

        server.dispose();
      });
    });

    test('addControlServiceIfNeeded is a no-op when interval is null', () async {
      final server = LifecycleServer(
        platformApi: fakePlatform,
        interval: null,
        serverId: ServerId.generate(),
        onClientGone: (_) {},
      );

      await server.addControlServiceIfNeeded();

      expect(fakePlatform.localServices, isEmpty);

      server.dispose();
    });

    test('addControlServiceIfNeeded adds the control service exactly once',
        () async {
      final server = LifecycleServer(
        platformApi: fakePlatform,
        interval: const Duration(seconds: 5),
        serverId: ServerId.generate(),
        onClientGone: (_) {},
      );

      await server.addControlServiceIfNeeded();
      await server.addControlServiceIfNeeded();
      await server.addControlServiceIfNeeded();

      expect(fakePlatform.localServices, hasLength(1));
      expect(
        fakePlatform.localServices.single.uuid,
        lifecycle.controlServiceUuid,
      );

      server.dispose();
    });

    test('responds to serverId read with encoded bytes', () {
      final id = ServerId.generate();
      final server = LifecycleServer(
        platformApi: fakePlatform,
        interval: const Duration(seconds: 5),
        serverId: id,
        onClientGone: (_) {},
      );

      final handled = server.handleReadRequest(PlatformReadRequest(
        requestId: 1,
        centralId: 'central-1',
        characteristicUuid: 'b1e70004-0000-1000-8000-00805f9b34fb',
        offset: 0,
      ));
      expect(handled, isTrue);

      expect(fakePlatform.respondReadCalls, hasLength(1));
      final call = fakePlatform.respondReadCalls.single;
      expect(call.status, PlatformGattStatus.success);
      expect(call.value, equals(id.toBytes()));

      server.dispose();
    });

    test('recordActivity resets the per-client timer', () {
      fakeAsync((async) {
        final events = <String>[];
        final server = LifecycleServer(
          platformApi: FakeBlueyPlatform(),
          interval: const Duration(seconds: 10),
          serverId: ServerId.generate(),
          onClientGone: (id) => events.add('gone:$id'),
        );

        const clientId = 'test-client';

        // Prime the server by receiving a heartbeat from the client.
        server.handleWriteRequest(PlatformWriteRequest(
          requestId: 1,
          centralId: clientId,
          characteristicUuid: lifecycle.heartbeatCharUuid,
          value: lifecycle.heartbeatValue,
          responseNeeded: false,
          offset: 0,
        ));

        // Advance 9s — just under the timeout.
        async.elapse(const Duration(seconds: 9));
        expect(events, isEmpty);

        // Record activity (simulates a non-control-service write arriving).
        server.recordActivity(clientId);

        // Advance another 9s — total 18s since first heartbeat, but only
        // 9s since recordActivity, so still within the window.
        async.elapse(const Duration(seconds: 9));
        expect(events, isEmpty, reason: 'recordActivity should reset the timer');

        // Another 2s → past the timer from recordActivity → should fire.
        async.elapse(const Duration(seconds: 2));
        expect(events, equals(['gone:$clientId']));

        server.dispose();
      });
    });

    test('recordActivity is a no-op when lifecycle is disabled (null interval)',
        () {
      final server = LifecycleServer(
        platformApi: FakeBlueyPlatform(),
        interval: null,
        serverId: ServerId.generate(),
        onClientGone: (_) => fail('no client should expire'),
      );

      // Calling recordActivity when lifecycle is disabled should be safe
      // and do nothing.
      expect(() => server.recordActivity('client'), returnsNormally);

      server.dispose();
    });
  });
}
