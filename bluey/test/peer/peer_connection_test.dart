import 'dart:async';

import 'package:bluey/bluey.dart';
import 'package:bluey/src/connection/lifecycle_client.dart';
import 'package:bluey/src/lifecycle.dart' as lifecycle;
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';
import '../fakes/test_helpers.dart';

/// Records calls made on the wrapped [Connection] so tests can assert
/// delegation. Only stubs the methods the C.1 PeerConnection actually
/// invokes; everything else throws [UnimplementedError].
class _SpyConnection implements Connection {
  _SpyConnection({UUID? deviceId, this.servicesResult = const []})
    : _deviceId = deviceId ?? UUID.short(0xAAAA);

  final UUID _deviceId;
  final List<RemoteService> servicesResult;

  /// Ordered list of method names invoked on this stub. The
  /// `sendDisconnectCommand` test inspects this against the lifecycle
  /// stub's call log to verify call order.
  final List<String> calls = [];

  /// Records of (cache: <bool>) for each services() invocation.
  final List<bool> servicesCacheArgs = [];

  /// Records of UUIDs passed to service() / hasService().
  final List<UUID> serviceArgs = [];
  final List<UUID> hasServiceArgs = [];

  @override
  UUID get deviceId => _deviceId;

  @override
  Future<List<RemoteService>> services({bool cache = false}) async {
    calls.add('services');
    servicesCacheArgs.add(cache);
    return servicesResult;
  }

  @override
  RemoteService service(UUID uuid) {
    calls.add('service');
    serviceArgs.add(uuid);
    final svc = servicesResult.where((s) => s.uuid == uuid).firstOrNull;
    if (svc == null) throw ServiceNotFoundException(uuid);
    return svc;
  }

  @override
  Future<bool> hasService(UUID uuid) async {
    calls.add('hasService');
    hasServiceArgs.add(uuid);
    return servicesResult.any((s) => s.uuid == uuid);
  }

  @override
  Future<void> disconnect() async {
    calls.add('disconnect');
  }

  /// Broadcast controller backing [stateChanges]. Tests drive disconnect
  /// scenarios via [simulateState].
  final StreamController<ConnectionState> _stateController =
      StreamController<ConnectionState>.broadcast();

  /// Inject a state event onto [stateChanges] so subscribers fire.
  /// Tests await `pumpEventQueue` after this call.
  void simulateState(ConnectionState s) {
    _stateController.add(s);
  }

  /// Close the controller — call from tearDown to avoid leaked
  /// subscriptions across tests.
  Future<void> dispose() => _stateController.close();

  // Members not exercised by C.1's PeerConnection — explicitly throw to
  // catch accidental dependence.
  @override
  ConnectionState get state => throw UnimplementedError();
  @override
  Stream<ConnectionState> get stateChanges => _stateController.stream;
  @override
  Stream<List<RemoteService>> get servicesChanges => const Stream.empty();
  @override
  Mtu get mtu => throw UnimplementedError();
  @override
  Future<Mtu> requestMtu(Mtu mtu) => throw UnimplementedError();
  @override
  Future<int> readRssi() => throw UnimplementedError();
  @override
  AndroidConnectionExtensions? get android => throw UnimplementedError();
  @override
  IosConnectionExtensions? get ios => throw UnimplementedError();
}

/// LifecycleClient subclass that records `sendDisconnectCommand` calls
/// and shares a call-order log with the spy connection so tests can
/// assert ordering across the two collaborators.
class _SpyLifecycleClient extends LifecycleClient {
  _SpyLifecycleClient({required this.callLog})
    : super(
        platformApi: FakeBlueyPlatform(),
        connectionId: 'spy-connection-id',
        localIdentity: TestServerIds.localIdentity,
        peerSilenceTimeout: const Duration(seconds: 30),
        onServerUnreachable: _noop,
        logger: _spyLogger,
      );

  static final _spyLogger = testLogger();

  /// Shared call-order log. The test passes the spy connection's `calls`
  /// list in so both collaborators record into the same buffer.
  final List<String> callLog;

  static void _noop() {}

  /// Records calls to [stop] so tests can assert teardown.
  bool stopCalled = false;

  @override
  Future<void> sendDisconnectCommand() async {
    callLog.add('lifecycle.sendDisconnectCommand');
  }

  @override
  void stop() {
    stopCalled = true;
    callLog.add('lifecycle.stop');
  }
}

