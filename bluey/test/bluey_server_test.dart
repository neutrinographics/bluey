import 'dart:async';
import 'dart:typed_data';

import 'package:bluey/bluey.dart';
import 'package:bluey/src/gatt_server/server.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

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
  final List<String> disconnectedClients = [];

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
    String characteristicUuid,
  ) async => Uint8List(0);

  @override
  Future<void> writeCharacteristic(
    String deviceId,
    String characteristicUuid,
    Uint8List value,
    bool withResponse,
  ) async {}

  @override
  Future<void> setNotification(
    String deviceId,
    String characteristicUuid,
    bool enable,
  ) async {}

  @override
  Stream<platform.PlatformNotification> notificationStream(String deviceId) =>
      Stream.empty();

  @override
  Future<Uint8List> readDescriptor(
    String deviceId,
    String descriptorUuid,
  ) async => Uint8List(0);

  @override
  Future<void> writeDescriptor(
    String deviceId,
    String descriptorUuid,
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
  Future<void> addService(platform.PlatformLocalService service) async {
    addedServices.add(service);
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
    String characteristicUuid,
    Uint8List value,
  ) async {
    notifyCalls.add(
      NotifyCall(characteristicUuid: characteristicUuid, value: value),
    );
  }

  @override
  Future<void> notifyCharacteristicTo(
    String centralId,
    String characteristicUuid,
    Uint8List value,
  ) async {
    notifyToCalls.add(
      NotifyToCall(
        centralId: centralId,
        characteristicUuid: characteristicUuid,
        value: value,
      ),
    );
  }

  @override
  Future<void> indicateCharacteristic(
    String characteristicUuid,
    Uint8List value,
  ) async {
    indicateCalls.add(
      IndicateCall(characteristicUuid: characteristicUuid, value: value),
    );
  }

  @override
  Future<void> indicateCharacteristicTo(
    String centralId,
    String characteristicUuid,
    Uint8List value,
  ) async {
    indicateToCalls.add(
      IndicateToCall(
        centralId: centralId,
        characteristicUuid: characteristicUuid,
        value: value,
      ),
    );
  }

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
    respondToReadCalls.add(
      RespondToReadCall(requestId: requestId, status: status, value: value),
    );
  }

  @override
  Future<void> respondToWriteRequest(
    int requestId,
    platform.PlatformGattStatus status,
  ) async {
    respondToWriteCalls.add(
      RespondToWriteCall(requestId: requestId, status: status),
    );
  }

  @override
  Future<void> disconnectCentral(String centralId) async {
    disconnectedClients.add(centralId);
  }

  @override
  Future<void> closeServer() async {
    // Mock implementation - nothing to do
  }

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

        expect(mockPlatform.addedServices, hasLength(1));
        expect(
          mockPlatform.addedServices.first.uuid,
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
        // Bluey manufacturer data marker is set instead
        expect(
          mockPlatform.lastAdvertiseConfig?.manufacturerDataCompanyId,
          equals(0xFFFF),
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

      test('startAdvertising sets Bluey marker when no app manufacturer data',
          () async {
        final server = bluey.server()!;

        await server.startAdvertising(name: 'Test Device');

        expect(
          mockPlatform.lastAdvertiseConfig?.manufacturerDataCompanyId,
          equals(0xFFFF),
        );
        expect(
          mockPlatform.lastAdvertiseConfig?.manufacturerData,
          equals(Uint8List.fromList([0xB1, 0xE7])),
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

    group('Notifications', () {
      test('notify sends to all subscribed centrals', () async {
        final server = bluey.server()!;
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
      test('indicate sends indication to all subscribed centrals', () async {
        final server = bluey.server()!;
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

    group('Central disconnect', () {
      test('central.disconnect() disconnects the central', () async {
        final server = bluey.server()!;

        server.connections.listen((_) {});
        mockPlatform.emitCentralConnected(
          const platform.PlatformCentral(id: 'central-1', mtu: 512),
        );
        await Future.delayed(Duration(milliseconds: 10));

        final central = server.connectedClients.first;
        await central.disconnect();

        expect(mockPlatform.disconnectedClients, contains('central-1'));
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
  });
}

/// A platform that does not support advertising.
final class _NonAdvertisingPlatform extends MockBlueyPlatform {
  @override
  platform.Capabilities get capabilities => const platform.Capabilities(
    canScan: true,
    canConnect: true,
    canAdvertise: false,
  );
}
