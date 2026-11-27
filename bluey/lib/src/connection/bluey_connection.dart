/// [LinkGattClient], the GATT client of one link, with the remote attributes
/// it discovers.
///
/// The file keeps its old name, which no longer says what it holds, because
/// it leaves for the GATT Client context with that context's slice, and a
/// rename now would only be undone by that move.
library;

import 'dart:async';
import 'dart:typed_data';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;

import '../shared/domain/device_address.dart';
import '../shared/application/event_publisher.dart';
import '../events.dart';
import '../gatt_client/gatt.dart';
import '../shared/infrastructure/bluey_logger.dart';
import '../shared/application/log_level.dart';
import '../shared/domain/either.dart';
import '../features/connection/application/link_session.dart';
import '../features/connection/domain/link_end.dart';
import '../shared/characteristic_properties.dart';
import '../shared/error_translation.dart';
import '../shared/exceptions.dart';
import '../shared/domain/uuid.dart';
import 'lifecycle_client.dart';
import 'value_objects/attribute_handle.dart';

/// Thin wrapper over [withErrorTranslation] preserved for call-site
/// readability — every public GATT op on [LinkGattClient] /
/// [BlueyRemoteCharacteristic] / [BlueyRemoteDescriptor] flows through
/// this so the lifecycle accounting and exception translation stay in
/// one place. See [withErrorTranslation] for the full hook contract.
Future<T> _runGattOp<T>(
  DeviceAddress deviceAddress,
  String operation,
  Future<T> Function() body, {
  LifecycleClient? lifecycleClient,
}) {
  return withErrorTranslation(
    body,
    operation: operation,
    address: deviceAddress.value,
    lifecycleClient: lifecycleClient,
  );
}

/// Wraps [_runGattOp] with start / complete / failed log lines and a
/// stopwatch. Every public GATT op on the Connection / Characteristic /
/// Descriptor surface that wants per-op tracing goes through this so
/// the three log lines stay in lock-step.
///
/// [startDetail] — extra context appended after `deviceId=…` in both
/// the start and failed messages (e.g. `'char=$uuid, bytes=N'`).
/// [completeDetail] — optional result-derived suffix for the complete
/// message (e.g. `'negotiated=$mtu'`).
Future<T> _loggedGattOp<T>({
  required DeviceAddress deviceAddress,
  required String op,
  required Future<T> Function() body,
  String startDetail = '',
  String Function(T result)? completeDetail,
  LifecycleClient? lifecycleClient,
  BlueyLogger? logger,
}) async {
  logger?.log(
    BlueyLogLevel.debug,
    'bluey.gatt',
    '$op start',
    data: {
      'deviceId': deviceAddress.toString(),
      'op': op,
      if (startDetail.isNotEmpty) 'detail': startDetail,
    },
  );
  final sw = Stopwatch()..start();
  try {
    final result = await _runGattOp(
      deviceAddress,
      op,
      body,
      lifecycleClient: lifecycleClient,
    );
    final detail = completeDetail?.call(result);
    logger?.log(
      BlueyLogLevel.debug,
      'bluey.gatt',
      '$op complete',
      data: {
        'deviceId': deviceAddress.toString(),
        'op': op,
        'durationMs': sw.elapsedMilliseconds,
        if (detail != null && detail.isNotEmpty) 'detail': detail,
      },
    );
    return result;
  } catch (e) {
    logger?.log(
      BlueyLogLevel.error,
      'bluey.gatt',
      '$op failed',
      data: {
        'deviceId': deviceAddress.toString(),
        'op': op,
        'exception': e.runtimeType.toString(),
        'durationMs': sw.elapsedMilliseconds,
        if (e is GattOperationFailedException) 'status': e.status,
        if (startDetail.isNotEmpty) 'detail': startDetail,
      },
      errorCode: e.runtimeType.toString(),
    );
    rethrow;
  }
}

