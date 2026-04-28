import 'dart:async';

import 'package:bluey/bluey.dart';

import 'fake_remote_characteristic.dart';

/// Programmable [Connection] for runner tests. Holds a single fake
/// service with one fake characteristic that tests configure via
/// `stressChar.onWriteHook` / `stressChar.onReadHook` /
/// `stressChar.emitNotification`.
class FakeConnection implements Connection {
  final FakeRemoteCharacteristic stressChar;
  final UUID stressServiceUuid;
  final _stateController = StreamController<ConnectionState>.broadcast();

  ConnectionState _state = ConnectionState.ready;
  int _mtu = 23;
  int? _mtuRequest;

  FakeConnection({
    required this.stressServiceUuid,
    required this.stressChar,
  });

  @override
  ConnectionState get state => _state;

  @override
  Stream<ConnectionState> get stateChanges => _stateController.stream;

  @override
  Mtu get mtu => Mtu.fromPlatform(_mtu);

  @override
  Future<Mtu> requestMtu(Mtu mtu) async {
    _mtuRequest = mtu.value;
    _mtu = mtu.value;
    return Mtu.fromPlatform(_mtu);
  }

  /// Records what mtu was most recently requested.
  int? get lastRequestedMtu => _mtuRequest;

  @override
  Future<List<RemoteService>> services({bool cache = false}) async {
    return [_FakeService(stressServiceUuid, [stressChar])];
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
  bool get isBlueyServer => throw UnimplementedError();

  @override
  ServerId? get serverId => throw UnimplementedError();

  @override
  Future<int> readRssi() => throw UnimplementedError();

  @override
  BondState get bondState => throw UnimplementedError();

  @override
  Stream<BondState> get bondStateChanges => throw UnimplementedError();

  @override
  Future<void> bond() => throw UnimplementedError();

  @override
  Future<void> removeBond() => throw UnimplementedError();

  @override
  Phy get txPhy => throw UnimplementedError();

  @override
  Phy get rxPhy => throw UnimplementedError();

  @override
  Stream<({Phy tx, Phy rx})> get phyChanges => throw UnimplementedError();

  @override
  Future<void> requestPhy({Phy? txPhy, Phy? rxPhy}) =>
      throw UnimplementedError();

  @override
  ConnectionParameters get connectionParameters => throw UnimplementedError();

  @override
  Future<void> requestConnectionParameters(ConnectionParameters params) =>
      throw UnimplementedError();
}

class _FakeService implements RemoteService {
  @override
  final UUID uuid;
  @override
  final List<RemoteCharacteristic> characteristics;

  _FakeService(this.uuid, this.characteristics);

  @override
  bool get isPrimary => true;

  @override
  RemoteCharacteristic characteristic(UUID uuid) =>
      characteristics.firstWhere(
        (c) => c.uuid == uuid,
        orElse: () => throw CharacteristicNotFoundException(uuid),
      );

  @override
  List<RemoteService> get includedServices => const [];
}
