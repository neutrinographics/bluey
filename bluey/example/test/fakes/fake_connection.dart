import 'dart:async';

import 'package:bluey/bluey.dart';

import 'fake_remote_characteristic.dart';

/// Fake [AndroidConnectionExtensions] used by [FakeConnection] to host
/// MTU state. Mirrors the test pattern in
/// `bluey/test/connection_test.dart:MockAndroidConnectionExtensions`.
class _FakeAndroidConnectionExtensions implements AndroidConnectionExtensions {
  Mtu _mtu = Mtu.fromPlatform(23);
  int? _mtuRequest;

  @override
  Mtu get mtu => _mtu;

  @override
  Future<Mtu> requestMtu(Mtu desired) async {
    _mtuRequest = desired.value;
    _mtu = desired;
    return _mtu;
  }

  /// Records what mtu was most recently requested.
  int? get lastRequestedMtu => _mtuRequest;

  // Stub all other AndroidConnectionExtensions members.
  @override
  BondState get bondState => BondState.none;
  @override
  Stream<BondState> get bondStateChanges => const Stream.empty();
  @override
  Future<void> bond() async {}
  @override
  Future<void> removeBond() async {}
  @override
  Phy get txPhy => Phy.le1m;
  @override
  Phy get rxPhy => Phy.le1m;
  @override
  Stream<({Phy tx, Phy rx})> get phyChanges => const Stream.empty();
  @override
  Future<void> requestPhy({Phy? txPhy, Phy? rxPhy}) async {}
  @override
  ConnectionParameters get connectionParameters => ConnectionParameters(
    interval: ConnectionInterval(30),
    latency: PeripheralLatency(0),
    timeout: SupervisionTimeout(4000),
  );
  @override
  Future<void> requestConnectionParameters(ConnectionParameters params) async {}
}

/// Programmable [Connection] for runner tests. Holds a single fake
/// service with one fake characteristic that tests configure via
/// `stressChar.onWriteHook` / `stressChar.onReadHook` /
/// `stressChar.emitNotification`.
class FakeConnection implements Connection {
  final FakeRemoteCharacteristic stressChar;
  final UUID stressServiceUuid;
  final _stateController = StreamController<ConnectionState>.broadcast();

  ConnectionState _state = ConnectionState.ready;
  final _FakeAndroidConnectionExtensions _android =
      _FakeAndroidConnectionExtensions();

  FakeConnection({required this.stressServiceUuid, required this.stressChar});

  @override
  ConnectionState get state => _state;

  @override
  Stream<ConnectionState> get stateChanges => _stateController.stream;

  @override
  Stream<List<RemoteService>> get servicesChanges => const Stream.empty();

  @override
  Future<WritePayloadLimit> maxWritePayload({
    required bool withResponse,
  }) async {
    return WritePayloadLimit.fromPlatform(_android.mtu.value - 3);
  }

  /// Records what mtu was most recently requested.
  int? get lastRequestedMtu => _android.lastRequestedMtu;

  @override
  Future<List<RemoteService>> services({bool cache = false}) async {
    return [
      _FakeService(stressServiceUuid, [stressChar]),
    ];
  }

  @override
  RemoteService service(UUID uuid) {
    if (uuid == stressServiceUuid) {
      return _FakeService(stressServiceUuid, [stressChar]);
    }
    throw ServiceNotFoundException(uuid);
  }

  @override
  Future<bool> hasService(UUID uuid) async => uuid == stressServiceUuid;

  @override
  Future<void> disconnect() async {
    _state = ConnectionState.disconnected;
    _stateController.add(_state);
  }

  /// Test-only: simulate an external disconnect mid-run.
  void simulateDisconnect() {
    _state = ConnectionState.disconnected;
    _stateController.add(_state);
  }

  // === Stubbed Connection interface members (not used by stress tests) ===

  @override
  UUID get deviceId => throw UnimplementedError();

  @override
  Future<int> readRssi() => throw UnimplementedError();

  @override
  AndroidConnectionExtensions? get android => _android;

  @override
  IosConnectionExtensions? get ios => null;
}

class _FakeService implements RemoteService {
  @override
  final UUID uuid;
  final List<RemoteCharacteristic> _characteristics;

  _FakeService(this.uuid, this._characteristics);

  @override
  bool get isPrimary => true;

  @override
  List<RemoteCharacteristic> characteristics({UUID? uuid}) {
    if (uuid == null) return List.unmodifiable(_characteristics);
    return List.unmodifiable(_characteristics.where((c) => c.uuid == uuid));
  }

  @override
  RemoteCharacteristic characteristic(UUID uuid) {
    final matches = _characteristics.where((c) => c.uuid == uuid).toList();
    if (matches.isEmpty) {
      throw CharacteristicNotFoundException(uuid);
    }
    if (matches.length > 1) {
      throw AmbiguousAttributeException(
        uuid,
        matches.length,
        attributeKind: 'characteristic',
      );
    }
    return matches.single;
  }

  @override
  List<RemoteService> get includedServices => const [];
}
