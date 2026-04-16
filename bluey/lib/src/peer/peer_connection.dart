import 'dart:async';

import '../connection/connection.dart';
import '../gatt_client/gatt.dart';
import '../lifecycle.dart' as lifecycle;
import '../shared/exceptions.dart';
import '../shared/uuid.dart';
import 'server_id.dart';

/// A decorator around [Connection] that hides the internal Bluey lifecycle
/// control service from the public services view.
///
/// All non-service-related methods delegate unchanged to the inner connection.
/// The three service-related methods ([services], [service], [hasService])
/// filter out the control service UUID so that library consumers never see it.
class PeerConnection implements Connection {
  final Connection _inner;
  final ServerId _serverId;

  /// Creates a [PeerConnection] wrapping the given [inner] connection.
  PeerConnection(this._inner, this._serverId);

  @override
  bool get isBlueyServer => true;

  @override
  ServerId? get serverId => _serverId;

  // --- Service-related: filter the control service ---

  @override
  RemoteService service(UUID uuid) {
    if (lifecycle.isControlService(uuid.toString())) {
      throw ServiceNotFoundException(uuid);
    }
    return _inner.service(uuid);
  }

  @override
  Future<List<RemoteService>> services({bool cache = false}) async {
    final all = await _inner.services(cache: cache);
    return all
        .where((s) => !lifecycle.isControlService(s.uuid.toString()))
        .toList();
  }

  @override
  Future<bool> hasService(UUID uuid) async {
    if (lifecycle.isControlService(uuid.toString())) return false;
    return _inner.hasService(uuid);
  }

  // --- Everything else delegates unchanged ---

  @override
  UUID get deviceId => _inner.deviceId;

  @override
  ConnectionState get state => _inner.state;

  @override
  Stream<ConnectionState> get stateChanges => _inner.stateChanges;

  @override
  int get mtu => _inner.mtu;

  @override
  Future<int> requestMtu(int mtu) => _inner.requestMtu(mtu);

  @override
  Future<int> readRssi() => _inner.readRssi();

  @override
  Future<void> disconnect() => _inner.disconnect();

  @override
  BondState get bondState => _inner.bondState;

  @override
  Stream<BondState> get bondStateChanges => _inner.bondStateChanges;

  @override
  Future<void> bond() => _inner.bond();

  @override
  Future<void> removeBond() => _inner.removeBond();

  @override
  Phy get txPhy => _inner.txPhy;

  @override
  Phy get rxPhy => _inner.rxPhy;

  @override
  Stream<({Phy tx, Phy rx})> get phyChanges => _inner.phyChanges;

  @override
  Future<void> requestPhy({Phy? txPhy, Phy? rxPhy}) =>
      _inner.requestPhy(txPhy: txPhy, rxPhy: rxPhy);

  @override
  ConnectionParameters get connectionParameters =>
      _inner.connectionParameters;

  @override
  Future<void> requestConnectionParameters(ConnectionParameters params) =>
      _inner.requestConnectionParameters(params);
}
