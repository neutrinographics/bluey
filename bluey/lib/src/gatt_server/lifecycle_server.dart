import 'dart:async';
import 'dart:typed_data';

import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;

import '../event_bus.dart';
import '../events.dart';
import '../lifecycle.dart' as lifecycle;
import '../log/bluey_logger.dart';
import '../log/log_level.dart';
import '../peer/server_id.dart';
import '../shared/error_translation.dart';
import '../shared/exceptions.dart';
import 'client_address.dart';

/// Server-side lifecycle management.
///
/// Handles the control service (heartbeat monitoring, interval reads) and
/// detects client disconnection via heartbeat timeouts. Internal to the
/// GATT Server bounded context.
class LifecycleServer {
  final platform.BlueyPlatform _platform;
  final Duration? _interval;
  final ServerId _serverId;

  /// Called when the heartbeat silence timer fires (no heartbeat received
  /// within the configured interval). On authoritative platforms (e.g.
  /// Android) the domain layer treats this as advisory; on inferring
  /// platforms (e.g. iOS) it is the primary disconnect signal.
  ///
  /// Distinct from [onExplicitDisconnect], which is called on receipt of
  /// a courtesy-disconnect command — always a definitive disconnect.
  final void Function(ClientAddress clientAddress) onClientGone;

  /// Called on receipt of a courtesy-disconnect write command from a
  /// connected Bluey peer. Unlike [onClientGone] (silence timeout), a
  /// courtesy disconnect is always a definitive signal regardless of the
  /// platform's [Capabilities.reportsCentralDisconnects] value.
  ///
  /// When null, the silence-timeout handler ([onClientGone]) is used for
  /// both paths, preserving the pre-I338 behaviour. Non-null callers
  /// (post-I338 [BlueyServer]) should pass `_handleClientDisconnected` so
  /// the two paths are handled independently.
  final void Function(ClientAddress clientAddress)? onExplicitDisconnect;

  final void Function(ClientAddress clientAddress, ServerId senderId)? onPeerIdentified;
  final BlueyLogger _logger;
  final EventPublisher? _events;

  bool _controlServiceAdded = false;
  final Map<ClientAddress, _ClientLiveness> _clients = {};

