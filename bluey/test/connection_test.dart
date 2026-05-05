import 'dart:async';
import 'package:bluey/bluey.dart';
import 'package:flutter_test/flutter_test.dart';

// Mock implementation for testing the interface
class MockConnection implements Connection {
  @override
  final UUID deviceId;

  @override
  ConnectionState state;

  @override
  Mtu mtu;

  final List<RemoteService> _services;

  final _stateController = StreamController<ConnectionState>.broadcast();

  MockConnection({
    required this.deviceId,
    this.state = ConnectionState.ready,
    Mtu? mtu,
    List<RemoteService>? services,
  }) : mtu = mtu ?? Mtu.fromPlatform(23),
       _services = services ?? [];

  @override
  Stream<ConnectionState> get stateChanges => _stateController.stream;

  @override
  Stream<List<RemoteService>> get servicesChanges => const Stream.empty();

  @override
  RemoteService service(UUID uuid) {
    final svc = _services.where((s) => s.uuid == uuid).firstOrNull;
    if (svc == null) {
      throw ServiceNotFoundException(uuid);
    }
    return svc;
  }

  @override
  Future<List<RemoteService>> services({bool cache = false}) async {
    return _services;
  }

  @override
  Future<bool> hasService(UUID uuid) async {
    final svcs = await services();
    return svcs.any((s) => s.uuid == uuid);
  }

  @override
  Future<Mtu> requestMtu(Mtu mtu) async {
    // Simulate negotiation - might get less than requested
    final negotiated = mtu.value > 512 ? 512 : mtu.value;
    this.mtu = Mtu.fromPlatform(negotiated);
    return this.mtu;
  }

  @override
  Future<WritePayloadLimit> maxWritePayload({required bool withResponse}) async {
    return WritePayloadLimit.fromPlatform(mtu.value - 3);
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

  @override
  AndroidConnectionExtensions? get android => null;

  @override
  IosConnectionExtensions? get ios => null;

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
  final bool isPrimary;

  @override
  List<RemoteCharacteristic> characteristics({UUID? uuid}) => const [];

  @override
  List<RemoteService> get includedServices => [];

  MockRemoteServiceMinimal(this.uuid, {this.isPrimary = true});

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
        expect(connection.state, equals(ConnectionState.ready));
      });

      test('has mtu', () {
        expect(connection.mtu, equals(Mtu.fromPlatform(23)));
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
        final svcs = await connection.services();
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

        final svcs = await connection.services();
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
        final negotiated = await connection.requestMtu(
          Mtu(256, capabilities: Capabilities.android),
        );
        expect(negotiated, equals(Mtu.fromPlatform(256)));
        expect(connection.mtu, equals(Mtu.fromPlatform(256)));
      });

      test('requestMtu may return less than requested', () async {
        final negotiated = await connection.requestMtu(
          Mtu(517, capabilities: Capabilities.android),
        );
        expect(negotiated.value, lessThanOrEqualTo(512));
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

    // Bonding / PHY / Connection Parameters are no longer part of the
    // Connection interface as of B.3 (I089). They live behind
    // `connection.android?.X()`. See:
    //   - test/connection/android_extensions_test.dart
    //   - test/connection/bluey_connection_capabilities_test.dart
  });
}

/// Tests for ConnectionParameters value object.
void connectionParametersTests() {
  group('ConnectionParameters', () {
    test('can be created with values', () {
      final params = ConnectionParameters(
        interval: ConnectionInterval(7.5),
        latency: PeripheralLatency(0),
        timeout: SupervisionTimeout(4000),
      );

      expect(params.interval.milliseconds, equals(7.5));
      expect(params.latency.events, equals(0));
      expect(params.timeout.milliseconds, equals(4000));
    });

    test('is immutable', () {
      final params = ConnectionParameters(
        interval: ConnectionInterval(15),
        latency: PeripheralLatency(4),
        timeout: SupervisionTimeout(6000),
      );

      // These should be final properties
      expect(params.interval.milliseconds, equals(15));
      expect(params.latency.events, equals(4));
      expect(params.timeout.milliseconds, equals(6000));
    });

    test('equality based on values', () {
      final params1 = ConnectionParameters(
        interval: ConnectionInterval(15),
        latency: PeripheralLatency(4),
        timeout: SupervisionTimeout(6000),
      );
      final params2 = ConnectionParameters(
        interval: ConnectionInterval(15),
        latency: PeripheralLatency(4),
        timeout: SupervisionTimeout(6000),
      );
      final params3 = ConnectionParameters(
        interval: ConnectionInterval(30),
        latency: PeripheralLatency(4),
        timeout: SupervisionTimeout(6000),
      );

      expect(params1, equals(params2));
      expect(params1, isNot(equals(params3)));
    });
  });
}

/// Bonding state of a device.
///
/// Tests that BondState enum exists with correct values.
void bondStateEnumTests() {
  group('BondState', () {
    test('has none value', () {
      expect(BondState.none, isNotNull);
    });

    test('has bonding value', () {
      expect(BondState.bonding, isNotNull);
    });

    test('has bonded value', () {
      expect(BondState.bonded, isNotNull);
    });

    test('values are distinct', () {
      expect(BondState.none, isNot(equals(BondState.bonding)));
      expect(BondState.none, isNot(equals(BondState.bonded)));
      expect(BondState.bonding, isNot(equals(BondState.bonded)));
    });
  });
}