/// One link's GATT client: discovery and its cache and the Service Changed
/// handler, over the link a [LinkSession] runs.
///
/// It keeps no copy of the link's state. It asks the session whether the
/// link is usable, runs every platform call that needs the link through
/// [LinkSession.whileUp], so the link's end answers a call at once, and
/// releases its caches and streams when the session says the link ended.
class LinkGattClient {
  final platform.BlueyPlatform _platform;
  final LinkSession _session;
  final BlueyLogger _logger;

  // Read only while the link is up: an ended link's id may name the next.
  String get _connectionId => _session.id.value;

  DeviceAddress get _device => _session.link.device;

  final StreamController<List<RemoteService>> _servicesChangesController =
      StreamController<List<RemoteService>>.broadcast();

  StreamSubscription? _platformServiceChangesSubscription;

  List<BlueyRemoteService>? _cachedServices;

  // Failed with AttributeHandleInvalidatedException on Service Changed, so no
  // caller waits on a stale handle.
  final Set<Completer<Object?>> _pendingGattOpAborters = {};

  /// The exception an ended link is thrown as, since an app catches what the
  /// edge translates the end to.
  final BlueyException Function(LinkEnd end) _endAsException;

  /// Where GATT-op events go; none are emitted without it.
  final EventPublisher? _events;

  /// Starts following Service Changed for the session's link at once; it is
  /// released when the link ends. An ended link is thrown as
  /// [endAsException] answers it.
  LinkGattClient({
    required platform.BlueyPlatform platformInstance,
    required LinkSession session,
    required BlueyLogger logger,
    required BlueyException Function(LinkEnd end) endAsException,
    EventPublisher? events,
  }) : _platform = platformInstance,
       _session = session,
       _logger = logger,
       _endAsException = endAsException,
       _events = events {
    final connectionId = _connectionId;

    // The native side has already dropped its handles: so must we.
    _platformServiceChangesSubscription = _platform.serviceChanges
        .where((id) => id == connectionId)
        .listen((_) {
          _onServiceChanged();
        });

    _session.onEnd(_release);
  }

  /// Everything that lives as long as the link, let go when it ends.
  ///
  /// Nothing here is awaited: the session runs releases one after another,
  /// and a cancel awaited here would hold the next one up for nothing.
  void _release(LinkEnd end) {
    unawaited(_platformServiceChangesSubscription?.cancel());
    _platformServiceChangesSubscription = null;

    // An outage makes the connection stale: the stream says so before it
    // closes (Convention 3).
    if (end is EndedByRadioOutage) {
      _servicesChangesController.addError(_endAsException(end));
    }
    unawaited(_servicesChangesController.close());

    final cached = _cachedServices;
    _cachedServices = null;
    for (final service in cached ?? const <BlueyRemoteService>[]) {
      unawaited(service.dispose());
    }
  }

  /// The exception a radio outage left, or null when the link ended any
  /// other way or is still up.
  BlueyException? get _staleness {
    final end = _session.link.end;
    return end is EndedByRadioOutage ? _endAsException(end) : null;
  }

  /// Throws [StaleHandleException] once a radio outage has ended the link.
  void _ensureValid() {
    final stale = _staleness;
    if (stale != null) throw stale;
  }

  /// Throws the link's end, as the exception an app catches, unless the
  /// link is up: [StaleHandleException] after an outage and
  /// [DisconnectedException] otherwise.
  ///
  /// Called at the top of every public GATT-op method, and from
  /// `BlueyRemoteCharacteristic` / `BlueyRemoteDescriptor` via the closure
  /// threaded through their constructors, so a dead link never lets a raw
  /// platform exception escape.
  void _ensureConnected() {
    if (_session.link.endInSight case final end?) throw _endAsException(end);
  }

