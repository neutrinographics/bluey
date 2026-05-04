import 'dart:async';

import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;

import '../event_bus.dart';
import '../events.dart';
import '../lifecycle.dart' as lifecycle;
import '../log/bluey_logger.dart';
import '../log/log_level.dart';
import '../peer/server_id.dart';

/// Server-side lifecycle management.
///
/// Handles the control service (heartbeat monitoring, interval reads) and
/// detects client disconnection via heartbeat timeouts. Internal to the
/// GATT Server bounded context.
class LifecycleServer {
  final platform.BlueyPlatform _platform;
  final Duration? _interval;
  final ServerId _serverId;
  final void Function(String clientId) onClientGone;
  final void Function(String clientId, ServerId senderId)? onPeerIdentified;
  final BlueyLogger _logger;
  final EventPublisher? _events;

  bool _controlServiceAdded = false;
  final Map<String, _ClientLiveness> _clients = {};

  LifecycleServer({
    required platform.BlueyPlatform platformApi,
    required Duration? interval,
    required ServerId serverId,
    required this.onClientGone,
    required BlueyLogger logger,
    this.onPeerIdentified,
    EventPublisher? events,
  }) : _platform = platformApi,
       _interval = interval,
       _serverId = serverId,
       _logger = logger,
       _events = events;

  /// Whether lifecycle management is enabled (interval is non-null).
  bool get isEnabled => _interval != null;

  /// Adds the control service to the platform if lifecycle is enabled
  /// and it hasn't been added yet. Returns the populated service so
  /// callers can record its handles. Returns null when lifecycle is
  /// disabled or the service was already added.
  Future<platform.PlatformLocalService?> addControlServiceIfNeeded() async {
    _logger.log(
      BlueyLogLevel.debug,
      'bluey.server.lifecycle',
      'addControlServiceIfNeeded invoked',
    );
    if (_interval == null || _controlServiceAdded) {
      _logger.log(
        BlueyLogLevel.trace,
        'bluey.server.lifecycle',
        'addControlServiceIfNeeded skipped',
        data: {'reason': _interval == null ? 'disabled' : 'already-added'},
      );
      return null;
    }
    final populated = await _platform.addService(
      lifecycle.buildControlService(),
    );
    _controlServiceAdded = true;
    return populated;
  }

  /// Handles a write request to a control service characteristic.
  /// Returns true if the request was handled (caller should not forward it).
  bool handleWriteRequest(platform.PlatformWriteRequest req) {
    if (!lifecycle.isControlServiceCharacteristic(req.characteristicUuid)) {
      return false;
    }

    // Auto-respond if the platform requires it
    if (req.responseNeeded) {
      _platform.respondToWriteRequest(
        req.requestId,
        platform.PlatformGattStatus.success,
      );
    }

    final clientId = req.centralId;

    final lifecycle.LifecycleMessage message;
    try {
      message = lifecycle.lifecycleCodec.decodeMessage(req.value);
    } on lifecycle.MalformedLifecycleMessage catch (e) {
      _logger.log(
        BlueyLogLevel.warn,
        'bluey.server.lifecycle',
        'malformed lifecycle write — dropping',
        data: {'clientId': clientId, 'reason': e.reason},
      );
      return true;
    } on lifecycle.UnsupportedLifecycleProtocolVersion catch (e) {
      _logger.log(
        BlueyLogLevel.warn,
        'bluey.server.lifecycle',
        'unsupported lifecycle protocol version — dropping',
        data: {'clientId': clientId, 'version': e.version},
      );
      return true;
    }

    // Notify that this central has identified itself as a Bluey peer.
    // Fires for BOTH heartbeats and disconnect commands so that a
    // disconnect from an un-tracked client still tracks them first (so the
    // disconnection event has a client to remove).
    onPeerIdentified?.call(clientId, message.senderId);

    switch (message) {
      case lifecycle.CourtesyDisconnect():
        _logger.log(
          BlueyLogLevel.info,
          'bluey.server.lifecycle',
          'disconnect command received',
          data: {'clientId': clientId},
        );
        cancelTimer(clientId);
        onClientGone(clientId);
      case lifecycle.Heartbeat():
        _logger.log(
          BlueyLogLevel.debug,
          'bluey.server.lifecycle',
          'heartbeat received',
          data: {'clientId': clientId},
        );
        _resetTimer(clientId);
    }

    return true;
  }

  /// Handles a read request to a control service characteristic.
  /// Returns true if the request was handled (caller should not forward it).
  bool handleReadRequest(platform.PlatformReadRequest req) {
    final uuid = req.characteristicUuid.toLowerCase();

    if (uuid == lifecycle.serverIdCharUuid) {
      _platform.respondToReadRequest(
        req.requestId,
        platform.PlatformGattStatus.success,
        lifecycle.lifecycleCodec.encodeAdvertisedIdentity(_serverId),
      );
      return true;
    }

    if (!lifecycle.isControlServiceCharacteristic(uuid)) {
      return false;
    }

    final interval = _interval ?? lifecycle.defaultLifecycleInterval;
    _platform.respondToReadRequest(
      req.requestId,
      platform.PlatformGattStatus.success,
      lifecycle.encodeInterval(interval),
    );

    return true;
  }

