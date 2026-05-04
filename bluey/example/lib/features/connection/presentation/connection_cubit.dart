import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:bluey/bluey.dart';

import '../application/connect_to_device.dart';
import '../application/disconnect_device.dart';
import '../application/get_services.dart';
import '../application/watch_peer.dart';
import '../domain/connection_settings.dart';
import 'connection_settings_cubit.dart';
import 'connection_state.dart';

/// Cubit for managing connection state.
class ConnectionCubit extends Cubit<ConnectionScreenState> {
  final ConnectToDevice _connectToDevice;
  final DisconnectDevice _disconnectDevice;
  final GetServices _getServices;
  final WatchPeer _watchPeer;

  StreamSubscription<ConnectionState>? _stateSubscription;
  StreamSubscription<ConnectionSettings>? _settingsSubscription;
  StreamSubscription<PeerConnection?>? _peerSubscription;
  StreamSubscription<List<RemoteService>>? _servicesSubscription;
  ConnectionSettings _settings;

  /// Set during a user-initiated reconnect (tolerance change). The
  /// `_stateSubscription` listener checks this flag and skips the
  /// "Device disconnected" error emission so the dialog isn't shown
  /// during a transparent re-establishment.
  bool _suppressDisconnectDialog = false;

  ConnectionCubit({
    required Device device,
    required ConnectToDevice connectToDevice,
    required DisconnectDevice disconnectDevice,
    required GetServices getServices,
    required WatchPeer watchPeer,
    required ConnectionSettingsCubit settingsCubit,
  }) : _connectToDevice = connectToDevice,
       _disconnectDevice = disconnectDevice,
       _getServices = getServices,
       _watchPeer = watchPeer,
       _settings = settingsCubit.state,
       super(ConnectionScreenState(device: device)) {
    _settingsSubscription = settingsCubit.stream.listen(_handleSettingsChange);
  }

  Future<void> _handleSettingsChange(ConnectionSettings newSettings) async {
    if (newSettings == _settings) return;
    _settings = newSettings;
    if (state.connection != null) {
      _suppressDisconnectDialog = true;
      await _stateSubscription?.cancel();
      _stateSubscription = null;
      await _peerSubscription?.cancel();
      _peerSubscription = null;
      await _servicesSubscription?.cancel();
      _servicesSubscription = null;
      try {
        await _gracefulDisconnect(state.connection!);
      } catch (_) {
        // best-effort; even if disconnect throws we still want to reconnect
      }
      emit(state.withoutConnection());
      _suppressDisconnectDialog = false;
      await connect();
    }
  }

  /// Routes through `peer.disconnect()` when a peer is established —
  /// the peer protocol writes a 0x00 courtesy hint to the lifecycle
  /// service, allowing the remote server to drop us immediately
  /// instead of waiting for a heartbeat-silence timeout. Falls back to
  /// the raw GATT disconnect for non-peer connections.
  Future<void> _gracefulDisconnect(Connection connection) async {
    final peer = state.peer;
    if (peer != null) {
      await peer.disconnect();
    } else {
      await _disconnectDevice(connection);
    }
  }

  /// Connects to the device.
  Future<void> connect() async {
    emit(
      state.copyWith(connectionState: ConnectionState.connecting, error: null),
    );

    try {
      final connection = await _connectToDevice(
        state.device,
        settings: _settings,
      );

      _stateSubscription = connection.stateChanges.listen(
        (connectionState) {
          if (connectionState == ConnectionState.ready &&
              state.connectionState == ConnectionState.ready) {
            // Re-emitted connected means the connection upgraded (e.g.,
            // server restarted and Bluey protocol became available).
            // Reload services so the UI refreshes.
            loadServices();
          }

          emit(state.copyWith(connectionState: connectionState));

          if (connectionState == ConnectionState.disconnected) {
            if (_suppressDisconnectDialog) {
              // User-initiated tolerance change — quiet teardown.
              emit(state.withoutConnection());
            } else {
              // Connection lost - emit event for UI to handle
              emit(
                state.withoutConnection().copyWith(
                  error: 'Device disconnected',
                ),
              );
            }
          }
        },
        onError: (error) {
          emit(
            state.copyWith(
              connectionState: ConnectionState.disconnected,
              error: 'Connection state error: $error',
            ),
          );
        },
      );

      emit(
        state.copyWith(
          connection: connection,
          connectionState: connection.state,
        ),
      );

      // Watch peer status across the connection's lifetime. The stream
      // emits the initial tryUpgrade result (possibly null), then
      // re-attempts on each Service Changed re-discovery — protects the
      // badge against stale GATT caches, where the lifecycle service
      // isn't visible until the peer pushes a Service Changed.
      _peerSubscription?.cancel();
      _peerSubscription = _watchPeer(connection).listen(
        (peer) {
          if (peer != null) emit(state.copyWith(peer: peer));
        },
        onError: (_) {
          // Best-effort; raw connection still works for non-peer devices.
        },
      );

      // Mirror the peer-watching pattern for the discovered service
      // tree: the library re-discovers and emits on `servicesChanges`
      // whenever the cache is invalidated (Service Changed indication
      // from the peer, stale-cache refresh on Android, etc.). Without
      // this subscription the cubit's `state.services` would stay frozen
      // at the initial discovery, hiding consumer UI gated on specific
      // services (e.g., the "Stress Tests" button) until manual refresh.
      _servicesSubscription?.cancel();
      _servicesSubscription = connection.servicesChanges.listen(
        (services) => emit(state.copyWith(services: services)),
        onError: (_) {
          // Re-discovery failures surface elsewhere; the previous
          // service tree remains usable.
        },
      );

      // Load services after connecting
      await loadServices();
    } on BlueyException catch (e) {
      emit(
        state.copyWith(
          connectionState: ConnectionState.disconnected,
          error: e.message,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          connectionState: ConnectionState.disconnected,
          error: e.toString(),
        ),
      );
    }
  }

  /// Disconnects from the device.
  Future<void> disconnect() async {
    final connection = state.connection;
    if (connection == null) return;

    // Cancel the state listener first so the platform's disconnect event
    // doesn't trigger the "Device disconnected" error path.
    await _stateSubscription?.cancel();
    _stateSubscription = null;
    await _peerSubscription?.cancel();
    _peerSubscription = null;
    await _servicesSubscription?.cancel();
    _servicesSubscription = null;

    try {
      await _gracefulDisconnect(connection);
      emit(state.withoutConnection());
    } catch (e) {
      emit(state.copyWith(error: 'Failed to disconnect: $e'));
    }
  }

  /// Loads the services available on the connected device.
  Future<void> loadServices() async {
    final connection = state.connection;
    if (connection == null) return;

    emit(state.copyWith(isDiscovering: true));

    try {
      final services = await _getServices(connection);
      emit(state.copyWith(services: services, isDiscovering: false));
    } catch (e) {
      emit(
        state.copyWith(
          isDiscovering: false,
          error: 'Failed to load services: $e',
        ),
      );
    }
  }

  /// Clears any error message.
  void clearError() {
    emit(state.copyWith(error: null));
  }

  @override
  Future<void> close() {
    _settingsSubscription?.cancel();
    _stateSubscription?.cancel();
    _peerSubscription?.cancel();
    _servicesSubscription?.cancel();
    // Fire-and-forget: route through the peer protocol if a peer is
    // established so the server cleans up immediately.
    final peer = state.peer;
    if (peer != null) {
      peer.disconnect();
    } else {
      state.connection?.disconnect();
    }
    return super.close();
  }
}