  /// Runs one throwing platform call so that the link's end answers it at once.
  Future<T> _overLink<T>(Future<T> Function() call) async {
    final answer = await _session.whileUp<_Raised, T>(() async {
      try {
        return Right(await call());
      } catch (error, stack) {
        return Left(_Raised(error, stack));
      }
    }, orEnd: (end) => _Raised(_endAsException(end), StackTrace.current));
    return answer.fold(
      (raised) => Error.throwWithStackTrace(raised.error, raised.stack),
      (value) => value,
    );
  }

  /// Wraps [body] so that a Service Changed event fired while the call
  /// is in flight surfaces the typed [AttributeHandleInvalidatedException]
  /// on the original future, even if the platform layer never produces
  /// a response. The aborter token is registered for the lifetime of the
  /// platform call; whichever of (platform completion, abort) fires
  /// first wins.
  Future<T> _trackInFlight<T>(Future<T> Function() body) {
    final aborter = Completer<Object?>();
    _pendingGattOpAborters.add(aborter);
    body().then(
      (value) {
        if (!aborter.isCompleted) aborter.complete(value);
      },
      onError: (Object error, StackTrace stack) {
        if (!aborter.isCompleted) aborter.completeError(error, stack);
      },
    );
    return aborter.future
        .whenComplete(() => _pendingGattOpAborters.remove(aborter))
        .then((value) => value as T);
  }

  /// Service Changed handler. Drops the cached service tree and aborts
  /// every in-flight op. Idempotent: a second event with no in-flight
  /// ops is a no-op.
  ///
  /// After clearing the cache, kicks off a fresh re-discovery and emits
  /// the new service list on [servicesChanges] for proactive consumers
  /// (e.g. the lifecycle client refreshing its heartbeat-char handle).
  void _onServiceChanged() {
    _logger.log(
      BlueyLogLevel.warn,
      'bluey.connection',
      'Service Changed received',
      data: {
        'deviceId': _device.toString(),
        'inFlight': _pendingGattOpAborters.length,
      },
    );
    _cachedServices = null;
    _logger.log(
      BlueyLogLevel.warn,
      'bluey.connection',
      'service cache cleared, re-discovery pending',
      data: {'deviceId': _device.toString()},
    );
    if (_pendingGattOpAborters.isNotEmpty) {
      final aborters = _pendingGattOpAborters.toList(growable: false);
      _pendingGattOpAborters.clear();
      for (final aborter in aborters) {
        if (!aborter.isCompleted) {
          aborter.completeError(AttributeHandleInvalidatedException());
        }
      }
    }

    // Eagerly re-discover so consumers get a fresh service tree without
    // having to call services() themselves. Fire-and-forget; errors
    // surface as a stream error to subscribers (rather than an
    // unhandled future).
    services()
        .then((fresh) {
          if (_servicesChangesController.isClosed) return;
          _servicesChangesController.add(fresh);
        })
        .catchError((Object e, StackTrace st) {
          if (_servicesChangesController.isClosed) return;
          _servicesChangesController.addError(e, st);
        });
  }

  /// Each re-discovered service tree, as `servicesChanges` gives it.
  Stream<List<RemoteService>> get servicesChanges =>
      Stream<List<RemoteService>>.multi((controller) {
        // Convention 3 (non-enum terminal): late subscribers after
        // an outage see addError(StaleHandleException) + close so
        // their `onError` mirrors what the corresponding sync getter
        // would throw (Convention 6).
        final stale = _staleness;
        if (stale != null) {
          controller.addError(stale);
          controller.close();
          return;
        }
        // Replay the currently-discovered services (or the empty list
        // if discovery hasn't run yet) before forwarding live events.
        controller.add(_cachedServices ?? const <RemoteService>[]);
        final sub = _servicesChangesController.stream.listen(
          controller.add,
          onError: controller.addError,
          onDone: controller.close,
        );
        controller.onCancel = sub.cancel;
      }, isBroadcast: true);

