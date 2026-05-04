import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:bluey/bluey.dart';

import '../application/check_server_support.dart';
import '../application/set_server_identity.dart';
import '../application/reset_server.dart';
import '../application/start_advertising.dart';
import '../application/stop_advertising.dart';
import '../application/add_service.dart';
import '../application/send_notification.dart';
import '../application/observe_connections.dart';
import '../application/observe_peer_connections.dart';
import '../application/dispose_server.dart';
import '../application/get_connected_clients.dart';
import '../application/observe_disconnections.dart';
import '../application/handle_requests.dart';
import '../application/get_server.dart';
import '../infrastructure/server_identity_storage.dart';
import '../infrastructure/stress_service_handler.dart';
import '../../../shared/stress_protocol.dart';
import 'server_state.dart';

/// Cubit for managing server state.
class ServerCubit extends Cubit<ServerScreenState> {
  final CheckServerSupport _checkServerSupport;
  final SetServerIdentity _setServerIdentity;
  final ResetServer _resetServer;
  final StartAdvertising _startAdvertising;
  final StopAdvertising _stopAdvertising;
  final AddService _addService;
  final SendNotification _sendNotification;
  final ObserveConnections _observeConnections;
  final ObservePeerConnections _observePeerConnections;
  final DisposeServer _disposeServer;
  final GetConnectedClients _getConnectedClients;
  final ObserveDisconnections _observeDisconnections;
  final ObserveReadRequests _observeReadRequests;
  final ObserveWriteRequests _observeWriteRequests;
  final GetServer _getServer;
  final ServerIdentityStorage _identityStorage;

  final StressServiceHandler _stressHandler = StressServiceHandler();

