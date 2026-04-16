import 'dart:async';

import 'package:bluey/bluey.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../application/connect_saved_peer.dart';
import '../application/discover_peers.dart';
import '../application/forget_saved_peer.dart';
import '../infrastructure/peer_storage.dart';
import 'peer_state.dart';

/// Cubit managing the peer discovery and reconnection flow.
class PeerCubit extends Cubit<PeerState> {
  final DiscoverPeers _discoverPeers;
  final ConnectSavedPeer _connectSavedPeer;
  final ForgetSavedPeer _forgetSavedPeer;
  final PeerStorage _storage;

  StreamSubscription<ConnectionState>? _connectionSub;

  PeerCubit({
    required DiscoverPeers discoverPeers,
    required ConnectSavedPeer connectSavedPeer,
    required ForgetSavedPeer forgetSavedPeer,
    required PeerStorage storage,
  })  : _discoverPeers = discoverPeers,
        _connectSavedPeer = connectSavedPeer,
        _forgetSavedPeer = forgetSavedPeer,
        _storage = storage,
        super(const PeerState());

  /// Initializes the cubit: tries the saved peer, falls back to initial.
  Future<void> initialize() async {
    final savedId = await _storage.load();
    if (savedId != null) {
      emit(state.copyWith(
        status: PeerScreenStatus.restoring,
        savedPeerId: savedId,
      ));
      try {
        final connection = await _connectSavedPeer();
        if (connection != null) {
          _listenToConnection(connection);
          emit(state.copyWith(
            status: PeerScreenStatus.connected,
            connection: connection,
          ));
          return;
        }
      } on PeerNotFoundException {
        // Saved peer not reachable -- fall through to initial.
      } catch (_) {
        // Other error -- fall through to initial.
      }
    }
    emit(state.copyWith(status: PeerScreenStatus.initial));
  }

  /// Scans for nearby Bluey servers.
  Future<void> discover() async {
    emit(state.copyWith(status: PeerScreenStatus.discovering));
    try {
      final peers = await _discoverPeers();
      emit(state.copyWith(status: PeerScreenStatus.discovered, peers: peers));
    } catch (e) {
      emit(state.copyWith(
        status: PeerScreenStatus.error,
        error: 'Discovery failed: $e',
      ));
    }
  }

  /// Connects to a discovered peer, persists the [ServerId], and
  /// transitions to the connected state.
  Future<void> connectToPeer(BlueyPeer peer) async {
    emit(state.copyWith(status: PeerScreenStatus.connecting));
    try {
      final connection = await peer.connect();
      await _storage.save(peer.serverId);
      _listenToConnection(connection);
      emit(state.copyWith(
        status: PeerScreenStatus.connected,
        connection: connection,
        savedPeerId: peer.serverId,
      ));
    } catch (e) {
      emit(state.copyWith(
        status: PeerScreenStatus.error,
        error: 'Connect failed: $e',
      ));
    }
  }

  /// Disconnects the active connection and returns to the initial state.
  Future<void> disconnect() async {
    await _connectionSub?.cancel();
    _connectionSub = null;
    try {
      await state.connection?.disconnect();
    } catch (_) {}
    emit(state.withoutConnection().copyWith(
      status: PeerScreenStatus.initial,
    ));
  }

  /// Forgets the saved peer and returns to the initial state.
  Future<void> forgetPeer() async {
    await _connectionSub?.cancel();
    _connectionSub = null;
    try {
      await state.connection?.disconnect();
    } catch (_) {}
    await _forgetSavedPeer();
    emit(const PeerState(status: PeerScreenStatus.initial));
  }

  void _listenToConnection(Connection connection) {
    _connectionSub?.cancel();
    _connectionSub = connection.stateChanges.listen((connectionState) {
      if (connectionState == ConnectionState.disconnected) {
        emit(state.withoutConnection().copyWith(
          status: PeerScreenStatus.error,
          error: 'Peer disconnected',
        ));
      }
    });
  }

  @override
  Future<void> close() {
    _connectionSub?.cancel();
    state.connection?.disconnect();
    return super.close();
  }
}