  /// The one discovered service with [uuid], which every Connection's `service` answers.
  RemoteService service(UUID uuid) {
    _ensureValid();
    if (_cachedServices == null) {
      throw ServiceNotFoundException(uuid);
    }

    final matches = <RemoteService>[
      for (final svc in _cachedServices!)
        if (svc.uuid == uuid) svc,
    ];
    if (matches.isEmpty) {
      throw ServiceNotFoundException(uuid);
    }
    if (matches.length > 1) {
      throw AmbiguousAttributeException(
        uuid,
        matches.length,
        attributeKind: 'service',
      );
    }
    return matches.single;
  }

  /// Discovers the link's services, which makes the link ready.
  Future<List<RemoteService>> services({bool cache = false}) async {
    _ensureValid();
    _ensureConnected();
    if (cache && _cachedServices != null) {
      return _cachedServices!;
    }

    _logger.log(
      BlueyLogLevel.info,
      'bluey.connection',
      'services discovery started',
      data: {'deviceId': _device.toString()},
    );
    _events?.emit(
      DiscoveringServicesEvent(
        deviceAddress: _device,
        source: 'BlueyConnection',
      ),
    );
    final stopwatch = Stopwatch()..start();
    final connectionId = _connectionId;
    final platformServices = await _trackInFlight(
      () => _runGattOp(
        _device,
        'discoverServices',
        () => _overLink(() => _platform.discoverServices(connectionId)),
      ),
    );
    _cachedServices = platformServices.map((ps) => _mapService(ps)).toList();

    _logger.log(
      BlueyLogLevel.info,
      'bluey.connection',
      'services discovery resolved',
      data: {
        'deviceId': _device.toString(),
        'count': _cachedServices!.length,
        'durationMs': stopwatch.elapsedMilliseconds,
      },
    );
    _events?.emit(
      ServicesDiscoveredEvent(
        deviceAddress: _device,
        serviceCount: _cachedServices!.length,
        source: 'BlueyConnection',
      ),
    );

    // Trace-level enumeration of every discovered service UUID. Useful
    // for debugging UUID-canonicalization mismatches (e.g. peer-detection
    // failing because the lifecycle control service UUID arrives in a
    // different form than expected).
    if (_cachedServices!.isNotEmpty) {
      _logger.log(
        BlueyLogLevel.trace,
        'bluey.connection',
        'services discovered',
        data: {
          'deviceId': _device.toString(),
          'uuids': _cachedServices!.map((s) => s.uuid.toString()).toList(),
        },
      );
    }

    _session.servicesDiscovered();

    return _cachedServices!;
  }

  /// Whether the link has a service with [uuid].
  Future<bool> hasService(UUID uuid) async {
    _ensureValid();
    final svcs = await services(cache: true);
    return svcs.any((s) => s.uuid == uuid);
  }

  BlueyRemoteService _mapService(platform.PlatformService ps) {
    return BlueyRemoteService(
      platform: _platform,
      connectionId: _connectionId,
      uuid: UUID(ps.uuid),
      isPrimary: ps.isPrimary,
      characteristics:
          ps.characteristics.map((pc) => _mapCharacteristic(pc)).toList(),
      includedServices:
          ps.includedServices.map((is_) => _mapService(is_)).toList(),
    );
  }

  BlueyRemoteCharacteristic _mapCharacteristic(
    platform.PlatformCharacteristic pc,
  ) {
    // No lifecycle client: the peer protocol is PeerConnection's alone.
    final characteristicHandle = AttributeHandle(pc.handle);
    return BlueyRemoteCharacteristic(
      platform: _platform,
      connectionId: _connectionId,
      deviceAddress: _device,
      uuid: UUID(pc.uuid),
      handle: characteristicHandle,
      properties: CharacteristicProperties(
        canRead: pc.properties.canRead,
        canWrite: pc.properties.canWrite,
        canWriteWithoutResponse: pc.properties.canWriteWithoutResponse,
        canNotify: pc.properties.canNotify,
        canIndicate: pc.properties.canIndicate,
      ),
      descriptors:
          pc.descriptors
              .map((pd) => _mapDescriptor(pd, characteristicHandle))
              .toList(),
      ensureConnected: _ensureConnected,
      trackInFlight: _trackInFlight,
      overLink: _overLink,
      logger: _logger,
      events: _events,
    );
  }

