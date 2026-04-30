import 'dart:async';
import 'dart:typed_data';

import 'package:bluey/bluey.dart';
import 'package:bluey/src/lifecycle.dart' as lifecycle;
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/test_helpers.dart';

/// Mock platform implementation for testing Server functionality.
final class MockBlueyPlatform extends platform.BlueyPlatform {
  MockBlueyPlatform() : super.impl();
  platform.BluetoothState mockState = platform.BluetoothState.on;

  // Server mock state
  final List<platform.PlatformLocalService> addedServices = [];
  final List<String> removedServiceUuids = [];
  platform.PlatformAdvertiseConfig? lastAdvertiseConfig;
  bool isAdvertising = false;
  final List<NotifyCall> notifyCalls = [];
  final List<NotifyToCall> notifyToCalls = [];
  final List<IndicateCall> indicateCalls = [];
  final List<IndicateToCall> indicateToCalls = [];
  final List<RespondToReadCall> respondToReadCalls = [];
  final List<RespondToWriteCall> respondToWriteCalls = [];

  // I079: when set, the next respondToWriteRequest call throws this error
  // before recording the call. Used to verify that requestCompleted has
  // already drained pending state before the platform call.
  Object? throwOnRespondToWriteRequest;

  // I009: symmetric hook for respondToReadRequest. Set to a throwable to
  // make the next respondToReadRequest fail before recording the call.
  Object? throwOnRespondToReadRequest;

  // Stream controllers for server events
  final _centralConnectionsController =
      StreamController<platform.PlatformCentral>.broadcast();
  final _centralDisconnectionsController = StreamController<String>.broadcast();
  final _readRequestsController =
      StreamController<platform.PlatformReadRequest>.broadcast();
  final _writeRequestsController =
      StreamController<platform.PlatformWriteRequest>.broadcast();

  // Connection state controllers for client operations (stub)
  final _stateController =
      StreamController<platform.BluetoothState>.broadcast();
  final Map<String, StreamController<platform.PlatformConnectionState>>
  _connectionStateControllers = {};

  @override
  platform.Capabilities get capabilities => platform.Capabilities.android;

  @override
  Future<void> configure(platform.BlueyConfig config) async {}

  @override
  Stream<platform.BluetoothState> get stateStream => _stateController.stream;

  @override
  Future<platform.BluetoothState> getState() async => mockState;

  @override
  Future<bool> requestEnable() async => true;

  @override
  Future<bool> authorize() async => true;

  @override
  Future<void> openSettings() async {}

  @override
  Stream<platform.PlatformDevice> scan(platform.PlatformScanConfig config) =>
      Stream.empty();

  @override
  Future<void> stopScan() async {}

  @override
  Future<String> connect(
    String deviceId,
    platform.PlatformConnectConfig config,
  ) async {
    _connectionStateControllers[deviceId] =
        StreamController<platform.PlatformConnectionState>.broadcast();
    return deviceId;
  }

  @override
  Future<void> disconnect(String deviceId) async {
    await _connectionStateControllers[deviceId]?.close();
    _connectionStateControllers.remove(deviceId);
  }

  @override
  Stream<platform.PlatformConnectionState> connectionStateStream(
    String deviceId,
  ) {
    return _connectionStateControllers[deviceId]?.stream ??
        Stream.error(StateError('Not connected'));
  }

  // GATT Client operations - stub implementations
  @override
  Future<List<platform.PlatformService>> discoverServices(
    String deviceId,
  ) async => [];

  @override
  Future<Uint8List> readCharacteristic(
    String deviceId,
    int characteristicHandle,
  ) async => Uint8List(0);

  @override
  Future<void> writeCharacteristic(
    String deviceId,
    int characteristicHandle,
    Uint8List value,
    bool withResponse,
  ) async {}

  @override
  Future<void> setNotification(
    String deviceId,
    int characteristicHandle,
    bool enable,
  ) async {}

  @override
  Stream<platform.PlatformNotification> notificationStream(String deviceId) =>
      Stream.empty();

  @override
  Future<Uint8List> readDescriptor(
    String deviceId,
    int characteristicHandle,
    int descriptorHandle,
  ) async => Uint8List(0);

  @override
  Future<void> writeDescriptor(
    String deviceId,
    int characteristicHandle,
    int descriptorHandle,
    Uint8List value,
  ) async {}

  @override
  Future<int> requestMtu(String deviceId, int mtu) async => mtu;

  @override
  Future<int> readRssi(String deviceId) async => -60;

  // Bonding operations - stub implementations
  @override
  Future<platform.PlatformBondState> getBondState(String deviceId) async =>
      platform.PlatformBondState.none;

  @override
  Stream<platform.PlatformBondState> bondStateStream(String deviceId) =>
      Stream.empty();

  @override
  Future<void> bond(String deviceId) async {}

  @override
  Future<void> removeBond(String deviceId) async {}

  @override
  Future<List<platform.PlatformDevice>> getBondedDevices() async => [];

  // PHY operations - stub implementations
  @override
  Future<({platform.PlatformPhy tx, platform.PlatformPhy rx})> getPhy(
    String deviceId,
  ) async => (tx: platform.PlatformPhy.le1m, rx: platform.PlatformPhy.le1m);

  @override
  Stream<({platform.PlatformPhy tx, platform.PlatformPhy rx})> phyStream(
    String deviceId,
  ) => Stream.empty();

  @override
  Future<void> requestPhy(
    String deviceId,
    platform.PlatformPhy? txPhy,
    platform.PlatformPhy? rxPhy,
  ) async {}

  // Connection parameters - stub implementations
  @override
  Future<platform.PlatformConnectionParameters> getConnectionParameters(
    String deviceId,
  ) async => const platform.PlatformConnectionParameters(
    intervalMs: 30.0,
    latency: 0,
    timeoutMs: 4000,
  );

  @override
  Future<void> requestConnectionParameters(
    String deviceId,
    platform.PlatformConnectionParameters params,
  ) async {}

  // === Server (Peripheral) Operations ===

  @override
  Future<platform.PlatformLocalService> addService(
    platform.PlatformLocalService service,
  ) async {
    final populated = _populateLocalHandles(service);
    addedServices.add(populated);
    return populated;
  }

