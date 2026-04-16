import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:bluey/bluey.dart';

import '../application/connect_to_device.dart';
import '../application/disconnect_device.dart';
import '../application/get_services.dart';
import '../domain/connection_settings.dart';
import 'connection_state.dart';

/// Cubit for managing connection state.
class ConnectionCubit extends Cubit<ConnectionScreenState> {
  final ConnectToDevice _connectToDevice;
  final DisconnectDevice _disconnectDevice;
  final GetServices _getServices;
  final ConnectionSettings _settings;
  final bool _isBlueyServer;

  StreamSubscription<ConnectionState>? _stateSubscription;

  ConnectionCubit({
    required Device device,
    required ConnectToDevice connectToDevice,
    required DisconnectDevice disconnectDevice,
    required GetServices getServices,
    ConnectionSettings settings = const ConnectionSettings(),
    bool isBlueyServer = false,
  }) : _connectToDevice = connectToDevice,
       _disconnectDevice = disconnectDevice,
       _getServices = getServices,
       _settings = settings,
       _isBlueyServer = isBlueyServer,
       super(ConnectionScreenState(device: device));

  /// Connects to the device.
  Future<void> connect() async {
    emit(
      state.copyWith(connectionState: ConnectionState.connecting, error: null),
    );

    try {
      final connection = await _connectToDevice(
        state.device,
        isBlueyServer: _isBlueyServer,
        settings: _settings,
      );

      _stateSubscription = connection.stateChanges.listen(
        (connectionState) {
          emit(state.copyWith(connectionState: connectionState));

          if (connectionState == ConnectionState.disconnected) {
            // Connection lost - emit event for UI to handle
            emit(
              state.withoutConnection().copyWith(error: 'Device disconnected'),
            );
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
    _stateSubscription?.cancel();
    state.connection?.disconnect();
    return super.close();
  }
}
