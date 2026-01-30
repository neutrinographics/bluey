import 'dart:async';
import 'dart:typed_data';
import 'package:bluey/bluey.dart';
import 'package:bluey/src/well_known_uuids.dart';
import 'package:flutter_test/flutter_test.dart';

// Mock implementation for testing the interface
class MockConnection implements Connection {
  @override
  final UUID deviceId;

  @override
  ConnectionState state;

  @override
  int mtu;

  final List<RemoteService> _services;
  bool _servicesDiscovered = false;

  final _stateController = StreamController<ConnectionState>.broadcast();

  MockConnection({
    required this.deviceId,
    this.state = ConnectionState.connected,
    this.mtu = 23,
    List<RemoteService>? services,
  }) : _services = services ?? [];

  @override
  Stream<ConnectionState> get stateChanges => _stateController.stream;

  @override
  RemoteService service(UUID uuid) {
    final svc = _services.where((s) => s.uuid == uuid).firstOrNull;
    if (svc == null) {
      throw ServiceNotFoundException(uuid);
    }
    return svc;
  }

  @override
  Future<List<RemoteService>> get services async {
    _servicesDiscovered = true;
    return _services;
  }

  @override
  Future<bool> hasService(UUID uuid) async {
    final svcs = await services;
    return svcs.any((s) => s.uuid == uuid);
  }

  @override
  Future<int> requestMtu(int mtu) async {
    // Simulate negotiation - might get less than requested
    this.mtu = mtu > 512 ? 512 : mtu;
    return this.mtu;
  }

  @override
  Future<int> readRssi() async {
    return -60; // Simulated RSSI
  }

  @override
  Future<void> disconnect() async {
    state = ConnectionState.disconnecting;
    _stateController.add(state);
    state = ConnectionState.disconnected;
    _stateController.add(state);
  }

  void emitState(ConnectionState newState) {
    state = newState;
    _stateController.add(state);
  }

  void dispose() {
    _stateController.close();
  }
}

// Minimal mock service for Connection tests
class MockRemoteServiceMinimal implements RemoteService {
  @override
  final UUID uuid;

  @override
  List<RemoteCharacteristic> get characteristics => [];

  @override
  List<RemoteService> get includedServices => [];

  MockRemoteServiceMinimal(this.uuid);

  @override
  RemoteCharacteristic characteristic(UUID uuid) {
    throw CharacteristicNotFoundException(uuid);
  }
}

void main() {
  group('Connection', () {
    late MockConnection connection;

    setUp(() {
      connection = MockConnection(
        deviceId: UUID('00000000-0000-0000-0000-aabbccddeeff'),
      );
    });

    tearDown(() {
      connection.dispose();
    });

    group('Properties', () {
      test('has deviceId', () {
        expect(
          connection.deviceId,
          equals(UUID('00000000-0000-0000-0000-aabbccddeeff')),
        );
      });

      test('has state', () {
        expect(connection.state, equals(ConnectionState.connected));
      });

      test('has mtu', () {
        expect(connection.mtu, equals(23));
      });

      test('provides stateChanges stream', () {
        expect(connection.stateChanges, isA<Stream<ConnectionState>>());
      });
    });

    group('State changes', () {
      test('emits state changes', () async {
        final states = <ConnectionState>[];
        final subscription = connection.stateChanges.listen(states.add);

        connection.emitState(ConnectionState.disconnecting);
        connection.emitState(ConnectionState.disconnected);

        await Future.delayed(Duration(milliseconds: 10));
        await subscription.cancel();

        expect(states, contains(ConnectionState.disconnecting));
        expect(states, contains(ConnectionState.disconnected));
      });
    });

    group('Services', () {
      test('returns empty list when no services', () async {
        final svcs = await connection.services;
        expect(svcs, isEmpty);
      });

      test('returns services when available', () async {
        connection = MockConnection(
          deviceId: UUID('00000000-0000-0000-0000-aabbccddeeff'),
          services: [
            MockRemoteServiceMinimal(Services.heartRate),
            MockRemoteServiceMinimal(Services.battery),
          ],
        );

        final svcs = await connection.services;
        expect(svcs, hasLength(2));
      });

      test('service() finds by UUID', () {
        connection = MockConnection(
          deviceId: UUID('00000000-0000-0000-0000-aabbccddeeff'),
          services: [MockRemoteServiceMinimal(Services.heartRate)],
        );

        final svc = connection.service(Services.heartRate);
        expect(svc.uuid, equals(Services.heartRate));
      });

      test('service() throws when not found', () {
        expect(
          () => connection.service(Services.heartRate),
          throwsA(isA<ServiceNotFoundException>()),
        );
      });

      test('hasService() returns true when found', () async {
        connection = MockConnection(
          deviceId: UUID('00000000-0000-0000-0000-aabbccddeeff'),
          services: [MockRemoteServiceMinimal(Services.heartRate)],
        );

        expect(await connection.hasService(Services.heartRate), isTrue);
      });

      test('hasService() returns false when not found', () async {
        expect(await connection.hasService(Services.heartRate), isFalse);
      });
    });

    group('MTU', () {
      test('requestMtu returns negotiated MTU', () async {
        final negotiated = await connection.requestMtu(256);
        expect(negotiated, equals(256));
        expect(connection.mtu, equals(256));
      });

      test('requestMtu may return less than requested', () async {
        final negotiated = await connection.requestMtu(1024);
        expect(negotiated, lessThanOrEqualTo(512));
      });
    });

    group('RSSI', () {
      test('readRssi returns signal strength', () async {
        final rssi = await connection.readRssi();
        expect(rssi, isA<int>());
        expect(rssi, lessThan(0)); // RSSI is negative dBm
      });
    });

    group('Disconnect', () {
      test('disconnect changes state', () async {
        final states = <ConnectionState>[];
        connection.stateChanges.listen(states.add);

        await connection.disconnect();

        await Future.delayed(Duration(milliseconds: 10));

        expect(states, contains(ConnectionState.disconnecting));
        expect(states, contains(ConnectionState.disconnected));
        expect(connection.state, equals(ConnectionState.disconnected));
      });
    });
  });
}
