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
  Future<int> readRssi() => throw UnimplementedError();

  @override
  AndroidConnectionExtensions? get android => null;

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