  // Mints handles for every characteristic / descriptor in [service]
  // so consumers (BlueyServer's UUID->handle resolver) can address
  // them. Mirrors the production native side.
  int _nextLocalHandle = 1;
  final Map<String, int> localHandleByCharUuid = {};

  platform.PlatformLocalService _populateLocalHandles(
    platform.PlatformLocalService s,
  ) {
    final populatedChars = <platform.PlatformLocalCharacteristic>[];
    for (final c in s.characteristics) {
      final h = _nextLocalHandle++;
      localHandleByCharUuid[c.uuid.toLowerCase()] = h;
      var nextDesc = 1;
      final populatedDescs = c.descriptors
          .map((d) => platform.PlatformLocalDescriptor(
                uuid: d.uuid,
                permissions: d.permissions,
                value: d.value,
                handle: nextDesc++,
              ))
          .toList();
      populatedChars.add(platform.PlatformLocalCharacteristic(
        uuid: c.uuid,
        properties: c.properties,
        permissions: c.permissions,
        descriptors: populatedDescs,
        handle: h,
      ));
    }
    return platform.PlatformLocalService(
      uuid: s.uuid,
      isPrimary: s.isPrimary,
      characteristics: populatedChars,
      includedServices: s.includedServices.map(_populateLocalHandles).toList(),
    );
  }

  String _localUuidForHandle(int handle) {
    for (final entry in localHandleByCharUuid.entries) {
      if (entry.value == handle) return entry.key;
    }
    return '';
  }

  @override
  Future<void> removeService(String serviceUuid) async {
    removedServiceUuids.add(serviceUuid);
  }

  @override
  Future<void> startAdvertising(platform.PlatformAdvertiseConfig config) async {
    lastAdvertiseConfig = config;
    isAdvertising = true;
  }

  @override
  Future<void> stopAdvertising() async {
    isAdvertising = false;
  }

  @override
  Future<void> notifyCharacteristic(
    int characteristicHandle,
    Uint8List value,
  ) async {
    notifyCalls.add(
      NotifyCall(
        characteristicUuid: _localUuidForHandle(characteristicHandle),
        value: value,
      ),
    );
  }

  @override
  Future<void> notifyCharacteristicTo(
    String centralId,
    int characteristicHandle,
    Uint8List value,
  ) async {
    notifyToCalls.add(
      NotifyToCall(
        centralId: centralId,
        characteristicUuid: _localUuidForHandle(characteristicHandle),
        value: value,
      ),
    );
  }

  @override
  Future<void> indicateCharacteristic(
    int characteristicHandle,
    Uint8List value,
  ) async {
    indicateCalls.add(
      IndicateCall(
        characteristicUuid: _localUuidForHandle(characteristicHandle),
        value: value,
      ),
    );
  }

  @override
  Future<void> indicateCharacteristicTo(
    String centralId,
    int characteristicHandle,
    Uint8List value,
  ) async {
    indicateToCalls.add(
      IndicateToCall(
        centralId: centralId,
        characteristicUuid: _localUuidForHandle(characteristicHandle),
        value: value,
      ),
    );
  }

  @override
  @override
  Stream<String> get serviceChanges => Stream.empty();

  @override
  Stream<platform.PlatformCentral> get centralConnections =>
      _centralConnectionsController.stream;

  @override
  Stream<String> get centralDisconnections =>
      _centralDisconnectionsController.stream;

  @override
  Stream<platform.PlatformReadRequest> get readRequests =>
      _readRequestsController.stream;

  @override
  Stream<platform.PlatformWriteRequest> get writeRequests =>
      _writeRequestsController.stream;

  @override
  Future<void> respondToReadRequest(
    int requestId,
    platform.PlatformGattStatus status,
    Uint8List? value,
  ) async {
    final err = throwOnRespondToReadRequest;
    if (err != null) {
      throwOnRespondToReadRequest = null;
      throw err;
    }
    respondToReadCalls.add(
      RespondToReadCall(requestId: requestId, status: status, value: value),
    );
  }

  @override
  Future<void> respondToWriteRequest(
    int requestId,
    platform.PlatformGattStatus status,
  ) async {
    final err = throwOnRespondToWriteRequest;
    if (err != null) {
      throwOnRespondToWriteRequest = null;
      throw err;
    }
    respondToWriteCalls.add(
      RespondToWriteCall(requestId: requestId, status: status),
    );
  }

  @override
  Future<void> closeServer() async {
    // Mock implementation - nothing to do
  }

  // Structured logging - stub implementations (I307)
  @override
  Stream<platform.PlatformLogEvent> get logEvents => Stream.empty();

  @override
  Future<void> setLogLevel(platform.PlatformLogLevel level) async {}

  // Test helpers
  void emitCentralConnected(platform.PlatformCentral central) {
    _centralConnectionsController.add(central);
  }

  void emitCentralDisconnected(String centralId) {
    _centralDisconnectionsController.add(centralId);
  }

  void emitReadRequest(platform.PlatformReadRequest request) {
    _readRequestsController.add(request);
  }

  void emitWriteRequest(platform.PlatformWriteRequest request) {
    _writeRequestsController.add(request);
  }

  void dispose() {
    _stateController.close();
    _centralConnectionsController.close();
    _centralDisconnectionsController.close();
    _readRequestsController.close();
    _writeRequestsController.close();
    for (final controller in _connectionStateControllers.values) {
      controller.close();
    }
  }
}

// Helper classes for tracking calls
class NotifyCall {
  final String characteristicUuid;
  final Uint8List value;

  NotifyCall({required this.characteristicUuid, required this.value});
}

class NotifyToCall {
  final String centralId;
  final String characteristicUuid;
  final Uint8List value;

  NotifyToCall({
    required this.centralId,
    required this.characteristicUuid,
    required this.value,
  });
}

class IndicateCall {
  final String characteristicUuid;
  final Uint8List value;

  IndicateCall({required this.characteristicUuid, required this.value});
}

class IndicateToCall {
  final String centralId;
  final String characteristicUuid;
  final Uint8List value;

  IndicateToCall({
    required this.centralId,
    required this.characteristicUuid,
    required this.value,
  });
}

class RespondToReadCall {
  final int requestId;
  final platform.PlatformGattStatus status;
  final Uint8List? value;

