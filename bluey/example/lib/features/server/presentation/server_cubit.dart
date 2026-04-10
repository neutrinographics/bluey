import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:bluey/bluey.dart';

import '../domain/use_cases/check_server_support.dart';
import '../domain/use_cases/start_advertising.dart';
import '../domain/use_cases/stop_advertising.dart';
import '../domain/use_cases/add_service.dart';
import '../domain/use_cases/send_notification.dart';
import '../domain/use_cases/observe_connections.dart';
import '../domain/use_cases/disconnect_central.dart';
import '../domain/use_cases/dispose_server.dart';
import 'server_state.dart';

/// Cubit for managing server state.
class ServerCubit extends Cubit<ServerScreenState> {
  final CheckServerSupport _checkServerSupport;
  final StartAdvertising _startAdvertising;
  final StopAdvertising _stopAdvertising;
  final AddService _addService;
  final SendNotification _sendNotification;
  final ObserveConnections _observeConnections;
  final DisconnectCentral _disconnectCentral;
  final DisposeServer _disposeServer;

  StreamSubscription<Central>? _connectionSubscription;

  // Demo service UUIDs
  static final demoServiceUuid = UUID('12345678-1234-1234-1234-123456789abc');
  static final demoCharUuid = UUID('12345678-1234-1234-1234-123456789abd');

  ServerCubit({
    required CheckServerSupport checkServerSupport,
    required StartAdvertising startAdvertising,
    required StopAdvertising stopAdvertising,
    required AddService addService,
    required SendNotification sendNotification,
    required ObserveConnections observeConnections,
    required DisconnectCentral disconnectCentral,
    required DisposeServer disposeServer,
  }) : _checkServerSupport = checkServerSupport,
       _startAdvertising = startAdvertising,
       _stopAdvertising = stopAdvertising,
       _addService = addService,
       _sendNotification = sendNotification,
       _observeConnections = observeConnections,
       _disconnectCentral = disconnectCentral,
       _disposeServer = disposeServer,
       super(const ServerScreenState());

  /// Initializes the server.
  Future<void> initialize() async {
    if (!_checkServerSupport()) {
      _addLog('Server', 'Peripheral role not supported on this platform');
      emit(state.copyWith(isSupported: false));
      return;
    }

    // Listen for central connections
    _connectionSubscription = _observeConnections().listen(
      (central) {
        final centrals = [...state.connectedCentrals, central];
        emit(state.copyWith(connectedCentrals: centrals));
        _addLog('Connection', 'Central connected: ${central.id}');
      },
      onError: (error) {
        _addLog('Error', 'Connection stream error: $error');
        emit(state.copyWith(error: 'Connection error: $error'));
      },
    );

    // Add demo service
    try {
      await _addService(
        HostedService(
          uuid: demoServiceUuid,
          isPrimary: true,
          characteristics: [
            HostedCharacteristic(
              uuid: demoCharUuid,
              properties: const CharacteristicProperties(
                canRead: true,
                canWrite: true,
                canNotify: true,
              ),
              permissions: const [GattPermission.read, GattPermission.write],
            ),
          ],
        ),
      );
      _addLog('Server', 'Initialized with demo service');
    } catch (e) {
      _addLog('Error', 'Failed to add service: $e');
      emit(state.copyWith(error: 'Failed to initialize server: $e'));
    }
  }

  /// Starts advertising.
  Future<void> startAdvertising() async {
    try {
      await _startAdvertising(name: 'Bluey Demo', services: [demoServiceUuid]);
      emit(state.copyWith(isAdvertising: true));
      _addLog('Advertising', 'Started advertising');
    } catch (e) {
      emit(state.copyWith(error: 'Failed to start advertising: $e'));
    }
  }

  /// Stops advertising.
  Future<void> stopAdvertising() async {
    try {
      await _stopAdvertising();
      emit(state.copyWith(isAdvertising: false));
      _addLog('Advertising', 'Stopped advertising');
    } catch (e) {
      emit(state.copyWith(error: 'Failed to stop advertising: $e'));
    }
  }

  /// Sends a notification to all connected centrals.
  Future<void> sendNotification() async {
    if (state.connectedCentrals.isEmpty) {
      emit(state.copyWith(error: 'No centrals connected'));
      return;
    }

    try {
      final count = state.notificationCount + 1;
      final data = Uint8List.fromList([count & 0xFF]);
      await _sendNotification(demoCharUuid, data);
      emit(state.copyWith(notificationCount: count));
      _addLog('Notify', 'Sent notification #$count to all centrals');
    } catch (e) {
      emit(state.copyWith(error: 'Failed to send notification: $e'));
    }
  }

  /// Disconnects a specific central.
  Future<void> disconnectCentral(Central central) async {
    try {
      await _disconnectCentral(central);
      final centrals =
          state.connectedCentrals.where((c) => c.id != central.id).toList();
      emit(state.copyWith(connectedCentrals: centrals));
      _addLog('Connection', 'Disconnected central: ${central.id}');
    } catch (e) {
      emit(state.copyWith(error: 'Failed to disconnect: $e'));
    }
  }

  /// Clears the log.
  void clearLog() {
    emit(state.copyWith(log: []));
  }

  /// Clears any error message.
  void clearError() {
    emit(state.copyWith(error: null));
  }

  void _addLog(String tag, String message) {
    final log = [ServerLogEntry(tag, message), ...state.log];
    if (log.length > 100) log.removeLast();
    emit(state.copyWith(log: log));
  }

  @override
  Future<void> close() {
    _connectionSubscription?.cancel();
    _disposeServer();
    return super.close();
  }
}