  BlueyRemoteDescriptor _mapDescriptor(
    platform.PlatformDescriptor pd,
    AttributeHandle characteristicHandle,
  ) {
    return BlueyRemoteDescriptor(
      platform: _platform,
      connectionId: _connectionId,
      deviceAddress: _device,
      uuid: UUID(pd.uuid),
      handle: AttributeHandle(pd.handle),
      characteristicHandle: characteristicHandle,
      ensureConnected: _ensureConnected,
      trackInFlight: _trackInFlight,
      overLink: _overLink,
      logger: _logger,
    );
  }
}

/// What a platform call raised, carried across [LinkSession.whileUp] as a
/// value so it is raised again, with its own stack, at the caller.
final class _Raised {
  const _Raised(this.error, this.stack);

  final Object error;
  final StackTrace stack;
}

/// Internal implementation of [RemoteService].
class BlueyRemoteService implements RemoteService {
  @override
  final UUID uuid;

  @override
  final bool isPrimary;

  /// All characteristics in this service. Stored as the full discovered
  /// list; the public surface is [characteristics] (filterable) and
  /// [characteristic] (singular, throws on ambiguity).
  final List<RemoteCharacteristic> _characteristics;

  @override
  final List<RemoteService> includedServices;

  BlueyRemoteService({
    required platform.BlueyPlatform platform,
    required String connectionId,
    required this.uuid,
    required this.isPrimary,
    required List<RemoteCharacteristic> characteristics,
    required this.includedServices,
  }) : _characteristics = characteristics;

  @override
  List<RemoteCharacteristic> characteristics({UUID? uuid}) {
    if (uuid == null) return List.unmodifiable(_characteristics);
    return List.unmodifiable(_characteristics.where((c) => c.uuid == uuid));
  }

  @override
  RemoteCharacteristic characteristic(UUID uuid) {
    final matches = _characteristics.where((c) => c.uuid == uuid).toList();
    if (matches.isEmpty) {
      throw CharacteristicNotFoundException(uuid);
    }
    if (matches.length > 1) {
      throw AmbiguousAttributeException(
        uuid,
        matches.length,
        attributeKind: 'characteristic',
      );
    }
    return matches.single;
  }

  /// Releases per-characteristic resources (notification subscriptions
  /// and broadcast controllers) for every characteristic in this
  /// service. Called by [LinkGattClient] when its link ends so
  /// controllers don't persist across connect/disconnect cycles.
  /// Included services are disposed recursively. Idempotent.
  Future<void> dispose() async {
    for (final char in _characteristics) {
      if (char is BlueyRemoteCharacteristic) {
        await char.dispose();
      }
    }
    for (final included in includedServices) {
      if (included is BlueyRemoteService) {
        await included.dispose();
      }
    }
  }
}

/// Type signature of the in-flight aborter wrapper threaded from
/// [LinkGattClient] into characteristics and descriptors. Wraps a
/// platform-call body so a Service Changed event fired mid-flight
/// causes the returned future to fail with
/// [AttributeHandleInvalidatedException].
typedef _TrackInFlight = Future<T> Function<T>(Future<T> Function() body);

Future<T> _passthroughInFlight<T>(Future<T> Function() body) => body();

/// Internal implementation of [RemoteCharacteristic].
class BlueyRemoteCharacteristic implements RemoteCharacteristic {
  final platform.BlueyPlatform _platform;
  final String _connectionId;
  final DeviceAddress _deviceAddress;
  final LifecycleClient? Function() _lifecycle;
  final void Function() _ensureConnected;
  final _TrackInFlight _trackInFlight;
  final _TrackInFlight _overLink;
  final BlueyLogger? _logger;
  final EventPublisher? _events;

  @override
  final UUID uuid;

  @override
  final AttributeHandle handle;

