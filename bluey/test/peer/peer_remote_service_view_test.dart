import 'dart:async';

import 'package:bluey/bluey.dart';
import 'package:bluey/src/lifecycle.dart' as lifecycle;
import 'package:bluey/src/peer/peer_remote_service_view.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal RemoteService stub for view-layer tests. The view never calls
/// methods on these services — it only inspects [uuid] — so everything
/// else throws if accidentally exercised.
class _StubRemoteService implements RemoteService {
  _StubRemoteService(this.uuid);

  @override
  final UUID uuid;

  @override
  bool get isPrimary => true;

  @override
  List<RemoteCharacteristic> characteristics({UUID? uuid}) => const [];

  @override
  List<RemoteService> get includedServices => const [];

  @override
  RemoteCharacteristic characteristic(UUID uuid) => throw UnimplementedError();
}

/// Records calls made on the wrapped [Connection] so the view's tests
/// can assert delegation. Same shape as `_SpyConnection` in
/// `peer_connection_test.dart`, scoped to what the view exercises.
class _SpyConnection implements Connection {
  _SpyConnection({UUID? deviceId, List<RemoteService> services = const []})
    : _deviceId = deviceId ?? UUID.short(0xAAAA),
      _services = services;

  final UUID _deviceId;
  final List<RemoteService> _services;

  /// Method-call log in invocation order.
  final List<String> calls = [];

  /// Recorded `cache:` values from each `services()` call.
  final List<bool> servicesCacheArgs = [];

  /// Recorded UUIDs passed to `service()` and `hasService()`.
  final List<UUID> serviceArgs = [];
  final List<UUID> hasServiceArgs = [];

  @override
  UUID get deviceId => _deviceId;

  @override
  Future<List<RemoteService>> services({bool cache = false}) async {
    calls.add('services');
    servicesCacheArgs.add(cache);
    return _services;
  }

  @override
  RemoteService service(UUID uuid) {
    calls.add('service');
    serviceArgs.add(uuid);
    final svc = _services.where((s) => s.uuid == uuid).firstOrNull;
    if (svc == null) throw ServiceNotFoundException(uuid);
    return svc;
  }

  @override
  Future<bool> hasService(UUID uuid) async {
    calls.add('hasService');
    hasServiceArgs.add(uuid);
    return _services.any((s) => s.uuid == uuid);
  }

  @override
  Future<void> disconnect() async => calls.add('disconnect');

  // Members the view never touches — explicitly throw to catch
  // accidental dependence.
  @override
  ConnectionState get state => throw UnimplementedError();
  @override
  Stream<ConnectionState> get stateChanges => throw UnimplementedError();
  @override
  Stream<List<RemoteService>> get servicesChanges => throw UnimplementedError();
  @override
  Future<WritePayloadLimit> maxWritePayload({required bool withResponse}) =>
      throw UnimplementedError();
  @override
  Future<int> readRssi() => throw UnimplementedError();
  @override
  AndroidConnectionExtensions? get android => throw UnimplementedError();
  @override
  IosConnectionExtensions? get ios => throw UnimplementedError();
}

/// Spy variant whose `hasService` is decoupled from its `_services`
/// list — used to verify the view returns false for the control UUID
/// even when the underlying connection would say true.
class _AlwaysTrueHasServiceConnection extends _SpyConnection {
  _AlwaysTrueHasServiceConnection();

  @override
  Future<bool> hasService(UUID uuid) async {
    calls.add('hasService');
    hasServiceArgs.add(uuid);
    return true;
  }
}

void main() {
  // Use the canonical control-service UUID exposed by the lifecycle
  // module. This is the same string `isControlService` matches against,
  // so we know the filter triggers on it.
  final controlServiceUuid = UUID(lifecycle.controlServiceUuid);

  // Two arbitrary user-facing service UUIDs.
  final userUuid1 = UUID.short(0x180D); // heart rate
  final userUuid2 = UUID.short(0x180F); // battery

  group('PeerRemoteServiceView.services()', () {
    test('filters out the control service', () async {
      final controlSvc = _StubRemoteService(controlServiceUuid);
      final user1 = _StubRemoteService(userUuid1);
      final user2 = _StubRemoteService(userUuid2);
      final conn = _SpyConnection(services: [controlSvc, user1, user2]);

      final view = PeerRemoteServiceView(conn);
      final result = await view.services();

      expect(result, hasLength(2));
      expect(result.map((s) => s.uuid), [userUuid1, userUuid2]);
    });

    test('is a pure pass-through when no control service is present', () async {
      final user1 = _StubRemoteService(userUuid1);
      final user2 = _StubRemoteService(userUuid2);
      final conn = _SpyConnection(services: [user1, user2]);

      final view = PeerRemoteServiceView(conn);
      final result = await view.services();

      expect(result.map((s) => s.uuid), [userUuid1, userUuid2]);
    });

    test('forwards the cache flag to the underlying connection', () async {
      final conn = _SpyConnection();
      final view = PeerRemoteServiceView(conn);

      await view.services();
      await view.services(cache: true);

      expect(conn.servicesCacheArgs, equals([false, true]));
    });
  });

  group('PeerRemoteServiceView.service()', () {
    test('throws ServiceNotFoundException for the control-service UUID, '
        'even though the underlying connection has it', () {
      final controlSvc = _StubRemoteService(controlServiceUuid);
      final user1 = _StubRemoteService(userUuid1);
      final conn = _SpyConnection(services: [controlSvc, user1]);

      final view = PeerRemoteServiceView(conn);

      expect(
        () => view.service(controlServiceUuid),
        throwsA(isA<ServiceNotFoundException>()),
      );
      // The view rejects the lookup before delegating, so the spy
      // never sees the call.
      expect(conn.serviceArgs, isEmpty);
    });

    test('delegates to the underlying connection for a user service', () {
      final user1 = _StubRemoteService(userUuid1);
      final conn = _SpyConnection(services: [user1]);

      final view = PeerRemoteServiceView(conn);
      final result = view.service(userUuid1);

      expect(identical(result, user1), isTrue);
      expect(conn.serviceArgs, equals([userUuid1]));
    });
  });

  group('PeerRemoteServiceView.hasService()', () {
    test('returns false for the control-service UUID even though '
        'the underlying connection says true', () async {
      final conn = _AlwaysTrueHasServiceConnection();
      final view = PeerRemoteServiceView(conn);

      final result = await view.hasService(controlServiceUuid);

      expect(result, isFalse);
      // Short-circuited: the view never delegates for the control UUID.
      expect(conn.hasServiceArgs, isEmpty);
    });

    test('delegates to the underlying connection for a user UUID', () async {
      final user1 = _StubRemoteService(userUuid1);
      final conn = _SpyConnection(services: [user1]);

      final view = PeerRemoteServiceView(conn);
      final present = await view.hasService(userUuid1);
      final absent = await view.hasService(userUuid2);

      expect(present, isTrue);
      expect(absent, isFalse);
      expect(conn.hasServiceArgs, equals([userUuid1, userUuid2]));
    });
  });
}