void main() {
  late ServerId serverId;

  setUp(() {
    serverId = ServerId.generate();
  });

  test('PeerConnection.create wraps the given Connection (identity)', () {
    final conn = _SpyConnection();
    final lifecycle = _SpyLifecycleClient(callLog: []);

    final peerConn = PeerConnection.create(
      connection: conn,
      serverId: serverId,
      lifecycleClient: lifecycle,
    );

    expect(identical(peerConn.connection, conn), isTrue);
  });

  test('PeerConnection.serverId returns the constructed value', () {
    final conn = _SpyConnection();
    final lifecycle = _SpyLifecycleClient(callLog: []);

    final peerConn = PeerConnection.create(
      connection: conn,
      serverId: serverId,
      lifecycleClient: lifecycle,
    );

    expect(peerConn.serverId, equals(serverId));
  });

  test(
    'services() / service() / hasService() delegate to wrapped connection',
    () async {
      final conn = _SpyConnection();
      final lifecycle = _SpyLifecycleClient(callLog: []);

      final peerConn = PeerConnection.create(
        connection: conn,
        serverId: serverId,
        lifecycleClient: lifecycle,
      );

      // services()
      await peerConn.services();
      await peerConn.services(cache: true);
      expect(conn.servicesCacheArgs, equals([false, true]));

      // service()
      final lookupUuid = UUID.short(0x1234);
      expect(
        () => peerConn.service(lookupUuid),
        throwsA(isA<ServiceNotFoundException>()),
      );
      expect(conn.serviceArgs, equals([lookupUuid]));

      // hasService()
      final hasResult = await peerConn.hasService(lookupUuid);
      expect(hasResult, isFalse);
      expect(conn.hasServiceArgs, equals([lookupUuid]));
    },
  );

  group(
    'control-service filtering (delegated through PeerRemoteServiceView)',
    () {
      final controlServiceUuid = UUID(lifecycle.controlServiceUuid);
      final userUuid = UUID.short(0x180D);

      test('peer.services() excludes the control service', () async {
        final controlSvc = _StubRemoteService(controlServiceUuid);
        final userSvc = _StubRemoteService(userUuid);
        final conn = _SpyConnection(servicesResult: [controlSvc, userSvc]);
        final lifecycleClient = _SpyLifecycleClient(callLog: []);

        final peerConn = PeerConnection.create(
          connection: conn,
          serverId: serverId,
          lifecycleClient: lifecycleClient,
        );

        final result = await peerConn.services();
        expect(result.map((s) => s.uuid), [userUuid]);
      });

      test('peer.connection.services() returns the FULL tree (raw access '
          'unchanged)', () async {
        final controlSvc = _StubRemoteService(controlServiceUuid);
        final userSvc = _StubRemoteService(userUuid);
        final conn = _SpyConnection(servicesResult: [controlSvc, userSvc]);
        final lifecycleClient = _SpyLifecycleClient(callLog: []);

        final peerConn = PeerConnection.create(
          connection: conn,
          serverId: serverId,
          lifecycleClient: lifecycleClient,
        );

        final raw = await peerConn.connection.services();
        expect(raw.map((s) => s.uuid), [controlServiceUuid, userUuid]);
      });

      test(
        'peer.service(controlServiceUuid) throws ServiceNotFoundException',
        () {
          final controlSvc = _StubRemoteService(controlServiceUuid);
          final userSvc = _StubRemoteService(userUuid);
          final conn = _SpyConnection(servicesResult: [controlSvc, userSvc]);
          final lifecycleClient = _SpyLifecycleClient(callLog: []);

          final peerConn = PeerConnection.create(
            connection: conn,
            serverId: serverId,
            lifecycleClient: lifecycleClient,
          );

          expect(
            () => peerConn.service(controlServiceUuid),
            throwsA(isA<ServiceNotFoundException>()),
          );
        },
      );

      test('peer.hasService(controlServiceUuid) returns false', () async {
        final controlSvc = _StubRemoteService(controlServiceUuid);
        final conn = _SpyConnection(servicesResult: [controlSvc]);
        final lifecycleClient = _SpyLifecycleClient(callLog: []);

        final peerConn = PeerConnection.create(
          connection: conn,
          serverId: serverId,
          lifecycleClient: lifecycleClient,
        );

        expect(await peerConn.hasService(controlServiceUuid), isFalse);
      });

      test('peer.service(userUuid) and peer.hasService(userUuid) delegate '
          'to the underlying connection', () async {
        final userSvc = _StubRemoteService(userUuid);
        final conn = _SpyConnection(servicesResult: [userSvc]);
        final lifecycleClient = _SpyLifecycleClient(callLog: []);

        final peerConn = PeerConnection.create(
          connection: conn,
          serverId: serverId,
          lifecycleClient: lifecycleClient,
        );

        expect(identical(peerConn.service(userUuid), userSvc), isTrue);
        expect(await peerConn.hasService(userUuid), isTrue);
        expect(conn.serviceArgs, equals([userUuid]));
        expect(conn.hasServiceArgs, equals([userUuid]));
      });
    },
  );

  test(
    'disconnect() calls lifecycle.sendDisconnectCommand THEN '
    'connection.disconnect (in order) — peers always go through the '
    'lifecycle protocol; raw escape hatch is peer.connection.disconnect()',
    () async {
      final callLog = <String>[];
      final conn = _SpyConnection();
      final lifecycle = _SpyLifecycleClient(callLog: callLog);

      // Wire the spy connection's disconnect through the same callLog
      // so we can verify ordering across both collaborators.
      final peerConn = PeerConnection.create(
        connection: _OrderingSpyConnection(callLog: callLog),
        serverId: serverId,
        lifecycleClient: lifecycle,
      );

      await peerConn.disconnect();

      expect(
        callLog,
        equals(['lifecycle.sendDisconnectCommand', 'connection.disconnect']),
      );

      // Also verify conn (the unused one) was not touched.
      expect(conn.calls, isEmpty);
    },
  );

  // Regression: when the underlying Connection disconnects (via raw
  // `connection.disconnect()`, supervision timeout, or any other path),
  // the wrapped LifecycleClient must be stopped. Without this, callers
  // that disconnect the raw connection without going through
  // `peer.disconnect()` leak heartbeat traffic for ~30 seconds until
  // the LifecycleClient's own peer-silence timeout fires.
  test(
    'stops LifecycleClient when underlying Connection disconnects',
    () async {
      final conn = _SpyConnection();
      addTearDown(conn.dispose);
      final lifecycle = _SpyLifecycleClient(callLog: []);

      PeerConnection.create(
        connection: conn,
        serverId: serverId,
        lifecycleClient: lifecycle,
      );

      expect(lifecycle.stopCalled, isFalse);

      conn.simulateState(ConnectionState.disconnected);
      await pumpEventQueue();

      expect(
        lifecycle.stopCalled,
        isTrue,
        reason: 'LifecycleClient.stop should fire on connection disconnect',
      );
    },
  );

  test(
    'does NOT stop LifecycleClient on non-disconnected state changes',
    () async {
      final conn = _SpyConnection();
      addTearDown(conn.dispose);
      final lifecycle = _SpyLifecycleClient(callLog: []);

      PeerConnection.create(
        connection: conn,
        serverId: serverId,
        lifecycleClient: lifecycle,
      );

      conn.simulateState(ConnectionState.connecting);
      conn.simulateState(ConnectionState.linked);
      conn.simulateState(ConnectionState.ready);
      conn.simulateState(ConnectionState.disconnecting);
      await pumpEventQueue();

      expect(
        lifecycle.stopCalled,
        isFalse,
        reason: 'Only the disconnected state should trigger stop',
      );
    },
  );
}