  @override
  final CharacteristicProperties properties;

  /// All descriptors of this characteristic. Stored as the full
  /// discovered list; the public surface is [descriptors] (filterable)
  /// and [descriptor] (singular, throws on ambiguity).
  final List<RemoteDescriptor> _descriptors;

  StreamSubscription? _notificationSubscription;
  StreamController<Uint8List>? _notificationController;

  /// [lifecycleClient] is a getter rather than a value because the
  /// characteristic may be constructed before the connection upgrades
  /// to the Bluey lifecycle protocol. Reading the field at call time
  /// ensures user ops on characteristics built during initial service
  /// discovery still feed activity / failure signals into the
  /// lifecycle once it starts.
  ///
  /// [ensureConnected] is the connection's pre-flight gate.
  /// Invoked at the top of every public op; throws
  /// [DisconnectedException] if the owning connection is no longer
  /// in `linked` or `ready`. Defaults to a no-op for tests that
  /// build a characteristic without a parent connection.
  ///
  /// [overLink] runs each platform call over the parent's link, so the
  /// link's end answers it at once; a pass-through by default.
  BlueyRemoteCharacteristic({
    required platform.BlueyPlatform platform,
    required String connectionId,
    required DeviceAddress deviceAddress,
    required this.uuid,
    required this.handle,
    required this.properties,
    required List<RemoteDescriptor> descriptors,
    LifecycleClient? Function()? lifecycleClient,
    void Function()? ensureConnected,
    _TrackInFlight? trackInFlight,
    _TrackInFlight? overLink,
    BlueyLogger? logger,
    EventPublisher? events,
  }) : _platform = platform,
       _connectionId = connectionId,
       _deviceAddress = deviceAddress,
       _descriptors = descriptors,
       _lifecycle = lifecycleClient ?? (() => null),
       _ensureConnected = ensureConnected ?? (() {}),
       _trackInFlight = trackInFlight ?? _passthroughInFlight,
       _overLink = overLink ?? _passthroughInFlight,
       _logger = logger,
       _events = events;

  @override
  Future<Uint8List> read() async {
    _ensureConnected();
    if (!properties.canRead) {
      throw const OperationNotSupportedException('read');
    }
    final value = await _trackInFlight(
      () => _loggedGattOp(
        deviceAddress: _deviceAddress,
        op: 'readCharacteristic',
        startDetail: 'char=$uuid',
        body:
            () => _overLink(
              () => _platform.readCharacteristic(_connectionId, handle.value),
            ),
        completeDetail: (value) => 'char=$uuid, bytes=${value.length}',
        lifecycleClient: _lifecycle(),
        logger: _logger,
      ),
    );
    _events?.emit(
      CharacteristicReadEvent(
        deviceAddress: _deviceAddress,
        characteristicId: uuid,
        valueLength: value.length,
        source: 'BlueyRemoteCharacteristic',
      ),
    );
    return value;
  }

  @override
  Future<void> write(Uint8List value, {bool withResponse = true}) async {
    _ensureConnected();
    if (withResponse && !properties.canWrite) {
      throw const OperationNotSupportedException('write');
    }
    if (!withResponse && !properties.canWriteWithoutResponse) {
      throw const OperationNotSupportedException('writeWithoutResponse');
    }
    await _trackInFlight<void>(
      () => _loggedGattOp<void>(
        deviceAddress: _deviceAddress,
        op: 'writeCharacteristic',
        startDetail: 'char=$uuid, bytes=${value.length}',
        body:
            () => _overLink<void>(
              () => _platform.writeCharacteristic(
                _connectionId,
                handle.value,
                value,
                withResponse,
              ),
            ),
        completeDetail: (_) => 'char=$uuid',
        lifecycleClient: _lifecycle(),
        logger: _logger,
      ),
    );
    _events?.emit(
      CharacteristicWrittenEvent(
        deviceAddress: _deviceAddress,
        characteristicId: uuid,
        valueLength: value.length,
        withResponse: withResponse,
        source: 'BlueyRemoteCharacteristic',
      ),
    );
  }