  /// Cancels the heartbeat timer for a specific client and clears any
  /// pending-request state. Removes the client entirely from tracking.
  void cancelTimer(String clientId) {
    _clients.remove(clientId)?.timer?.cancel();
  }

  /// Treats any incoming activity from [clientId] as liveness evidence,
  /// refreshing an existing per-client timer so a busy lifecycle client
  /// isn't disconnected while its user-service traffic keeps flowing.
  ///
  /// Only clients that have previously identified themselves via a
  /// heartbeat write are tracked — activity from a non-lifecycle
  /// central (e.g. a generic BLE app reading a hosted service) is
  /// ignored so we don't spuriously fire [onClientGone] for a client
  /// we never promised to track.
  ///
  /// No-op if lifecycle is disabled (interval is null).
  void recordActivity(String clientId) {
    if (_interval == null) return;
    if (!_clients.containsKey(clientId)) {
      _logger.log(
        BlueyLogLevel.trace,
        'bluey.server.lifecycle',
        'recordActivity ignored (untracked client)',
        data: {'clientId': clientId},
      );
      return;
    }
    _resetTimer(clientId);
  }

  /// Marks that the server has accepted a request from [clientId] and
  /// owes a response. Adds [requestId] to the client's pending-request
  /// set and pauses the client's heartbeat-timeout timer until all
  /// pending requests for the client have completed.
  ///
  /// No-op for untracked clients (no prior heartbeat). Lifecycle policy
  /// is opt-in: a generic BLE central reading a hosted service must not
  /// be implicitly tracked as a Bluey peer.
  ///
  /// No-op if lifecycle is disabled (interval is null).
  void requestStarted(String clientId, int requestId) {
    if (_interval == null) return;
    final state = _clients[clientId];
    if (state == null) return;
    _logger.log(
      BlueyLogLevel.debug,
      'bluey.server.lifecycle',
      'requestStarted',
      data: {'clientId': clientId, 'requestId': requestId},
    );
    final wasIdle = state.pendingRequests.isEmpty;
    state.pendingRequests.add(requestId);
    if (wasIdle) {
      // Transition from no-pending-requests to one-pending — the
      // timer is about to be paused by _resetTimer. Diagnostic event
      // fires once per pause edge, not on every subsequent request.
      _events?.emit(
        LifecyclePausedForPendingRequestEvent(
          clientId: clientId,
          source: 'LifecycleServer',
        ),
      );
    }
    _resetTimer(clientId);
  }

  /// Marks a previously-started request as complete. If the client has
  /// no further pending requests, restarts the heartbeat-timeout timer
  /// with a fresh interval (treated as activity).
  ///
  /// Idempotent: completing an unknown id is a no-op.
  ///
  /// No-op if lifecycle is disabled (interval is null).
  void requestCompleted(String clientId, int requestId) {
    if (_interval == null) return;
    final state = _clients[clientId];
    if (state == null) return;
    if (!state.pendingRequests.remove(requestId)) return;
    _logger.log(
      BlueyLogLevel.debug,
      'bluey.server.lifecycle',
      'requestEnded',
      data: {'clientId': clientId, 'requestId': requestId},
    );
    if (state.pendingRequests.isEmpty) {
      _resetTimer(clientId);
    }
  }

  /// Cancels all heartbeat timers and clears all per-client state.
  void dispose() {
    for (final state in _clients.values) {
      state.timer?.cancel();
    }
    _clients.clear();
  }

  void _resetTimer(String clientId) {
    final interval = _interval;
    if (interval == null) return;

    final state = _clients.putIfAbsent(clientId, _ClientLiveness.new);
    state.timer?.cancel();

    if (state.pendingRequests.isNotEmpty) {
      // Paused while pending — see _ClientLiveness doc.
      state.timer = null;
      return;
    }

    state.timer = Timer(interval, () {
      _logger.log(
        BlueyLogLevel.warn,
        'bluey.server.lifecycle',
        'client gone',
        data: {'clientId': clientId},
      );
      _clients.remove(clientId);
      _events?.emit(
        ClientLifecycleTimeoutEvent(
          clientId: clientId,
          source: 'LifecycleServer',
        ),
      );
      onClientGone(clientId);
    });
  }
}

/// Per-client liveness state: a (possibly paused) heartbeat-timeout timer
/// and the set of platform request IDs currently pending a server response.
///
/// While [pendingRequests] is non-empty, [timer] is null (paused) — the
/// client is demonstrably engaged with the server and must not be declared
/// gone. Map-key membership in `_clients` is the unambiguous "tracked"
/// signal.
class _ClientLiveness {
  Timer? timer;
  final Set<int> pendingRequests = {};
}