  LifecycleServer({
    required platform.BlueyPlatform platformApi,
    required Duration? interval,
    required ServerId serverId,
    required this.onClientGone,
    required BlueyLogger logger,
    this.onExplicitDisconnect,
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

    final clientAddress = ClientAddress(req.centralId);

    final lifecycle.LifecycleMessage message;
    try {
      message = lifecycle.lifecycleCodec.decodeMessage(req.value);
    } on lifecycle.MalformedLifecycleMessage catch (e) {
      _logger.log(
        BlueyLogLevel.warn,
        'bluey.server.lifecycle',
        'malformed lifecycle write — dropping',
        data: {'clientId': clientAddress.toString(), 'reason': e.reason},
      );
      return true;
    } on lifecycle.UnsupportedLifecycleProtocolVersion catch (e) {
      _logger.log(
        BlueyLogLevel.warn,
        'bluey.server.lifecycle',
        'unsupported lifecycle protocol version — dropping',
        data: {'clientId': clientAddress.toString(), 'version': e.version},
      );
      return true;
    }

    // Notify that this central has identified itself as a Bluey peer.
    // Fires for BOTH heartbeats and disconnect commands so that a
    // disconnect from an un-tracked client still tracks them first (so the
    // disconnection event has a client to remove).
    onPeerIdentified?.call(clientAddress, message.senderId);

    switch (message) {
      case lifecycle.CourtesyDisconnect():
        _logger.log(
          BlueyLogLevel.info,
          'bluey.server.lifecycle',
          'disconnect command received',
          data: {'clientId': clientAddress.toString()},
        );
        cancelTimer(clientAddress);
        // A courtesy-disconnect write is an explicit, definitive disconnect
        // signal. Route through `onExplicitDisconnect` when provided so the
        // domain layer can treat it differently from a heartbeat silence
        // (which is advisory on authoritative platforms — see I338).
        // Falls back to `onClientGone` when the caller passes no separate
        // handler (preserves pre-I338 behaviour for callers that haven't
        // been updated yet).
        (onExplicitDisconnect ?? onClientGone)(clientAddress);
      case lifecycle.Heartbeat():
        _logger.log(
          BlueyLogLevel.debug,
          'bluey.server.lifecycle',
          'heartbeat received',
          data: {'clientId': clientAddress.toString()},
        );
        _resetTimer(clientAddress);
    }

    return true;
  }

  /// Handles a read request to a control service characteristic.
  /// Returns true if the request was handled (caller should not forward it).
  bool handleReadRequest(platform.PlatformReadRequest req) {
    final uuid = req.characteristicUuid.toLowerCase();

    if (uuid == lifecycle.serverIdCharUuid) {
      _respondAndContain(
        req: req,
        branch: 'serverId',
        value: lifecycle.lifecycleCodec.encodeAdvertisedIdentity(_serverId),
      );
      return true;
    }

    if (!lifecycle.isControlServiceCharacteristic(uuid)) {
      return false;
    }

    final interval = _interval ?? lifecycle.defaultLifecycleInterval;
    _respondAndContain(
      req: req,
      branch: 'interval',
      value: lifecycle.encodeInterval(interval),
    );

    return true;
  }

  /// Issues a fire-and-forget read response and contains failures.
  ///
  /// `RespondNotFoundException` (translated from the platform's typed
  /// not-found code) is the *expected race* — duplicate response on the
  /// Dart side (see I322); logged at warn. Any other failure is
  /// unexpected and logged at error so it shows up in observability.
  ///
  /// Always returns synchronously (the underlying respond future is
  /// `unawaited` to preserve the synchronous `handleReadRequest`
  /// contract). The trace log on entry carries `requestId`,
  /// `characteristicUuid`, and `branch` so a future maintainer
  /// investigating I322 can correlate by id.
  void _respondAndContain({
    required platform.PlatformReadRequest req,
    required String branch,
    required Uint8List value,
  }) {
    _logger.log(
      BlueyLogLevel.trace,
      'bluey.server.lifecycle',
      'respond entered',
      data: {
        'requestId': req.requestId,
        'characteristicUuid': req.characteristicUuid,
        'branch': branch,
      },
    );
    unawaited(
      _platform
          .respondToReadRequest(
            req.requestId,
            platform.PlatformGattStatus.success,
            value,
          )
          .then(
            (_) {},
            onError: (Object e, StackTrace st) {
              final translated = translatePlatformException(
                e,
                operation: 'respondToReadRequest',
              );
              if (translated is RespondNotFoundException) {
                _logger.log(
                  BlueyLogLevel.warn,
                  'bluey.server.lifecycle',
                  'respond skipped — request id not found '
                      '(likely duplicate response; see I322)',
                  data: {
                    'requestId': req.requestId,
                    'characteristicUuid': req.characteristicUuid,
                    'branch': branch,
                  },
                  errorCode: 'respond-not-found',
                );
                return;
              }
              _logger.log(
                BlueyLogLevel.error,
                'bluey.server.lifecycle',
                'respond failed unexpectedly',
                data: {
                  'requestId': req.requestId,
                  'characteristicUuid': req.characteristicUuid,
                  'branch': branch,
                  'exception': translated.runtimeType.toString(),
                },
                errorCode: translated.runtimeType.toString(),
              );
            },
          ),
    );
  }

  /// Cancels the heartbeat timer for a specific client and clears any
  /// pending-request state. Removes the client entirely from tracking.
  void cancelTimer(ClientAddress clientAddress) {
    _clients.remove(clientAddress)?.timer?.cancel();
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
  void recordActivity(ClientAddress clientAddress) {
    if (_interval == null) return;
    if (!_clients.containsKey(clientAddress)) {
      _logger.log(
        BlueyLogLevel.trace,
        'bluey.server.lifecycle',
        'recordActivity ignored (untracked client)',
        data: {'clientId': clientAddress.toString()},
      );
      return;
    }
    _resetTimer(clientAddress);
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
  void requestStarted(ClientAddress clientAddress, int requestId) {
    if (_interval == null) return;
    final state = _clients[clientAddress];
    if (state == null) return;
    _logger.log(
      BlueyLogLevel.debug,
      'bluey.server.lifecycle',
      'requestStarted',
      data: {'clientId': clientAddress.toString(), 'requestId': requestId},
    );
    final wasIdle = state.pendingRequests.isEmpty;
    state.pendingRequests.add(requestId);
    if (wasIdle) {
      // Transition from no-pending-requests to one-pending — the
      // timer is about to be paused by _resetTimer. Diagnostic event
      // fires once per pause edge, not on every subsequent request.
      _events?.emit(
        LifecyclePausedForPendingRequestEvent(
          clientAddress: clientAddress,
          source: 'LifecycleServer',
        ),
      );
    }
    _resetTimer(clientAddress);
  }

  /// Marks a previously-started request as complete. If the client has
  /// no further pending requests, restarts the heartbeat-timeout timer
  /// with a fresh interval (treated as activity).
  ///
  /// Idempotent: completing an unknown id is a no-op.
  ///
  /// No-op if lifecycle is disabled (interval is null).
  void requestCompleted(ClientAddress clientAddress, int requestId) {
    if (_interval == null) return;
    final state = _clients[clientAddress];
    if (state == null) return;
    if (!state.pendingRequests.remove(requestId)) return;
    _logger.log(
      BlueyLogLevel.debug,
      'bluey.server.lifecycle',
      'requestEnded',
      data: {'clientId': clientAddress.toString(), 'requestId': requestId},
    );
    if (state.pendingRequests.isEmpty) {
      _resetTimer(clientAddress);
    }
  }

  /// Cancels all heartbeat timers and clears all per-client state.
  void dispose() {
    for (final state in _clients.values) {
      state.timer?.cancel();
    }
    _clients.clear();
  }

  void _resetTimer(ClientAddress clientAddress) {
    final interval = _interval;
    if (interval == null) return;

    final state = _clients.putIfAbsent(clientAddress, _ClientLiveness.new);
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
        data: {'clientId': clientAddress.toString()},
      );
      _clients.remove(clientAddress);
      _events?.emit(
        ClientLifecycleTimeoutEvent(
          clientAddress: clientAddress,
          source: 'LifecycleServer',
        ),
      );
      onClientGone(clientAddress);
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