  @override
  Stream<Uint8List> get notifications {
    _ensureConnected();
    if (!properties.canSubscribe) {
      throw const OperationNotSupportedException('notify');
    }

    // Create a new controller if needed
    if (_notificationController == null) {
      _notificationController = StreamController<Uint8List>.broadcast(
        onListen: _onFirstListen,
        onCancel: _onLastCancel,
      );
    }

    return _notificationController!.stream;
  }

  void _onFirstListen() {
    // Enable notifications on the platform. Fire-and-forget by design —
    // StreamController's onListen callback is synchronous. A platform
    // failure here (e.g. mid-op disconnect drained by the Android queue)
    // must surface on the notification stream so subscribers see it
    // instead of it becoming an unhandled async error.
    _runGattOp(
          _deviceAddress,
          'setNotification',
          () => _overLink<void>(
            () => _platform.setNotification(_connectionId, handle.value, true),
          ),
          lifecycleClient: _lifecycle(),
        )
        .then((_) {
          _events?.emit(
            NotificationSubscriptionEvent(
              deviceAddress: _deviceAddress,
              characteristicId: uuid,
              enabled: true,
              source: 'BlueyRemoteCharacteristic',
            ),
          );
        })
        .catchError((Object error) {
          _notificationController?.addError(error);
        });

    // Subscribe to platform notifications
    _notificationSubscription = _platform
        .notificationStream(_connectionId)
        .where((n) {
          // DA-02 — demux by handle when the platform attributes the
          // notification to a characteristic instance; duplicate-UUID
          // trees cannot be told apart by UUID alone. Handle-less
          // (legacy) notifications fall back to UUID matching.
          final notificationHandle = n.characteristicHandle;
          if (notificationHandle != null) {
            return notificationHandle == handle.value;
          }
          return n.characteristicUuid.toLowerCase() ==
              uuid.toString().toLowerCase();
        })
        .listen(
          (notification) {
            // Inbound notifications are demonstrable peer activity but
            // not user ops, so we record activity without the
            // start/end/failure wrapping used for outbound ops.
            _lifecycle()?.recordActivity();
            _notificationController?.add(notification.value);
            _events?.emit(
              NotificationReceivedEvent(
                deviceAddress: _deviceAddress,
                characteristicId: uuid,
                valueLength: notification.value.length,
                source: 'BlueyRemoteCharacteristic',
              ),
            );
          },
          onError: (error) {
            _notificationController?.addError(error);
          },
        );
  }

  void _onLastCancel() {
    // Disable notifications on the platform. Fire-and-forget; the last
    // subscriber has just cancelled, so there is no natural recipient for
    // errors. Swallow silently to keep teardown best-effort — a link-loss
    // race on shutdown is an expected condition, not a test failure.
    _runGattOp(
          _deviceAddress,
          'setNotification',
          () => _overLink<void>(
            () => _platform.setNotification(_connectionId, handle.value, false),
          ),
          lifecycleClient: _lifecycle(),
        )
        .then((_) {
          _events?.emit(
            NotificationSubscriptionEvent(
              deviceAddress: _deviceAddress,
              characteristicId: uuid,
              enabled: false,
              source: 'BlueyRemoteCharacteristic',
            ),
          );
        })
        .catchError((Object _) {});

    // Cancel subscription
    _notificationSubscription?.cancel();
    _notificationSubscription = null;
  }

  /// Releases this characteristic's notification resources. Called by
  /// the owning [BlueyRemoteService.dispose] when the connection is
  /// torn down. Cancels the platform notification subscription and
  /// closes the lazily-built broadcast controller. Idempotent and safe
  /// when no consumer ever subscribed (controller was never created).
  Future<void> dispose() async {
    final sub = _notificationSubscription;
    _notificationSubscription = null;
    await sub?.cancel();

    final controller = _notificationController;
    _notificationController = null;
    await controller?.close();
  }

