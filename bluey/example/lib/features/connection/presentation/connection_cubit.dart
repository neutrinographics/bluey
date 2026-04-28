import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:bluey/bluey.dart';

import '../application/connect_to_device.dart';
import '../application/disconnect_device.dart';
import '../application/get_services.dart';
import '../application/try_upgrade.dart';
import '../domain/connection_settings.dart';
import 'connection_settings_cubit.dart';
import 'connection_state.dart';

/// Cubit for managing connection state.
class ConnectionCubit extends Cubit<ConnectionScreenState> {
  final ConnectToDevice _connectToDevice;
  final DisconnectDevice _disconnectDevice;
  final GetServices _getServices;
  final TryUpgrade _tryUpgrade;

  StreamSubscription<ConnectionState>? _stateSubscription;
  StreamSubscription<ConnectionSettings>? _settingsSubscription;
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
    required TryUpgrade tryUpgrade,
    required ConnectionSettingsCubit settingsCubit,
  })  : _connectToDevice = connectToDevice,
        _disconnectDevice = disconnectDevice,
        _getServices = getServices,
        _tryUpgrade = tryUpgrade,
        _settings = settingsCubit.state,
        super(ConnectionScreenState(device: device)) {
    _settingsSubscription =
        settingsCubit.stream.listen(_handleSettingsChange);
  }

  Future<void> _handleSettingsChange(ConnectionSettings newSettings) async {
    if (newSettings == _settings) return;
    _settings = newSettings;
    if (state.connection != null) {
      _suppressDisconnectDialog = true;
      await _stateSubscription?.cancel();
      _stateSubscription = null;
      try {
        await _disconnectDevice(state.connection!);
      } catch (_) {
        // best-effort; even if disconnect throws we still want to reconnect
      }
      emit(state.withoutConnection());
      _suppressDisconnectDialog = false;
      await connect();
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
                state.withoutConnection().copyWith(error: 'Device disconnected'),
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

      // Opportunistically upgrade to a PeerConnection if the remote
      // exposes the Bluey lifecycle service. This starts a
      // LifecycleClient internally — heartbeats begin flowing.
      // For non-peer devices, peer is null and the badge / heartbeat
      // path stays dormant.
      try {
        final peer = await _tryUpgrade(connection);
        if (peer != null) emit(state.copyWith(peer: peer));
      } catch (_) {
        // Best-effort; raw connection still works for non-peer devices.
      }

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

    try {
      await _disconnectDevice(connection);
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
    state.connection?.disconnect();
    return super.close();
  }
}
