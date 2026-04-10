import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:bluey/bluey.dart';

import '../application/check_server_support.dart';
import '../application/start_advertising.dart';
import '../application/stop_advertising.dart';
import '../application/add_service.dart';
import '../application/send_notification.dart';
import '../application/observe_connections.dart';
import '../application/disconnect_central.dart';
import '../application/dispose_server.dart';
import '../application/get_connected_centrals.dart';
import '../application/observe_disconnections.dart';
import '../application/handle_requests.dart';
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
  final GetConnectedCentrals _getConnectedCentrals;
  final ObserveDisconnections _observeDisconnections;
  final ObserveReadRequests _observeReadRequests;
  final ObserveWriteRequests _observeWriteRequests;

  StreamSubscription<Central>? _connectionSubscription;
  StreamSubscription<String>? _disconnectionSubscription;
  StreamSubscription<ReadRequest>? _readRequestSubscription;
  StreamSubscription<WriteRequest>? _writeRequestSubscription;

  // Demo configuration
  static const advertisedName = 'Bluey Demo';
  static final demoServiceUuid = UUID('12345678-1234-1234-1234-123456789abc');
  static final demoCharUuid = UUID('12345678-1234-1234-1234-123456789abd');

  // Stored characteristic value (updated by writes, returned on reads)
  Uint8List _characteristicValue = Uint8List.fromList([0x00]);

  ServerCubit({
    required CheckServerSupport checkServerSupport,
    required StartAdvertising startAdvertising,
    required StopAdvertising stopAdvertising,
    required AddService addService,
    required SendNotification sendNotification,
    required ObserveConnections observeConnections,
    required DisconnectCentral disconnectCentral,
    required DisposeServer disposeServer,
    required GetConnectedCentrals getConnectedCentrals,
    required ObserveDisconnections observeDisconnections,
    required ObserveReadRequests observeReadRequests,
    required ObserveWriteRequests observeWriteRequests,
  }) : _checkServerSupport = checkServerSupport,
       _startAdvertising = startAdvertising,
       _stopAdvertising = stopAdvertising,
       _addService = addService,
       _sendNotification = sendNotification,
       _observeConnections = observeConnections,
       _disconnectCentral = disconnectCentral,
       _disposeServer = disposeServer,
       _getConnectedCentrals = getConnectedCentrals,
       _observeDisconnections = observeDisconnections,
       _observeReadRequests = observeReadRequests,
       _observeWriteRequests = observeWriteRequests,
       super(const ServerScreenState());

  /// Initializes the server.
  Future<void> initialize() async {
    if (!_checkServerSupport()) {
      _addLog('Server', 'Server not supported on this platform');
      emit(state.copyWith(isSupported: false));
      return;
    }

    // Listen for central connection/disconnection events and refresh
    // the list from the library's authoritative state each time.
    _connectionSubscription = _observeConnections().listen(
      (central) {
        _refreshConnectedCentrals();
        _addLog('Connection', 'Central connected: ${central.id}');
      },
      onError: (error) {
        _addLog('Error', 'Connection stream error: $error');
        emit(state.copyWith(error: 'Connection error: $error'));
      },
    );

    // Listen for central disconnections and refresh the list.
    _disconnectionSubscription = _observeDisconnections().listen(
      (centralId) {
        _refreshConnectedCentrals();
        _addLog('Connection', 'Central disconnected: $centralId');
      },
    );

    // Listen for read requests and respond with the current value.
    _readRequestSubscription = _observeReadRequests().listen(
      (request) async {
        _addLog('Read', 'From ${_shortId(request.central.id)}');
        try {
          await _observeReadRequests.respond(
            request,
            status: GattResponseStatus.success,
            value: _characteristicValue,
          );
        } catch (e) {
          _addLog('Error', 'Failed to respond to read: $e');
        }
      },
    );

    // Listen for write requests, store the value, and respond.
    _writeRequestSubscription = _observeWriteRequests().listen(
      (request) async {
        _characteristicValue = request.value;
        _addLog(
          'Write',
          'From ${_shortId(request.central.id)}: '
          '${_formatHex(request.value)}',
        );
        if (request.responseNeeded) {
          try {
            await _observeWriteRequests.respond(
              request,
              status: GattResponseStatus.success,
            );
          } catch (e) {
            _addLog('Error', 'Failed to respond to write: $e');
          }
        }
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
      await _startAdvertising(name: advertisedName, services: [demoServiceUuid]);
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
      _refreshConnectedCentrals();
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

  void _refreshConnectedCentrals() {
    emit(state.copyWith(connectedCentrals: _getConnectedCentrals()));
  }

  void _addLog(String tag, String message) {
    final log = [ServerLogEntry(tag, message), ...state.log];
    if (log.length > 100) log.removeLast();
    emit(state.copyWith(log: log));
  }

  String _shortId(UUID id) => id.toString().substring(0, 8);

  String _formatHex(Uint8List bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');

  @override
  Future<void> close() {
    _connectionSubscription?.cancel();
    _disconnectionSubscription?.cancel();
    _readRequestSubscription?.cancel();
    _writeRequestSubscription?.cancel();
    _disposeServer();
    return super.close();
  }
}