  RespondToReadCall({
    required this.requestId,
    required this.status,
    this.value,
  });
}

class RespondToWriteCall {
  final int requestId;
  final platform.PlatformGattStatus status;

  RespondToWriteCall({required this.requestId, required this.status});
}

void main() {
  late MockBlueyPlatform mockPlatform;
  late Bluey bluey;

  setUp(() {
    mockPlatform = MockBlueyPlatform();
    platform.BlueyPlatform.instance = mockPlatform;
    bluey = Bluey();
  });

  tearDown(() async {
    await bluey.dispose();
    mockPlatform.dispose();
  });

  group('BlueyServer', () {
    group('Creation', () {
      test('server() returns a Server instance when platform supports it', () {
        final server = bluey.server();
        expect(server, isNotNull);
        expect(server, isA<Server>());
      });

      test(
        'server() returns null when platform does not support advertising',
        () async {
          // Create a new instance with non-advertising platform
          final nonAdvertisingPlatform = _NonAdvertisingPlatform();
          platform.BlueyPlatform.instance = nonAdvertisingPlatform;
          final bluey2 = Bluey();

          final server = bluey2.server();
          expect(server, isNull);

          await bluey2.dispose();
        },
      );
    });

    group('Service Management', () {
      test('addService adds service to platform', () async {
        final server = bluey.server()!;

        final service = HostedService(
          uuid: UUID.short(0x180F),
          characteristics: [
            HostedCharacteristic.readable(uuid: UUID.short(0x2A19)),
          ],
        );

        server.addService(service);

        // Give time for async operation
        await Future.delayed(Duration.zero);

        // +1 for the auto-registered lifecycle control service
        expect(mockPlatform.addedServices, hasLength(2));
        expect(
          mockPlatform.addedServices.last.uuid,
          equals('0000180f-0000-1000-8000-00805f9b34fb'),
        );
      });

      test('removeService removes service from platform', () async {
        final server = bluey.server()!;
        final uuid = UUID.short(0x180F);

        server.removeService(uuid);

        await Future.delayed(Duration.zero);

        expect(mockPlatform.removedServiceUuids, hasLength(1));
        expect(
          mockPlatform.removedServiceUuids.first,
          equals('0000180f-0000-1000-8000-00805f9b34fb'),
        );
      });
    });

    group('Advertising', () {
      test('startAdvertising starts advertising with name', () async {
        final server = bluey.server()!;

        await server.startAdvertising(name: 'Test Device');

        expect(mockPlatform.isAdvertising, isTrue);
        expect(mockPlatform.lastAdvertiseConfig?.name, equals('Test Device'));
        expect(server.isAdvertising, isTrue);
      });

      test('startAdvertising includes service UUIDs', () async {
        final server = bluey.server()!;

        await server.startAdvertising(
          services: [UUID.short(0x180F), UUID.short(0x180D)],
        );

        // 2 app services only (control service no longer advertised)
        expect(mockPlatform.lastAdvertiseConfig?.serviceUuids, hasLength(2));
        expect(
          mockPlatform.lastAdvertiseConfig?.serviceUuids,
          contains('0000180f-0000-1000-8000-00805f9b34fb'),
        );
        expect(
          mockPlatform.lastAdvertiseConfig?.serviceUuids,
          contains('0000180d-0000-1000-8000-00805f9b34fb'),
        );
        // No manufacturer data when app doesn't provide any
        expect(
          mockPlatform.lastAdvertiseConfig?.manufacturerDataCompanyId,
          isNull,
        );
      });

      test('startAdvertising includes manufacturer data', () async {
        final server = bluey.server()!;

        await server.startAdvertising(
          manufacturerData: ManufacturerData(
            0x004C,
            Uint8List.fromList([1, 2, 3]),
          ),
        );

        // App-provided manufacturer data takes priority over Bluey marker
        expect(
          mockPlatform.lastAdvertiseConfig?.manufacturerDataCompanyId,
          equals(0x004C),
        );
        expect(
          mockPlatform.lastAdvertiseConfig?.manufacturerData,
          equals(Uint8List.fromList([1, 2, 3])),
        );
      });

      test('startAdvertising does not set manufacturer data when none provided',
          () async {
        final server = bluey.server()!;

        await server.startAdvertising(name: 'Test Device');

        expect(
          mockPlatform.lastAdvertiseConfig?.manufacturerDataCompanyId,
          isNull,
        );
        expect(
          mockPlatform.lastAdvertiseConfig?.manufacturerData,
          isNull,
        );
      });

      test('stopAdvertising stops advertising', () async {
        final server = bluey.server()!;

        await server.startAdvertising(name: 'Test');
        expect(server.isAdvertising, isTrue);

        await server.stopAdvertising();
        expect(server.isAdvertising, isFalse);
        expect(mockPlatform.isAdvertising, isFalse);
      });
    });

    group('Central Connections', () {
      test('connections stream emits when central connects', () async {
        final server = bluey.server()!;

        final centrals = <Client>[];
        final subscription = server.connections.listen(centrals.add);

        mockPlatform.emitCentralConnected(
          const platform.PlatformCentral(id: 'central-1', mtu: 512),
        );

        await Future.delayed(Duration(milliseconds: 10));
        await subscription.cancel();

        expect(centrals, hasLength(1));
        // The ID is converted from platform string to UUID
        expect(centrals.first.id, isA<UUID>());
        expect(centrals.first.mtu, equals(512));
      });

      test('connectedClients returns list of connected centrals', () async {
        final server = bluey.server()!;

        // Listen to keep track of connections
        server.connections.listen((_) {});

        mockPlatform.emitCentralConnected(
          const platform.PlatformCentral(id: 'central-1', mtu: 512),
        );
        mockPlatform.emitCentralConnected(
          const platform.PlatformCentral(id: 'central-2', mtu: 256),
        );

        await Future.delayed(Duration(milliseconds: 10));

        expect(server.connectedClients, hasLength(2));
      });

      test('central is removed from list when disconnected', () async {
        final server = bluey.server()!;

        server.connections.listen((_) {});

        mockPlatform.emitCentralConnected(
          const platform.PlatformCentral(id: 'central-1', mtu: 512),
        );
        await Future.delayed(Duration(milliseconds: 10));

        expect(server.connectedClients, hasLength(1));

        mockPlatform.emitCentralDisconnected('central-1');
        await Future.delayed(Duration(milliseconds: 10));

        expect(server.connectedClients, isEmpty);
      });
    });

    group('Peer Identification', () {
      // The server emits a PeerClient on `peerConnections` the first
      // time a connected central sends a lifecycle heartbeat write —
      // signaling "this central speaks the Bluey protocol."
      // Symmetric with the connection-side `tryUpgrade` path.

      test('peerConnections emits when central first sends a heartbeat',
          () async {
        final server = bluey.server()!;

        final peers = <PeerClient>[];
        final sub = server.peerConnections.listen(peers.add);
        addTearDown(sub.cancel);

        mockPlatform.emitCentralConnected(
          const platform.PlatformCentral(id: 'central-1', mtu: 247),
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));

        // Connection alone doesn't identify as peer.
        expect(peers, isEmpty);

        mockPlatform.emitWriteRequest(
          platform.PlatformWriteRequest(
            requestId: 1,
            centralId: 'central-1',
            characteristicUuid: lifecycle.heartbeatCharUuid,
            value: lifecycle.heartbeatValue,
            offset: 0,
            responseNeeded: false,
            characteristicHandle: 0,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(peers, hasLength(1),
            reason: 'first heartbeat from a central should produce '
                'one PeerClient emission');
        expect(peers.single.client.mtu, equals(247));
      });

      test('peerConnections does NOT re-emit on subsequent heartbeats',
          () async {
        final server = bluey.server()!;

        final peers = <PeerClient>[];
        final sub = server.peerConnections.listen(peers.add);
        addTearDown(sub.cancel);

        mockPlatform.emitCentralConnected(
          const platform.PlatformCentral(id: 'central-1', mtu: 247),
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));

        for (var i = 0; i < 5; i++) {
          mockPlatform.emitWriteRequest(
            platform.PlatformWriteRequest(
              requestId: i,
              centralId: 'central-1',
              characteristicUuid: lifecycle.heartbeatCharUuid,
              value: lifecycle.heartbeatValue,
              offset: 0,
              responseNeeded: false,
              characteristicHandle: 0,
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }

        expect(peers, hasLength(1),
            reason: 'identification fires once per identification, '
                'not per heartbeat');
      });

      test('peerConnections does NOT emit for non-Bluey centrals',
          () async {
        final server = bluey.server()!;

        final peers = <PeerClient>[];
        final sub = server.peerConnections.listen(peers.add);
        addTearDown(sub.cancel);

        mockPlatform.emitCentralConnected(
          const platform.PlatformCentral(id: 'raw-central', mtu: 247),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(peers, isEmpty,
            reason: 'a central that never heartbeats is not a peer');
      });

      test('peerConnections re-emits on reconnect after disconnect',
          () async {
        final server = bluey.server()!;

        final peers = <PeerClient>[];
        final sub = server.peerConnections.listen(peers.add);
        addTearDown(sub.cancel);

        // First session.
        mockPlatform.emitCentralConnected(
          const platform.PlatformCentral(id: 'central-1', mtu: 247),
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));
        mockPlatform.emitWriteRequest(
          platform.PlatformWriteRequest(
            requestId: 1,
            centralId: 'central-1',
            characteristicUuid: lifecycle.heartbeatCharUuid,
            value: lifecycle.heartbeatValue,
            offset: 0,
            responseNeeded: false,
            characteristicHandle: 0,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(peers, hasLength(1));

        mockPlatform.emitCentralDisconnected('central-1');
        await Future<void>.delayed(const Duration(milliseconds: 10));

        // Reconnect + heartbeat — fresh identification expected.
        mockPlatform.emitCentralConnected(
          const platform.PlatformCentral(id: 'central-1', mtu: 247),
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));
        mockPlatform.emitWriteRequest(
          platform.PlatformWriteRequest(
            requestId: 2,
            centralId: 'central-1',
            characteristicUuid: lifecycle.heartbeatCharUuid,
            value: lifecycle.heartbeatValue,
            offset: 0,
            responseNeeded: false,
            characteristicHandle: 0,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(peers, hasLength(2),
            reason: 'reconnect-then-heartbeat re-identifies the peer');
      });

      test('peerConnections is a broadcast stream', () async {
        final server = bluey.server()!;

        final a = <PeerClient>[];
        final b = <PeerClient>[];
        final subA = server.peerConnections.listen(a.add);
        final subB = server.peerConnections.listen(b.add);
        addTearDown(() async {
          await subA.cancel();
          await subB.cancel();
        });

        mockPlatform.emitCentralConnected(
          const platform.PlatformCentral(id: 'central-1', mtu: 247),
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));
        mockPlatform.emitWriteRequest(
          platform.PlatformWriteRequest(
            requestId: 1,
            centralId: 'central-1',
            characteristicUuid: lifecycle.heartbeatCharUuid,
            value: lifecycle.heartbeatValue,
            offset: 0,
            responseNeeded: false,
            characteristicHandle: 0,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(a, hasLength(1));
        expect(b, hasLength(1));
      });
    });

    group('Notifications', () {
      // BlueyServer post-D.13 resolves UUID -> handle from the
      // populated PlatformLocalService returned by addService. Each
      // test in this group registers a service hosting char 0x2A19
      // first so the resolver has a handle to forward.
      Future<void> registerNotifiableChar(Server server) async {
        await server.addService(
          HostedService(
            uuid: UUID.short(0x180D),
            characteristics: [
              HostedCharacteristic.notifiable(uuid: UUID.short(0x2A19)),
            ],
          ),
        );
      }

      test('notify sends to all subscribed centrals', () async {
        final server = bluey.server()!;
        await registerNotifiableChar(server);
        final charUuid = UUID.short(0x2A19);
        final data = Uint8List.fromList([42]);

        await server.notify(charUuid, data: data);

        expect(mockPlatform.notifyCalls, hasLength(1));
        expect(
          mockPlatform.notifyCalls.first.characteristicUuid,
          equals('00002a19-0000-1000-8000-00805f9b34fb'),
        );
        expect(mockPlatform.notifyCalls.first.value, equals(data));
      });

      test('notifyTo sends to specific central', () async {
        final server = bluey.server()!;
        await registerNotifiableChar(server);

        // First connect a central
        server.connections.listen((_) {});
        mockPlatform.emitCentralConnected(
          const platform.PlatformCentral(id: 'central-1', mtu: 512),
        );
        await Future.delayed(Duration(milliseconds: 10));

        final central = server.connectedClients.first;
        final charUuid = UUID.short(0x2A19);
        final data = Uint8List.fromList([99]);

        await server.notifyTo(central, charUuid, data: data);

        expect(mockPlatform.notifyToCalls, hasLength(1));
        expect(mockPlatform.notifyToCalls.first.centralId, equals('central-1'));
        expect(mockPlatform.notifyToCalls.first.value, equals(data));
      });
    });

    group('Indications', () {
      Future<void> registerIndicatableChar(Server server) async {
        await server.addService(
          HostedService(
            uuid: UUID.short(0x180D),
            characteristics: [
              HostedCharacteristic(
                uuid: UUID.short(0x2A19),
                properties: const CharacteristicProperties(
                  canRead: false,
                  canWrite: false,
                  canWriteWithoutResponse: false,
                  canNotify: false,
                  canIndicate: true,
                ),
                permissions: const [],
              ),
            ],
          ),
        );
      }

      test('indicate sends indication to all subscribed centrals', () async {
        final server = bluey.server()!;
        await registerIndicatableChar(server);
        final charUuid = UUID.short(0x2A19);
        final data = Uint8List.fromList([42]);

        await server.indicate(charUuid, data: data);

        expect(mockPlatform.indicateCalls, hasLength(1));
        expect(
          mockPlatform.indicateCalls.first.characteristicUuid,
          equals('00002a19-0000-1000-8000-00805f9b34fb'),
        );
        expect(mockPlatform.indicateCalls.first.value, equals(data));
      });

      test('indicateTo sends indication to specific central', () async {
        final server = bluey.server()!;
        await registerIndicatableChar(server);

        // First connect a central
        server.connections.listen((_) {});
        mockPlatform.emitCentralConnected(
          const platform.PlatformCentral(id: 'central-1', mtu: 512),
        );
        await Future.delayed(Duration(milliseconds: 10));

        final central = server.connectedClients.first;
        final charUuid = UUID.short(0x2A19);
        final data = Uint8List.fromList([99]);

        await server.indicateTo(central, charUuid, data: data);

        expect(mockPlatform.indicateToCalls, hasLength(1));
        expect(
          mockPlatform.indicateToCalls.first.centralId,
          equals('central-1'),
        );
        expect(mockPlatform.indicateToCalls.first.value, equals(data));
      });
    });

    group('Dispose', () {
      test('dispose cleans up resources', () async {
        final server = bluey.server()!;

        await server.startAdvertising(name: 'Test');
        await server.dispose();

        // Should have stopped advertising
        expect(mockPlatform.isAdvertising, isFalse);
      });
    });

    group('Read Requests', () {
      test('readRequests stream emits domain ReadRequest', () async {
        final server = bluey.server()!;

        // First connect a central
        server.connections.listen((_) {});
        mockPlatform.emitCentralConnected(
          const platform.PlatformCentral(id: 'central-1', mtu: 512),
        );
        await Future.delayed(Duration(milliseconds: 10));

        final requests = <ReadRequest>[];
        final subscription = server.readRequests.listen(requests.add);

        mockPlatform.emitReadRequest(
          const platform.PlatformReadRequest(
            requestId: 1,
            centralId: 'central-1',
            characteristicUuid: '00002a19-0000-1000-8000-00805f9b34fb',
            offset: 0,
            characteristicHandle: 0,
          ),
        );

        await Future.delayed(Duration(milliseconds: 10));
        await subscription.cancel();

        expect(requests, hasLength(1));
        expect(requests.first.client, isNotNull);
        expect(requests.first.characteristicId, equals(UUID.short(0x2A19)));
        expect(requests.first.offset, equals(0));
      });

      test('respondToRead sends response through platform', () async {
        final server = bluey.server()!;

        // Connect a central and receive a read request
        server.connections.listen((_) {});
        mockPlatform.emitCentralConnected(
          const platform.PlatformCentral(id: 'central-1', mtu: 512),
        );
        await Future.delayed(Duration(milliseconds: 10));

        late ReadRequest capturedRequest;
        server.readRequests.listen((r) => capturedRequest = r);

        mockPlatform.emitReadRequest(
          const platform.PlatformReadRequest(
            requestId: 42,
            centralId: 'central-1',
            characteristicUuid: '00002a19-0000-1000-8000-00805f9b34fb',
            offset: 0,
            characteristicHandle: 0,
          ),
        );
        await Future.delayed(Duration(milliseconds: 10));

        final responseData = Uint8List.fromList([100]);
        await server.respondToRead(
          capturedRequest,
          status: GattResponseStatus.success,
          value: responseData,
        );

        expect(mockPlatform.respondToReadCalls, hasLength(1));
        expect(mockPlatform.respondToReadCalls.first.requestId, equals(42));
        expect(
          mockPlatform.respondToReadCalls.first.status,
          equals(platform.PlatformGattStatus.success),
        );
        expect(
          mockPlatform.respondToReadCalls.first.value,
          equals(responseData),
        );
      });
    });

    group('Write Requests', () {
      test('writeRequests stream emits domain WriteRequest', () async {
        final server = bluey.server()!;

        // First connect a central
        server.connections.listen((_) {});
        mockPlatform.emitCentralConnected(
          const platform.PlatformCentral(id: 'central-1', mtu: 512),
        );
        await Future.delayed(Duration(milliseconds: 10));

        final requests = <WriteRequest>[];
        final subscription = server.writeRequests.listen(requests.add);

        final writeValue = Uint8List.fromList([1, 2, 3]);
        mockPlatform.emitWriteRequest(
          platform.PlatformWriteRequest(
            requestId: 2,
            centralId: 'central-1',
            characteristicUuid: '00002a19-0000-1000-8000-00805f9b34fb',
            value: writeValue,
            offset: 0,
            responseNeeded: true,
            characteristicHandle: 0,
          ),
        );

        await Future.delayed(Duration(milliseconds: 10));
        await subscription.cancel();

        expect(requests, hasLength(1));
        expect(requests.first.client, isNotNull);
        expect(requests.first.characteristicId, equals(UUID.short(0x2A19)));
        expect(requests.first.value, equals(writeValue));
        expect(requests.first.offset, equals(0));
        expect(requests.first.responseNeeded, isTrue);
      });

      test('respondToWrite sends response through platform', () async {
        final server = bluey.server()!;

        // Connect a central and receive a write request
        server.connections.listen((_) {});
        mockPlatform.emitCentralConnected(
          const platform.PlatformCentral(id: 'central-1', mtu: 512),
        );
        await Future.delayed(Duration(milliseconds: 10));

        late WriteRequest capturedRequest;
        server.writeRequests.listen((r) => capturedRequest = r);

        mockPlatform.emitWriteRequest(
          platform.PlatformWriteRequest(
            requestId: 99,
            centralId: 'central-1',
            characteristicUuid: '00002a19-0000-1000-8000-00805f9b34fb',
            value: Uint8List.fromList([5]),
            offset: 0,
            responseNeeded: true,
            characteristicHandle: 0,
          ),
        );
        await Future.delayed(Duration(milliseconds: 10));

        await server.respondToWrite(
          capturedRequest,
          status: GattResponseStatus.success,
        );

        expect(mockPlatform.respondToWriteCalls, hasLength(1));
        expect(mockPlatform.respondToWriteCalls.first.requestId, equals(99));
        expect(
          mockPlatform.respondToWriteCalls.first.status,
          equals(platform.PlatformGattStatus.success),
        );
      });
    });

    group('Lifecycle activity on non-control-service requests', () {
      test(
        'incoming write-without-response to a non-control-service char resets client liveness timer',
        () {
          fakeAsync((async) {
            final server = bluey.server(
              lifecycleInterval: const Duration(seconds: 10),
            )!;

            final userCharUuid = TestUuids.customChar1;

            server.addService(
              HostedService(
                uuid: UUID(TestUuids.customService),
                isPrimary: true,
                characteristics: [
                  HostedCharacteristic(
                    uuid: UUID(userCharUuid),
                    properties: const CharacteristicProperties(canWrite: true),
                    permissions: const [GattPermission.write],
                    descriptors: const [],
                  ),
                ],
              ),
            );
            async.flushMicrotasks();

            final disconnections = <String>[];
            server.disconnections.listen(disconnections.add);

            // Prime: send a heartbeat from client-1 to start the liveness timer.
            mockPlatform.emitWriteRequest(
              platform.PlatformWriteRequest(
                requestId: 1,
                centralId: 'client-1',
                characteristicUuid: lifecycle.heartbeatCharUuid,
                value: lifecycle.heartbeatValue,
                offset: 0,
                responseNeeded: false,
                characteristicHandle: 0,
              ),
            );
            async.flushMicrotasks();

            // Advance 9s — under the 10s timeout.
            async.elapse(const Duration(seconds: 9));
            expect(disconnections, isEmpty);

            // Send a write-without-response to the user service — should reset
            // the timer via recordActivity even though it's not a control-service
            // write.
            mockPlatform.emitWriteRequest(
              platform.PlatformWriteRequest(
                requestId: 2,
                centralId: 'client-1',
                characteristicUuid: userCharUuid,
                value: Uint8List.fromList([0x99]),
                offset: 0,
                responseNeeded: false,
                characteristicHandle: 0,
              ),
            );
            async.flushMicrotasks();

            // Advance another 9s — total 18s since the heartbeat, but only
            // 9s since the user write — still within window.
            async.elapse(const Duration(seconds: 9));
            expect(
              disconnections,
              isEmpty,
              reason:
                  'write-without-response to non-control-service char should reset the liveness timer',
            );

            // 2s more → past the 10s window from the user write → should fire.
            async.elapse(const Duration(seconds: 2));
            expect(disconnections, equals(['client-1']));

            server.dispose();
          });
        },
      );
    });

    group('I079 — pending-request tolerance', () {
      test(
        'I079 — does not declare client gone while holding a pending '
        'write-with-response',
        () {
          fakeAsync((async) {
            final server = bluey.server(
              lifecycleInterval: const Duration(seconds: 10),
            )!;

            final disconnections = <String>[];
            server.disconnections.listen(disconnections.add);

            // 1. Track the client by simulating a heartbeat write arrival.
            mockPlatform.emitWriteRequest(platform.PlatformWriteRequest(
              requestId: 1,
              centralId: 'client-A',
              characteristicUuid: lifecycle.heartbeatCharUuid,
              value: lifecycle.heartbeatValue,
              responseNeeded: false,
              offset: 0,
              characteristicHandle: 0,
            ));
            async.flushMicrotasks();

            // 2. Simulate an app-level write-with-response arriving.
            WriteRequest? captured;
            server.writeRequests.listen((r) => captured = r);
            mockPlatform.emitWriteRequest(platform.PlatformWriteRequest(
              requestId: 99,
              centralId: 'client-A',
              characteristicUuid: '12345678-1234-1234-1234-123456789abc',
              value: Uint8List.fromList([0xAB]),
              responseNeeded: true,
              offset: 0,
              characteristicHandle: 0,
            ));
            async.flushMicrotasks();
            expect(captured, isNotNull);

            // 3. App takes 30s to respond. Heartbeat-timeout would normally
            //    fire at 10s — verify it does NOT.
            async.elapse(const Duration(seconds: 30));
            expect(disconnections, isEmpty,
                reason: 'I079: server must tolerate its own pending response');

            // 4. App finally responds.
            unawaited(server.respondToWrite(
              captured!,
              status: GattResponseStatus.success,
            ));
            async.flushMicrotasks();

            // 5. After response, the heartbeat clock restarts. 11s later,
            //    no further activity, client times out normally.
            async.elapse(const Duration(seconds: 11));
            expect(disconnections, ['client-A']);

            server.dispose();
          });
        },
      );

      test(
        'I079 — read request enters pending set, drains on respondToRead',
        () {
          fakeAsync((async) {
            final server = bluey.server(
              lifecycleInterval: const Duration(seconds: 10),
            )!;

            final disconnections = <String>[];
            server.disconnections.listen(disconnections.add);

            mockPlatform.emitWriteRequest(platform.PlatformWriteRequest(
              requestId: 1,
              centralId: 'client-A',
              characteristicUuid: lifecycle.heartbeatCharUuid,
              value: lifecycle.heartbeatValue,
              responseNeeded: false,
              offset: 0,
              characteristicHandle: 0,
            ));
            async.flushMicrotasks();

            ReadRequest? captured;
            server.readRequests.listen((r) => captured = r);
            mockPlatform.emitReadRequest(platform.PlatformReadRequest(
              requestId: 77,
              centralId: 'client-A',
              characteristicUuid: '12345678-1234-1234-1234-123456789abc',
              offset: 0,
              characteristicHandle: 0,
            ));
            async.flushMicrotasks();
            expect(captured, isNotNull);

            // Server holds the read for 30s — must not declare gone.
            async.elapse(const Duration(seconds: 30));
            expect(disconnections, isEmpty);

            unawaited(server.respondToRead(
              captured!,
              status: GattResponseStatus.success,
              value: Uint8List.fromList([0xCD]),
            ));
            async.flushMicrotasks();

            async.elapse(const Duration(seconds: 11));
            expect(disconnections, ['client-A']);

            server.dispose();
          });
        },
      );

      test(
        'I079 — write-without-response uses recordActivity (no pend)',
        () {
          fakeAsync((async) {
            final server = bluey.server(
              lifecycleInterval: const Duration(seconds: 10),
            )!;

            final disconnections = <String>[];
            server.disconnections.listen(disconnections.add);

            mockPlatform.emitWriteRequest(platform.PlatformWriteRequest(
              requestId: 1,
              centralId: 'client-A',
              characteristicUuid: lifecycle.heartbeatCharUuid,
              value: lifecycle.heartbeatValue,
              responseNeeded: false,
              offset: 0,
              characteristicHandle: 0,
            ));
            async.flushMicrotasks();

            // 9s later, write-without-response arrives — extends timer.
            async.elapse(const Duration(seconds: 9));
            mockPlatform.emitWriteRequest(platform.PlatformWriteRequest(
              requestId: 50,
              centralId: 'client-A',
              characteristicUuid: '12345678-1234-1234-1234-123456789abc',
              value: Uint8List.fromList([0xEE]),
              responseNeeded: false,
              offset: 0,
              characteristicHandle: 0,
            ));
            async.flushMicrotasks();

            // 9s after the write — total 18s since heartbeat, but only 9s
            // since the write-without-response refreshed the timer.
            async.elapse(const Duration(seconds: 9));
            expect(disconnections, isEmpty,
                reason: 'recordActivity should reset timer');

            // 2s more — past the window from the last activity.
            async.elapse(const Duration(seconds: 2));
            expect(disconnections, ['client-A']);

            server.dispose();
          });
        },
      );

      test(
        'I079 — disconnect mid-pending request leaves no leaked state',
        () {
          fakeAsync((async) {
            final server = bluey.server(
              lifecycleInterval: const Duration(seconds: 10),
            )!;

            final disconnections = <String>[];
            server.disconnections.listen(disconnections.add);

            // Track + arrive a pending write-with-response.
            mockPlatform.emitWriteRequest(platform.PlatformWriteRequest(
              requestId: 1,
              centralId: 'client-A',
              characteristicUuid: lifecycle.heartbeatCharUuid,
              value: lifecycle.heartbeatValue,
              responseNeeded: false,
              offset: 0,
              characteristicHandle: 0,
            ));
            WriteRequest? captured;
            server.writeRequests.listen((r) => captured = r);
            mockPlatform.emitWriteRequest(platform.PlatformWriteRequest(
              requestId: 99,
              centralId: 'client-A',
              characteristicUuid: '12345678-1234-1234-1234-123456789abc',
              value: Uint8List.fromList([0xAB]),
              responseNeeded: true,
              offset: 0,
              characteristicHandle: 0,
            ));
            async.flushMicrotasks();
            expect(captured, isNotNull);

            // Platform disconnect mid-request.
            mockPlatform.emitCentralDisconnected('client-A');
            async.flushMicrotasks();
            expect(disconnections, ['client-A']);

            // Late respond from the app — must be a no-op (no throw, no
            // double-fire of disconnections).
            unawaited(server.respondToWrite(
              captured!,
              status: GattResponseStatus.success,
            ));
            async.flushMicrotasks();

            // Re-track the same client. Heartbeat-timer must run on its
            // own fresh entry, with no phantom pending state.
            mockPlatform.emitWriteRequest(platform.PlatformWriteRequest(
              requestId: 200,
              centralId: 'client-A',
              characteristicUuid: lifecycle.heartbeatCharUuid,
              value: lifecycle.heartbeatValue,
              responseNeeded: false,
              offset: 0,
              characteristicHandle: 0,
            ));
            async.flushMicrotasks();

            async.elapse(const Duration(seconds: 11));
            expect(disconnections, ['client-A', 'client-A'],
                reason: 'second timeout fires on the new entry');

            server.dispose();
          });
        },
      );

      test(
        'I079 — requestCompleted fires even if platform respond throws',
        () {
          fakeAsync((async) {
            final server = bluey.server(
              lifecycleInterval: const Duration(seconds: 10),
            )!;

            final disconnections = <String>[];
            server.disconnections.listen(disconnections.add);

            // Track + arrive a pending write-with-response.
            mockPlatform.emitWriteRequest(platform.PlatformWriteRequest(
              requestId: 1,
              centralId: 'client-A',
              characteristicUuid: lifecycle.heartbeatCharUuid,
              value: lifecycle.heartbeatValue,
              responseNeeded: false,
              offset: 0,
              characteristicHandle: 0,
            ));
            WriteRequest? captured;
            server.writeRequests.listen((r) => captured = r);
            mockPlatform.emitWriteRequest(platform.PlatformWriteRequest(
              requestId: 99,
              centralId: 'client-A',
              characteristicUuid: '12345678-1234-1234-1234-123456789abc',
              value: Uint8List.fromList([0xAB]),
              responseNeeded: true,
              offset: 0,
              characteristicHandle: 0,
            ));
            async.flushMicrotasks();
            expect(captured, isNotNull);

            // Configure the platform to throw on respondToWriteRequest.
            mockPlatform.throwOnRespondToWriteRequest =
                StateError('platform respond failed');

            // App responds — platform call throws, but pending must already
            // be drained.
            Object? thrown;
            unawaited(server
                .respondToWrite(captured!, status: GattResponseStatus.success)
                .catchError((Object e) {
              thrown = e;
            }));
            async.flushMicrotasks();
            expect(thrown, isA<StateError>());

            // If pending was drained correctly, the heartbeat clock has
            // restarted. After the interval elapses, gone fires.
            async.elapse(const Duration(seconds: 11));
            expect(disconnections, ['client-A'],
                reason:
                    'pending must drain before platform call; otherwise '
                    'the timer would stay paused forever');

            server.dispose();
          });
        },
      );
    });

    group('GattResponseStatus mapping', () {
      test('all GattResponseStatus values map to platform status', () async {
        final server = bluey.server()!;

        server.connections.listen((_) {});
        mockPlatform.emitCentralConnected(
          const platform.PlatformCentral(id: 'central-1', mtu: 512),
        );
        await Future.delayed(Duration(milliseconds: 10));

        late ReadRequest capturedRequest;
        server.readRequests.listen((r) => capturedRequest = r);

        // Test each status
        for (final status in GattResponseStatus.values) {
          mockPlatform.respondToReadCalls.clear();

          mockPlatform.emitReadRequest(
            platform.PlatformReadRequest(
              requestId: status.index,
              centralId: 'central-1',
              characteristicUuid: '00002a19-0000-1000-8000-00805f9b34fb',
              offset: 0,
              characteristicHandle: 0,
            ),
          );
          await Future.delayed(Duration(milliseconds: 10));

          await server.respondToRead(
            capturedRequest,
            status: status,
            value: Uint8List(0),
          );

          expect(
            mockPlatform.respondToReadCalls,
            hasLength(1),
            reason: 'Status $status should be mapped',
          );
        }
      });
    });

    group('respond error translation (I009)', () {
      // Verify that platform-interface GattOperationStatusFailedException
      // (e.g. ATT status 0x0A NoPendingRequest after a central drops mid-
      // transaction) is translated into the user-facing
      // ServerRespondFailedException at the BlueyServer boundary, mirroring
      // the client-side translation in BlueyConnection.

      Future<ReadRequest> setUpReadRequest({required int requestId}) async {
        final server = bluey.server()!;
        server.connections.listen((_) {});
        mockPlatform.emitCentralConnected(
          const platform.PlatformCentral(id: 'central-1', mtu: 512),
        );
        await Future.delayed(Duration(milliseconds: 10));

        late ReadRequest captured;
        server.readRequests.listen((r) => captured = r);
        mockPlatform.emitReadRequest(
          platform.PlatformReadRequest(
            requestId: requestId,
            centralId: 'central-1',
            characteristicUuid: '00002a19-0000-1000-8000-00805f9b34fb',
            offset: 0,
            characteristicHandle: 0,
          ),
        );
        await Future.delayed(Duration(milliseconds: 10));
        return captured;
      }

      Future<WriteRequest> setUpWriteRequest({required int requestId}) async {
        final server = bluey.server()!;
        server.connections.listen((_) {});
        mockPlatform.emitCentralConnected(
          const platform.PlatformCentral(id: 'central-1', mtu: 512),
        );
        await Future.delayed(Duration(milliseconds: 10));

        late WriteRequest captured;
        server.writeRequests.listen((r) => captured = r);
        mockPlatform.emitWriteRequest(
          platform.PlatformWriteRequest(
            requestId: requestId,
            centralId: 'central-1',
            characteristicUuid: '00002a19-0000-1000-8000-00805f9b34fb',
            value: Uint8List.fromList([1, 2, 3]),
            offset: 0,
            responseNeeded: true,
            characteristicHandle: 0,
          ),
        );
        await Future.delayed(Duration(milliseconds: 10));
        return captured;
      }

      test(
          'respondToRead translates GattOperationStatusFailedException to '
          'ServerRespondFailedException', () async {
        final server = bluey.server()!;
        final request = await setUpReadRequest(requestId: 42);

        mockPlatform.throwOnRespondToReadRequest =
            const platform.GattOperationStatusFailedException(
          'respondToReadRequest',
          0x0A,
        );

        await expectLater(
          () => server.respondToRead(
            request,
            status: GattResponseStatus.success,
            value: Uint8List.fromList([1]),
          ),
          throwsA(
            isA<ServerRespondFailedException>()
                .having((e) => e.operation, 'operation', 'respondToRead')
                .having((e) => e.status, 'status', 0x0A)
                .having(
                  (e) => e.clientId,
                  'clientId',
                  request.client.id,
                )
                .having(
                  (e) => e.characteristicId,
                  'characteristicId',
                  request.characteristicId,
                ),
          ),
        );
      });

      test(
          'respondToWrite translates GattOperationStatusFailedException to '
          'ServerRespondFailedException', () async {
        final server = bluey.server()!;
        final request = await setUpWriteRequest(requestId: 7);

        mockPlatform.throwOnRespondToWriteRequest =
            const platform.GattOperationStatusFailedException(
          'respondToWriteRequest',
          0x0A,
        );

        await expectLater(
          () => server.respondToWrite(
            request,
            status: GattResponseStatus.success,
          ),
          throwsA(
            isA<ServerRespondFailedException>()
                .having((e) => e.operation, 'operation', 'respondToWrite')
                .having((e) => e.status, 'status', 0x0A)
                .having(
                  (e) => e.clientId,
                  'clientId',
                  request.client.id,
                )
                .having(
                  (e) => e.characteristicId,
                  'characteristicId',
                  request.characteristicId,
                ),
          ),
        );
      });

      test('ServerRespondFailedException is a BlueyException subtype', () {
        final e = ServerRespondFailedException(
          operation: 'respondToRead',
          status: 0x0A,
          clientId: UUID('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
          characteristicId: UUID('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'),
        );
        expect(e, isA<BlueyException>());
      });
    });
  });
}

/// A platform that does not support advertising.
final class _NonAdvertisingPlatform extends MockBlueyPlatform {
  @override
  platform.Capabilities get capabilities => const platform.Capabilities(
    platformKind: platform.PlatformKind.fake,
    canScan: true,
    canConnect: true,
    canAdvertise: false,
  );
}