/// Minimal RemoteService stub for the control-service filtering tests.
/// Only [uuid] is exercised — the filter inspects nothing else — so the
/// remaining members throw if accidentally touched.
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

/// Minimal connection stub that records 'connection.disconnect' into a
/// shared call-order log. Used only by the order-of-operations test.
class _OrderingSpyConnection implements Connection {
  _OrderingSpyConnection({required this.callLog});

  final List<String> callLog;

  @override
  Future<void> disconnect() async {
    callLog.add('connection.disconnect');
  }

  // Everything else is unused for the ordering test — throw if touched.
  @override
  UUID get deviceId => throw UnimplementedError();
  @override
  ConnectionState get state => throw UnimplementedError();
  @override
  Stream<ConnectionState> get stateChanges => const Stream.empty();
  @override
  Stream<List<RemoteService>> get servicesChanges => const Stream.empty();
  @override
  Mtu get mtu => throw UnimplementedError();
  @override
  RemoteService service(UUID uuid) => throw UnimplementedError();
  @override
  Future<List<RemoteService>> services({bool cache = false}) =>
      throw UnimplementedError();
  @override
  Future<bool> hasService(UUID uuid) => throw UnimplementedError();
  @override
  Future<Mtu> requestMtu(Mtu mtu) => throw UnimplementedError();
  @override
  Future<int> readRssi() => throw UnimplementedError();
  @override
  AndroidConnectionExtensions? get android => throw UnimplementedError();
  @override
  IosConnectionExtensions? get ios => throw UnimplementedError();
}