  @override
  List<RemoteDescriptor> descriptors({UUID? uuid}) {
    if (uuid == null) return List.unmodifiable(_descriptors);
    return List.unmodifiable(_descriptors.where((d) => d.uuid == uuid));
  }

  @override
  RemoteDescriptor descriptor(UUID uuid) {
    final matches = _descriptors.where((d) => d.uuid == uuid).toList();
    if (matches.isEmpty) {
      throw CharacteristicNotFoundException(uuid);
    }
    if (matches.length > 1) {
      throw AmbiguousAttributeException(
        uuid,
        matches.length,
        attributeKind: 'descriptor',
      );
    }
    return matches.single;
  }
}

/// Internal implementation of [RemoteDescriptor].
class BlueyRemoteDescriptor implements RemoteDescriptor {
  final platform.BlueyPlatform _platform;
  final String _connectionId;
  final DeviceAddress _deviceAddress;
  final LifecycleClient? Function() _lifecycle;
  final void Function() _ensureConnected;
  final _TrackInFlight _trackInFlight;
  final _TrackInFlight _overLink;
  // ignore: unused_field
  final BlueyLogger? _logger;

  /// Handle of the parent characteristic. Threaded onto the wire
  /// alongside [handle] so native receivers can route descriptor ops
  /// through the same handle table used for the owning characteristic.
  final AttributeHandle _characteristicHandle;

  @override
  final UUID uuid;

  @override
  final AttributeHandle handle;

  /// [lifecycleClient] is a getter rather than a value: descriptors are
  /// constructed during service discovery, before the connection
  /// upgrades to the Bluey lifecycle protocol. See
  /// [BlueyRemoteCharacteristic] for the same pattern and reasoning.
  ///
  /// [ensureConnected] is the connection's pre-flight gate.
  /// Defaults to a no-op for tests that build a descriptor without a
  /// parent connection.
  ///
  /// [characteristicHandle] is the parent characteristic's handle; it
  /// rides on every descriptor op so native receivers can prefer
  /// handle-keyed lookup over UUID-keyed lookup.
  ///
  /// [overLink] runs each platform call over the parent's link, as for
  /// [BlueyRemoteCharacteristic].
  BlueyRemoteDescriptor({
    required platform.BlueyPlatform platform,
    required String connectionId,
    required DeviceAddress deviceAddress,
    required this.uuid,
    required this.handle,
    required AttributeHandle characteristicHandle,
    LifecycleClient? Function()? lifecycleClient,
    void Function()? ensureConnected,
    _TrackInFlight? trackInFlight,
    _TrackInFlight? overLink,
    BlueyLogger? logger,
  }) : _platform = platform,
       _connectionId = connectionId,
       _deviceAddress = deviceAddress,
       _characteristicHandle = characteristicHandle,
       _lifecycle = lifecycleClient ?? (() => null),
       _ensureConnected = ensureConnected ?? (() {}),
       _trackInFlight = trackInFlight ?? _passthroughInFlight,
       _overLink = overLink ?? _passthroughInFlight,
       _logger = logger;

  @override
  Future<Uint8List> read() async {
    _ensureConnected();
    return _trackInFlight(
      () => _runGattOp(
        _deviceAddress,
        'readDescriptor',
        () => _overLink(
          () => _platform.readDescriptor(
            _connectionId,
            _characteristicHandle.value,
            handle.value,
          ),
        ),
        lifecycleClient: _lifecycle(),
      ),
    );
  }

  @override
  Future<void> write(Uint8List value) async {
    _ensureConnected();
    return _trackInFlight<void>(
      () => _runGattOp(
        _deviceAddress,
        'writeDescriptor',
        () => _overLink<void>(
          () => _platform.writeDescriptor(
            _connectionId,
            _characteristicHandle.value,
            handle.value,
            value,
          ),
        ),
        lifecycleClient: _lifecycle(),
      ),
    );
  }
}