  StreamSubscription<Client>? _connectionSubscription;
  StreamSubscription<PeerClient>? _peerConnectionSubscription;
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
    required SetServerIdentity setServerIdentity,
    required ResetServer resetServer,
    required StartAdvertising startAdvertising,
    required StopAdvertising stopAdvertising,
    required AddService addService,
    required SendNotification sendNotification,
    required ObserveConnections observeConnections,
    required ObservePeerConnections observePeerConnections,
    required DisposeServer disposeServer,
    required GetConnectedClients getConnectedClients,
    required ObserveDisconnections observeDisconnections,
    required ObserveReadRequests observeReadRequests,
    required ObserveWriteRequests observeWriteRequests,
    required GetServer getServer,
    required ServerIdentityStorage identityStorage,
  }) : _checkServerSupport = checkServerSupport,
       _setServerIdentity = setServerIdentity,
       _resetServer = resetServer,
       _startAdvertising = startAdvertising,
       _stopAdvertising = stopAdvertising,
       _addService = addService,
       _sendNotification = sendNotification,
       _observeConnections = observeConnections,
       _observePeerConnections = observePeerConnections,
       _disposeServer = disposeServer,
       _getConnectedClients = getConnectedClients,
       _observeDisconnections = observeDisconnections,
       _observeReadRequests = observeReadRequests,
       _observeWriteRequests = observeWriteRequests,
       _getServer = getServer,
       _identityStorage = identityStorage,
       super(const ServerScreenState());

  /// Initializes the server.
  Future<void> initialize() async {
    // Load (or generate) a stable identity before the server is created.
    final identity = await _identityStorage.loadOrGenerate();
    _setServerIdentity(identity);
    emit(state.copyWith(serverId: identity));

    if (!_checkServerSupport()) {
      _addLog('Server', 'Server not supported on this platform');
      emit(state.copyWith(isSupported: false));
      return;
    }

    await _resubscribeAndSetup();
  }

  /// Subscribes to server streams and adds the demo service.
  ///
  /// Shared by [initialize] and [resetIdentity].
  Future<void> _resubscribeAndSetup() async {
    // Listen for central connection/disconnection events and refresh
    // the list from the library's authoritative state each time.
    _connectionSubscription = _observeConnections().listen(
      (client) {
        _refreshConnectedClients();
        _addLog('Connection', 'Client connected: ${_shortId(client.id)}');
      },
      onError: (error) {
        _addLog('Error', 'Connection stream error: $error');
        emit(state.copyWith(error: 'Connection error: $error'));
      },
    );

    // Listen for central disconnections and refresh the list.
    _disconnectionSubscription = _observeDisconnections().listen((clientId) {
      _refreshConnectedClients();
      // Clear the peer-identification flag for this client so the
      // BLUEY badge disappears immediately on disconnect (and a
      // reconnect-then-heartbeat re-identifies cleanly).
      final updated = Set<UUID>.from(state.blueyPeerClientIds)
        ..removeWhere((id) => id.toString() == clientId);
      if (updated.length != state.blueyPeerClientIds.length) {
        emit(state.copyWith(blueyPeerClientIds: updated));
      }
      _addLog('Connection', 'Client disconnected: ${clientId.substring(0, 8)}');
    });

    // Listen for clients identifying as Bluey peers (first heartbeat).
    _peerConnectionSubscription = _observePeerConnections().listen((peer) {
      final updated = Set<UUID>.from(state.blueyPeerClientIds)
        ..add(peer.client.id);
      emit(state.copyWith(blueyPeerClientIds: updated));
      _addLog(
        'Connection',
        'Bluey peer identified: ${_shortId(peer.client.id)}',
      );
    });

    // Listen for read requests and respond with the current value.
    _readRequestSubscription = _observeReadRequests().listen((request) async {
      if (request.characteristicId == UUID(StressProtocol.charUuid)) {
        try {
          final value = _stressHandler.onRead();
          await _observeReadRequests.respond(
            request,
            status: GattResponseStatus.success,
            value: value,
          );
        } catch (e) {
          _addLog('Stress', 'Read handler error: $e');
        }
        return;
      }
      _addLog('Read', 'From ${_shortId(request.client.id)}');
      try {
        await _observeReadRequests.respond(
          request,
          status: GattResponseStatus.success,
          value: _characteristicValue,
        );
      } catch (e) {
        _addLog('Error', 'Failed to respond to read: $e');
      }
    });

    // Listen for write requests, store the value, and respond.
    _writeRequestSubscription = _observeWriteRequests().listen((request) async {
      if (request.characteristicId == UUID(StressProtocol.charUuid)) {
        final server = _getServer();
        if (server != null) {
          try {
            await _stressHandler.onWrite(request, server);
          } catch (e) {
            _addLog('Stress', 'Write handler error: $e');
          }
        } else if (request.responseNeeded) {
          _addLog('Stress', 'Write rejected: server unavailable');
          try {
            await _observeWriteRequests.respond(
              request,
              status: GattResponseStatus.requestNotSupported,
            );
          } catch (e) {
            _addLog('Error', 'Failed to respond to stress write: $e');
          }
        }
        return;
      }
      _characteristicValue = request.value;
      _addLog(
        'Write',
        'From ${_shortId(request.client.id)}: '
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
    });

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
              descriptors: [
                HostedDescriptor.immutable(
                  uuid: Descriptors.characteristicUserDescription,
                  value: Uint8List.fromList(utf8.encode('Demo Characteristic')),
                ),
              ],
            ),
          ],
        ),
      );
      _addLog('Server', 'Initialized with demo service');
    } catch (e) {
      _addLog('Error', 'Failed to add service: $e');
      emit(state.copyWith(error: 'Failed to initialize server: $e'));
      return;
    }

    // Add stress test service
    try {
      await _addService(
        HostedService(
          uuid: UUID(StressProtocol.serviceUuid),
          isPrimary: true,
          characteristics: [
            HostedCharacteristic(
              uuid: UUID(StressProtocol.charUuid),
              properties: const CharacteristicProperties(
                canRead: true,
                canWrite: true,
                canWriteWithoutResponse: true,
                canNotify: true,
              ),
              permissions: const [GattPermission.read, GattPermission.write],
              descriptors: const [],
            ),
          ],
        ),
      );
      _addLog('Server', 'Registered stress test service');
    } catch (e) {
      _addLog('Error', 'Failed to add stress service: $e');
      emit(state.copyWith(error: 'Failed to register stress service: $e'));
    }
  }

  /// Starts advertising.
  Future<void> startAdvertising() async {
    try {
      await _startAdvertising(
        name: advertisedName,
        services: [demoServiceUuid],
      );
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

  /// Sends a notification to all connected clients.
  Future<void> sendNotification() async {
    if (state.connectedClients.isEmpty) {
      emit(state.copyWith(error: 'No clients connected'));
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

  /// Clears the log.
  void clearLog() {
    emit(state.copyWith(log: []));
  }

  /// Clears any error message.
  void clearError() {
    emit(state.copyWith(error: null));
  }

  /// Persists a fresh server identity and tears down the current
  /// server. The new identity takes effect on the next app launch —
  /// the shared [Bluey] instance binds its `localIdentity` at
  /// construction time, so live rotation requires a restart.
  Future<void> resetIdentity() async {
    // Cancel existing subscriptions before disposing the server.
    await _connectionSubscription?.cancel();
    await _peerConnectionSubscription?.cancel();
    await _disconnectionSubscription?.cancel();
    await _readRequestSubscription?.cancel();
    await _writeRequestSubscription?.cancel();

    final newId = await _identityStorage.reset();
    await _resetServer(identity: newId);
    emit(
      state.copyWith(
        serverId: newId,
        isAdvertising: false,
        connectedClients: [],
        blueyPeerClientIds: const {},
      ),
    );
    _addLog(
      'Server',
      'Identity reset: ${newId.value.substring(0, 8)}... — restart the app '
          'to apply.',
    );
  }

  void _refreshConnectedClients() {
    emit(state.copyWith(connectedClients: _getConnectedClients()));
  }

  void _addLog(String tag, String message) {
    final log = [ServerLogEntry(tag, message), ...state.log];
    if (log.length > 100) log.removeLast();
    emit(state.copyWith(log: log));
  }

  String _shortId(UUID id) => id.toString().substring(0, 8);

  String _formatHex(Uint8List bytes) => bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join(' ');

  @override
  Future<void> close() {
    _connectionSubscription?.cancel();
    _peerConnectionSubscription?.cancel();
    _disconnectionSubscription?.cancel();
    _readRequestSubscription?.cancel();
    _writeRequestSubscription?.cancel();
    _disposeServer();
    return super.close();
  }
}
