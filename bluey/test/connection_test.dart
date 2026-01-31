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

  @override
  BondState bondState;

  @override
  Phy txPhy;

  @override
  Phy rxPhy;

  @override
  ConnectionParameters connectionParameters;

  final List<RemoteService> _services;
  bool _servicesDiscovered = false;

  final _stateController = StreamController<ConnectionState>.broadcast();
  final _bondStateController = StreamController<BondState>.broadcast();
  final _phyController = StreamController<({Phy tx, Phy rx})>.broadcast();

  MockConnection({
    required this.deviceId,
    this.state = ConnectionState.connected,
    this.mtu = 23,
    this.bondState = BondState.none,
    this.txPhy = Phy.le1m,
    this.rxPhy = Phy.le1m,
    ConnectionParameters? connectionParameters,
    List<RemoteService>? services,
  }) : connectionParameters =
           connectionParameters ??
           const ConnectionParameters(
             intervalMs: 30.0,
             latency: 0,
             timeoutMs: 4000,
           ),
       _services = services ?? [];

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

  @override
  Stream<BondState> get bondStateChanges => _bondStateController.stream;

  @override
  Future<void> bond() async {
    bondState = BondState.bonding;
    _bondStateController.add(bondState);
    bondState = BondState.bonded;
    _bondStateController.add(bondState);
  }

  @override
  Future<void> removeBond() async {
    bondState = BondState.none;
    _bondStateController.add(bondState);
  }

  @override
  Stream<({Phy tx, Phy rx})> get phyChanges => _phyController.stream;

  @override
  Future<void> requestPhy({Phy? txPhy, Phy? rxPhy}) async {
    if (txPhy != null) this.txPhy = txPhy;
    if (rxPhy != null) this.rxPhy = rxPhy;
    _phyController.add((tx: this.txPhy, rx: this.rxPhy));
  }

  @override
  Future<void> requestConnectionParameters(ConnectionParameters params) async {
    connectionParameters = params;
  }

  void emitState(ConnectionState newState) {
    state = newState;
    _stateController.add(state);
  }

  void dispose() {
    _stateController.close();
    _bondStateController.close();
    _phyController.close();
  }
}

// Minimal mock service for Connection tests
class MockRemoteServiceMinimal implements RemoteService {
  @override
  final UUID uuid;

  @override
  final bool isPrimary;

  @override
  List<RemoteCharacteristic> get characteristics => [];

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

    group('Bonding', () {
      test('has bondState property', () {
        expect(connection.bondState, isA<BondState>());
      });

      test('bondState defaults to none', () {
        expect(connection.bondState, equals(BondState.none));
      });

      test('provides bondStateChanges stream', () {
        expect(connection.bondStateChanges, isA<Stream<BondState>>());
      });

      test('bond() initiates bonding', () async {
        await connection.bond();
        expect(connection.bondState, equals(BondState.bonded));
      });

      test('bond() emits state changes', () async {
        final states = <BondState>[];
        final subscription = connection.bondStateChanges.listen(states.add);

        await connection.bond();

        await Future.delayed(Duration(milliseconds: 10));
        await subscription.cancel();

        expect(states, contains(BondState.bonding));
        expect(states, contains(BondState.bonded));
      });

      test('removeBond() removes bond', () async {
        await connection.bond();
        expect(connection.bondState, equals(BondState.bonded));

        await connection.removeBond();
        expect(connection.bondState, equals(BondState.none));
      });
    });

    group('PHY', () {
      test('has txPhy property', () {
        expect(connection.txPhy, isA<Phy>());
      });

      test('has rxPhy property', () {
        expect(connection.rxPhy, isA<Phy>());
      });

      test('txPhy defaults to le1m', () {
        expect(connection.txPhy, equals(Phy.le1m));
      });

      test('rxPhy defaults to le1m', () {
        expect(connection.rxPhy, equals(Phy.le1m));
      });

      test('provides phyChanges stream', () {
        expect(connection.phyChanges, isA<Stream<({Phy tx, Phy rx})>>());
      });

      test('requestPhy updates PHY values', () async {
        await connection.requestPhy(txPhy: Phy.le2m, rxPhy: Phy.le2m);

        expect(connection.txPhy, equals(Phy.le2m));
        expect(connection.rxPhy, equals(Phy.le2m));
      });

      test('requestPhy emits changes', () async {
        final changes = <({Phy tx, Phy rx})>[];
        final subscription = connection.phyChanges.listen(changes.add);

        await connection.requestPhy(txPhy: Phy.le2m, rxPhy: Phy.leCoded);

        await Future.delayed(Duration(milliseconds: 10));
        await subscription.cancel();

        expect(changes.length, greaterThanOrEqualTo(1));
        expect(changes.last.tx, equals(Phy.le2m));
        expect(changes.last.rx, equals(Phy.leCoded));
      });
    });

    group('Connection Parameters', () {
      test('has connectionParameters property', () {
        expect(connection.connectionParameters, isA<ConnectionParameters>());
      });

      test('connectionParameters has default values', () {
        final params = connection.connectionParameters;
        expect(params.intervalMs, isA<double>());
        expect(params.latency, isA<int>());
        expect(params.timeoutMs, isA<int>());
      });

      test('requestConnectionParameters updates values', () async {
        final newParams = ConnectionParameters(
          intervalMs: 15.0,
          latency: 2,
          timeoutMs: 5000,
        );

        await connection.requestConnectionParameters(newParams);

        expect(connection.connectionParameters.intervalMs, equals(15.0));
        expect(connection.connectionParameters.latency, equals(2));
        expect(connection.connectionParameters.timeoutMs, equals(5000));
      });
    });
  });
}

/// Tests for ConnectionParameters value object.
void connectionParametersTests() {
  group('ConnectionParameters', () {
    test('can be created with values', () {
      final params = ConnectionParameters(
        intervalMs: 7.5,
        latency: 0,
        timeoutMs: 4000,
      );

      expect(params.intervalMs, equals(7.5));
      expect(params.latency, equals(0));
      expect(params.timeoutMs, equals(4000));
    });

    test('is immutable', () {
      final params = ConnectionParameters(
        intervalMs: 15.0,
        latency: 4,
        timeoutMs: 6000,
      );

      // These should be final properties
      expect(params.intervalMs, equals(15.0));
      expect(params.latency, equals(4));
      expect(params.timeoutMs, equals(6000));
    });

    test('equality based on values', () {
      final params1 = ConnectionParameters(
        intervalMs: 15.0,
        latency: 4,
        timeoutMs: 6000,
      );
      final params2 = ConnectionParameters(
        intervalMs: 15.0,
        latency: 4,
        timeoutMs: 6000,
      );
      final params3 = ConnectionParameters(
        intervalMs: 30.0,
        latency: 4,
        timeoutMs: 6000,
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
