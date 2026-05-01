import 'dart:async';

import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:meta/meta.dart';

import 'connection/bluey_connection.dart';
import 'connection/connection.dart';
import 'connection/lifecycle_client.dart';
import 'peer/peer_connection.dart';
import 'discovery/bluey_scanner.dart';
import 'discovery/device.dart';
import 'discovery/scanner.dart';
import 'event_bus.dart';
import 'events.dart';
import 'gatt_server/bluey_server.dart';
import 'gatt_server/server.dart';
import 'lifecycle.dart' as lifecycle;
import 'log/bluey_logger.dart';
import 'log/log_event.dart';
import 'log/log_level.dart';
import 'peer/bluey_peer.dart';
import 'peer/peer.dart';
import 'peer/peer_discovery.dart';
import 'peer/server_id.dart';
import 'platform/bluetooth_state.dart';
import 'shared/device_id_coercion.dart';
import 'shared/error_translation.dart';
import 'shared/exceptions.dart';
import 'shared/gatt_timeouts.dart';

export 'events.dart';
export 'discovery/scanner.dart';
export 'platform/bluetooth_state.dart';

/// The main entry point to Bluey.
///
/// This is the domain-layer facade that provides a clean API over the
/// platform-specific implementations. All BLE operations go through this class.
///
/// ## Usage
///
/// For most apps, use the shared instance:
/// ```dart
/// final bluey = Bluey.shared;
/// ```
///
/// For testing, set the platform instance before creating Bluey:
/// ```dart
/// BlueyPlatform.instance = fakePlatform;
/// final bluey = Bluey();
/// ```
///
/// ## Example
///
/// ```dart
/// final bluey = Bluey.shared;
///
/// // Check Bluetooth state
/// if (await bluey.state != BluetoothState.on) {
///   await bluey.requestEnable();
/// }
///
/// // Scan for devices
/// final scanner = bluey.scanner();
/// scanner.scan().listen((result) {
///   print('Found: ${result.device.name}');
/// });
/// ```
class Bluey {
  /// Shared instance for simple apps.
  ///
  /// Use this when you don't need dependency injection or isolated instances.
  /// The instance is created lazily on first access.
  static Bluey get shared => _shared ??= Bluey();
  static Bluey? _shared;

  /// Resets the shared instance.
  ///
  /// Call this if you need to reinitialize Bluey (e.g., after dispose).
  /// Typically only needed in tests.
  static void resetShared() {
    _shared = null;
  }

  final platform.BlueyPlatform _platform;
  final BlueyEventBus _eventBus;
  final BlueyLogger _logger = BlueyLogger();

  StreamSubscription? _stateSubscription;
  StreamSubscription<platform.PlatformLogEvent>? _platformLogSubscription;
  final StreamController<BluetoothState> _stateController =
      StreamController<BluetoothState>.broadcast();

  BluetoothState _currentState = BluetoothState.unknown;

  /// Creates a new Bluey instance.
  ///
  /// For most apps, prefer using [Bluey.shared] instead.
  ///
  /// Use this constructor when you need multiple isolated Bluey instances.
  ///
  /// Call [dispose] when done to release resources.
  Bluey()
    : _platform = platform.BlueyPlatform.instance,
      _eventBus = BlueyEventBus() {
    _stateSubscription = _platform.stateStream.listen((state) {
      _currentState = _mapState(state);
      _stateController.add(_currentState);
    }, onError: (error) => _stateController.addError(
        translatePlatformException(error, operation: 'stateStream')));

    // Forward native log events into the unified logger stream so that
    // `bluey.logEvents` is the single, merged surface for both Dart-side
    // and platform-side records.
    _platformLogSubscription = _platform.logEvents.listen(
      _logger.injectFromPlatform,
    );
  }

  /// Platform capabilities.
  platform.Capabilities get capabilities => _platform.capabilities;

  /// Configure the Bluey plugin behavior.
  ///
  /// Call this early in your app lifecycle (e.g., in `main()` before
  /// `runApp()`) to customize plugin behavior.
  ///
  /// ## Configuration Options
  ///
  /// ### cleanupOnActivityDestroy (Android only)
  ///
  /// When `true` (default), the plugin will automatically clean up BLE
  /// resources when the Android activity is destroyed:
  /// - Stop advertising
  /// - Close the GATT server
  /// - Disconnect all connected centrals
  ///
  /// This prevents "zombie" BLE connections that persist after the app is
  /// closed, which can cause issues when the app is relaunched.
  ///
  /// Set to `false` if you want to manage cleanup manually by calling
  /// [Server.dispose] yourself. This gives you more control over when
  /// cleanup happens, but you are responsible for ensuring proper cleanup.
  ///
  /// **Note:** On iOS, the OS handles BLE cleanup automatically when the
  /// app is terminated, so this option has no effect.
  ///
  /// ## Example
  ///
  /// ```dart
  /// void main() async {
  ///   WidgetsFlutterBinding.ensureInitialized();
  ///
  ///   // Use default cleanup behavior (recommended)
  ///   final bluey = Bluey();
  ///   await bluey.configure();
  ///
  ///   // Or disable automatic cleanup (you'll manage it manually)
  ///   await bluey.configure(cleanupOnActivityDestroy: false);
  ///
  ///   runApp(MyApp());
  /// }
  /// ```
  ///
  /// See also:
  /// - [Server.dispose] for manual cleanup of the GATT server.
  Future<void> configure({
    bool cleanupOnActivityDestroy = true,
    GattTimeouts gattTimeouts = const GattTimeouts(),
  }) {
    return withErrorTranslation(
      () => _platform.configure(
        platform.BlueyConfig(
          cleanupOnActivityDestroy: cleanupOnActivityDestroy,
          discoverServicesTimeoutMs: gattTimeouts.discoverServices.inMilliseconds,
          readCharacteristicTimeoutMs: gattTimeouts.readCharacteristic.inMilliseconds,
          writeCharacteristicTimeoutMs: gattTimeouts.writeCharacteristic.inMilliseconds,
          readDescriptorTimeoutMs: gattTimeouts.readDescriptor.inMilliseconds,
          writeDescriptorTimeoutMs: gattTimeouts.writeDescriptor.inMilliseconds,
          requestMtuTimeoutMs: gattTimeouts.requestMtu.inMilliseconds,
          readRssiTimeoutMs: gattTimeouts.readRssi.inMilliseconds,
        ),
      ),
      operation: 'configure',
    );
  }

  /// Current Bluetooth state synchronously.
  ///
  /// This returns the last known state, which may be [BluetoothState.unknown]
  /// if the platform hasn't reported yet. For an up-to-date state, use [state].
  BluetoothState get currentState => _currentState;

  /// Stream of Bluetooth state changes.
  ///
  /// Emits whenever Bluetooth is enabled, disabled, or permissions change.
  Stream<BluetoothState> get stateStream => _stateController.stream;

  /// Stream of diagnostic events from Bluey.
  ///
  /// Subscribe to this stream to monitor what's happening inside Bluey.
  /// Useful for debugging, logging, and understanding BLE operations.
  ///
  /// Example:
  /// ```dart
  /// bluey.events.listen((event) {
  ///   print(event); // [Scan] Started filter=180d timeout=10s
  /// });
  /// ```
  Stream<BlueyEvent> get events => _eventBus.stream;

  /// Stream of structured log events emitted by Bluey internals.
  ///
  /// Events at or above the current log level (see [setLogLevel]) are
  /// delivered on this broadcast stream. Events below the threshold are
  /// dropped without allocation.
  ///
  /// Example:
  /// ```dart
  /// bluey.setLogLevel(BlueyLogLevel.debug);
  /// bluey.logEvents.listen((event) => print(event));
  /// ```
  Stream<BlueyLogEvent> get logEvents => _logger.events;

  /// Sets the minimum severity threshold for [logEvents].
  ///
  /// Events strictly below [level] are dropped. Defaults to
  /// [BlueyLogLevel.info]. Also forwards the threshold to the platform
  /// implementation so native sides can drop events before marshalling.
  void setLogLevel(BlueyLogLevel level) {
    _logger.setLevel(level);
    // Fire-and-forget: native filter updates eventually-consistently;
    // events emitted in the meantime are filtered Dart-side anyway.
    unawaited(_platform.setLogLevel(_mapLogLevelToPlatform(level)));
  }

  /// Internal logger seam for tests.
  ///
  /// Production code outside the [Bluey] facade must not depend on this
  /// getter; subsystems receive the logger via constructor injection
  /// (see plan I307 phase A.5). This exists solely to let tests verify
  /// the wiring between the logger and the public [logEvents] stream.
  @visibleForTesting
  BlueyLogger get logger => _logger;

  /// Get current Bluetooth state.
  Future<BluetoothState> get state {
    return withErrorTranslation(
      () async => _mapState(await _platform.getState()),
      operation: 'getState',
    );
  }

  /// Ensure Bluetooth is ready to use.
  ///
  /// Throws [BluetoothUnavailableException] if Bluetooth is not supported.
  /// Throws [PermissionDeniedException] if permissions are not granted.
  /// Throws [BluetoothDisabledException] if Bluetooth is off and cannot be enabled.
  Future<void> ensureReady() async {
    final currentState = await state;
    switch (currentState) {
      case BluetoothState.on:
        return;
      case BluetoothState.unsupported:
        throw const BluetoothUnavailableException();
      case BluetoothState.unauthorized:
        throw PermissionDeniedException(['Bluetooth']);
      case BluetoothState.off:
        final enabled = await requestEnable();
        if (!enabled) {
          throw const BluetoothDisabledException();
        }
      case BluetoothState.unknown:
        throw const BluetoothUnavailableException();
    }
  }

  /// Request the user to enable Bluetooth.
  ///
  /// Returns true if Bluetooth was enabled, false if user declined.
  /// On some platforms, this opens settings instead of showing a prompt.
  Future<bool> requestEnable() {
    return withErrorTranslation(
      () => _platform.requestEnable(),
      operation: 'requestEnable',
    );
  }

  /// Request Bluetooth permissions from the user.
  ///
  /// Returns true if all required permissions were granted, false otherwise.
  /// On Android 12+, this requests BLUETOOTH_SCAN and BLUETOOTH_CONNECT.
  /// On older Android versions, this requests BLUETOOTH, BLUETOOTH_ADMIN,
  /// and ACCESS_FINE_LOCATION.
  Future<bool> authorize() {
    return withErrorTranslation(
      () => _platform.authorize(),
      operation: 'authorize',
    );
  }

  /// Open system Bluetooth settings.
  Future<void> openSettings() {
    return withErrorTranslation(
      () => _platform.openSettings(),
      operation: 'openSettings',
    );
  }

  /// Create a Scanner for discovering nearby BLE devices.
  ///
  /// Returns a [Scanner] aggregate root for the Discovery bounded context.
  /// Call [Scanner.dispose] when done to release resources.
  ///
  /// Example:
  /// ```dart
  /// final scanner = bluey.scanner();
  /// final subscription = scanner.scan().listen((result) {
  ///   print('Found: ${result.device.name} at ${result.rssi} dBm');
  /// });
  /// // ...
  /// scanner.dispose();
  /// ```
  Scanner scanner() {
    return BlueyScanner(_platform, _eventBus);
  }

  /// Connect to a device.
  ///
  /// [device] - The device to connect to.
  /// [timeout] - Optional connection timeout.
  ///
  /// Returns a raw [Connection]. This method does **not** auto-upgrade
  /// to the Bluey peer protocol even when the device hosts the control
  /// service. Callers that want peer-aware behavior should use
  /// [connectAsPeer] (which throws [NotABlueyPeerException] for non-peer
  /// devices) or call [tryUpgrade] on the returned connection.
  ///
  /// Throws [ConnectionException] if connection fails.
  Future<Connection> connect(
    Device device, {
    Duration? timeout,
  }) async {
    final config = platform.PlatformConnectConfig(
      timeoutMs: timeout?.inMilliseconds,
      mtu: null,
    );

    _logger.log(
      BlueyLogLevel.info,
      'bluey',
      'connect entered',
      data: {'deviceId': device.id.toString()},
    );

    _logger.log(
      BlueyLogLevel.info,
      'bluey.connection',
      'connect started',
      data: {
        'deviceId': device.id.toString(),
        'address': device.address,
      },
    );

    _emitEvent(ConnectingEvent(deviceId: device.id));

    try {
      // Use address for the actual connection (MAC address on Android)
      final connectionId = await withErrorTranslation(
        () => _platform.connect(device.address, config),
        operation: 'connect',
        deviceId: device.id,
      );

      _emitEvent(ConnectedEvent(deviceId: device.id));

      final connection = BlueyConnection(
        platformInstance: _platform,
        connectionId: connectionId,
        deviceId: device.id,
        logger: _logger,
        events: _eventBus,
      );

      _logger.log(
        BlueyLogLevel.info,
        'bluey.connection',
        'connect succeeded',
        data: {'deviceId': device.id.toString()},
      );

      return connection;
    } catch (e) {
      _logger.log(
        BlueyLogLevel.error,
        'bluey.connection',
        'connect failed',
        data: {
          'deviceId': device.id.toString(),
          'exception': e.runtimeType.toString(),
        },
        errorCode: e.runtimeType.toString(),
      );
      _emitEvent(
        ErrorEvent(
          message: 'Connection failed to ${device.id.toShortString()}',
          error: e,
        ),
      );
      rethrow;
    }
  }

  /// Connects to [device] and returns a [PeerConnection] if the device
  /// hosts the Bluey lifecycle control service.
  ///
  /// Internally calls [connect] to establish the raw GATT connection,
  /// then attempts to build a peer wrapper. If the device is not a
  /// Bluey peer (no control service), the underlying connection is
  /// disconnected and [NotABlueyPeerException] is thrown.
  ///
  /// Use this when the caller knows the target should be a Bluey peer
  /// and wants the peer-protocol surface (stable [ServerId], filtered
  /// service tree, lifecycle disconnect) rather than the raw GATT
  /// handle.
  ///
  /// Throws [ConnectionException] if the underlying connect fails.
  /// Throws [NotABlueyPeerException] if the device connected but does
  /// not host the Bluey control service. The underlying connection has
  /// already been disconnected when this is thrown.
  Future<PeerConnection> connectAsPeer(
    Device device, {
    Duration? timeout,
    Duration peerSilenceTimeout = lifecycle.defaultPeerSilenceTimeout,
  }) async {
    _logger.log(
      BlueyLogLevel.info,
      'bluey',
      'connectAsPeer entered',
      data: {'deviceId': device.id.toString()},
    );
    final connection = await connect(
      device,
      timeout: timeout,
    );
    final peer = await _tryBuildPeerConnection(
      connection,
      peerSilenceTimeout: peerSilenceTimeout,
    );
    if (peer == null) {
      // The device connected but isn't a Bluey peer — disconnect and
      // throw so we don't leak a half-formed connection.
      await connection.disconnect();
      throw NotABlueyPeerException(device.id);
    }
    return peer;
  }

  /// Attempts to wrap an existing raw [Connection] in a [PeerConnection].
  ///
  /// Returns `null` if [connection] does not host the Bluey lifecycle
  /// control service. Unlike [connectAsPeer], this does not disconnect
  /// the connection on miss — the caller already owns it and decides
  /// what to do next.
  ///
  /// Use this when you have a raw [Connection] (e.g. from a custom
  /// connect path) and want to opportunistically promote it to a peer
  /// wrapper.
  ///
  /// **One-shot snapshot.** This method evaluates the connection's
  /// current service tree exactly once. On real devices the central may
  /// hold a stale GATT cache that hides the lifecycle service until the
  /// peer pushes a Service Changed indication — calls landing inside
  /// that window will return `null` even though the peer is fully
  /// available a moment later. Callers that want to track peer status
  /// across the connection's lifetime should use [watchPeer], which
  /// retries the upgrade on each Service Changed re-discovery.
  Future<PeerConnection?> tryUpgrade(Connection connection) async {
    _logger.log(
      BlueyLogLevel.debug,
      'bluey',
      'tryUpgrade entered',
      data: {'deviceId': connection.deviceId.toString()},
    );
    final result = await _tryBuildPeerConnection(connection);
    _logger.log(
      BlueyLogLevel.debug,
      'bluey',
      'tryUpgrade resolved',
      data: {
        'deviceId': connection.deviceId.toString(),
        'peer': result == null ? 'null' : 'present',
      },
    );
    return result;
  }

  /// Watches [connection] for peer status, retrying [tryUpgrade] on
  /// each Service Changed re-discovery until the upgrade succeeds.
  ///
  /// Emits the result of [tryUpgrade] on subscription (which may be
  /// `null`). If `null`, listens to `connection.servicesChanges` and
  /// re-attempts the upgrade on every emission, yielding each result.
  /// Once a non-null [PeerConnection] has been emitted, the stream
  /// completes — the resulting peer's own lifecycle protocol handles
  /// in-place handle refresh on subsequent Service Changed events, and
  /// re-running [tryUpgrade] would orphan a fresh `LifecycleClient`.
  ///
  /// The stream also completes when [connection] transitions to
  /// [ConnectionState.disconnected], so subscribers do not leak past
  /// the connection's lifetime.
  ///
  /// Use this in preference to [tryUpgrade] when the central may have a
  /// stale GATT cache (a real-device hazard with cold-launched servers
  /// that finish registering their lifecycle service after the central
  /// completes initial discovery): the stale cache hides the lifecycle
  /// service from the first [tryUpgrade], but Service Changed
  /// eventually surfaces it and a subsequent retry succeeds.
  ///
  /// Single-subscription. Each call returns a fresh stream with its own
  /// listeners; multiple watchers should each call [watchPeer].
  Stream<PeerConnection?> watchPeer(Connection connection) {
    late StreamController<PeerConnection?> controller;
    StreamSubscription<dynamic>? servicesSub;
    StreamSubscription<ConnectionState>? stateSub;
    var resolved = false;
    var busy = false;
    var pendingRetry = false;

    Future<void> attempt() async {
      if (resolved) return;
      if (busy) {
        // A service-changed event landed while a previous attempt was
        // still in flight — note it so we re-attempt once busy clears,
        // rather than dropping the signal.
        pendingRetry = true;
        return;
      }
      busy = true;
      try {
        do {
          pendingRetry = false;
          final peer = await tryUpgrade(connection);
          if (resolved || controller.isClosed) return;
          if (peer != null) {
            resolved = true;
            controller.add(peer);
            await controller.close();
            return;
          }
          controller.add(null);
        } while (pendingRetry);
      } finally {
        busy = false;
      }
    }

    controller = StreamController<PeerConnection?>(
      onListen: () async {
        await attempt();
        if (resolved || controller.isClosed) return;
        servicesSub = connection.servicesChanges.listen((_) {
          attempt();
        });
        stateSub = connection.stateChanges.listen((s) {
          if (s == ConnectionState.disconnected &&
              !resolved &&
              !controller.isClosed) {
            resolved = true;
            controller.close();
          }
        });
      },
      onCancel: () async {
        resolved = true;
        await servicesSub?.cancel();
        await stateSub?.cancel();
      },
    );

    return controller.stream;
  }

  /// Builds a [PeerConnection] wrapping [rawConnection] if the device
  /// hosts the lifecycle control service.
  ///
  /// Discovers services on [rawConnection] and, if the Bluey lifecycle
  /// control service is present, builds a [PeerConnection] around it.
  /// Does **not** mutate the underlying [Connection]. On success, a fresh
  /// [PeerConnection] wrapper is returned around the existing raw
  /// connection.
  ///
  /// Returns `null` when:
  /// - The control service is absent.
  /// - Service discovery fails for any reason.
  Future<PeerConnection?> _tryBuildPeerConnection(
    Connection rawConnection, {
    Duration peerSilenceTimeout = lifecycle.defaultPeerSilenceTimeout,
  }) async {
    try {
      _logger.log(
        BlueyLogLevel.debug,
        'bluey.peer',
        'tryBuildPeerConnection',
        data: {'deviceId': rawConnection.deviceId.toString()},
      );

      final services = await rawConnection.services();

      final controlService = services
          .where((s) => lifecycle.isControlService(s.uuid.toString()))
          .firstOrNull;

      if (controlService == null) {
        _logger.log(
          BlueyLogLevel.debug,
          'bluey.peer',
          'no control service — peer is not a bluey peer',
          data: {'deviceId': rawConnection.deviceId.toString()},
        );
        return null;
      }

      // Read the ServerId.
      final serverIdChar = controlService.characteristics().where(
            (c) =>
                c.uuid.toString().toLowerCase() == lifecycle.serverIdCharUuid,
          ).firstOrNull;

      ServerId? serverId;
      if (serverIdChar != null) {
        try {
          final bytes = await serverIdChar.read();
          serverId = lifecycle.decodeServerId(bytes);
        } catch (_) {
          // ServerId read failed — fall through with a generated id so
          // the peer wrapper still installs the lifecycle heartbeat.
        }
      }

      // Locate the underlying BlueyConnection for the lifecycle
      // client's connection id. The peer wrapper does not require
      // mutating this object; it only needs the platform connection
      // id to drive the heartbeat writes.
      final connectionId = rawConnection is BlueyConnection
          ? rawConnection.connectionId
          : rawConnection.deviceId.toString();

      final lifecycleClient = LifecycleClient(
        platformApi: _platform,
        connectionId: connectionId,
        peerSilenceTimeout: peerSilenceTimeout,
        onServerUnreachable: () {
          rawConnection.disconnect().catchError((_) {});
        },
        logger: _logger,
        servicesChanges: rawConnection.servicesChanges,
        events: _eventBus,
        deviceId: rawConnection.deviceId,
      );
      lifecycleClient.start(allServices: services);

      return PeerConnection.create(
        connection: rawConnection,
        serverId: serverId ?? ServerId.generate(),
        lifecycleClient: lifecycleClient,
      );
    } catch (_) {
      // Service discovery failed — treat as "not a bluey peer".
      return null;
    }
  }

  /// Get all bonded devices.
  ///
  /// Returns a list of devices that have been previously bonded/paired
  /// with this device. Bonded devices can reconnect without re-pairing
  /// and may have access to encrypted characteristics.
  ///
  /// Example:
  /// ```dart
  /// final bonded = await bluey.bondedDevices;
  /// for (final device in bonded) {
  ///   print('Bonded: ${device.name}');
  /// }
  /// ```
  Future<List<Device>> get bondedDevices {
    _requireCapability(_platform.capabilities.canBond, 'bondedDevices');
    return withErrorTranslation(
      () async =>
          (await _platform.getBondedDevices()).map(_mapDevice).toList(),
      operation: 'getBondedDevices',
    );
  }

  /// Throws [UnsupportedOperationException] when [flag] is false.
  ///
  /// Used to gate methods on [Bluey] whose underlying platform call may
  /// not be supported on the current platform. Mirrors the helper of the
  /// same name on [BlueyConnection] / [BlueyServer].
  void _requireCapability(bool flag, String op) {
    if (!flag) {
      throw UnsupportedOperationException(
        op,
        _platform.capabilities.platformKind.name,
      );
    }
  }

  /// Domain ↔ Platform seam: translates `PlatformDevice` (BLE-spec
  /// vocabulary, platform-interface layer) into the Discovery context's
  /// `Device` (domain layer). Identity-only — advertisement data is
  /// handled separately by the scanner pipeline.
  Device _mapDevice(platform.PlatformDevice platformDevice) {
    return Device(
      id: deviceIdToUuid(platformDevice.id),
      address: platformDevice.id,
      name: platformDevice.name,
    );
  }

  /// Create a GATT server for peripheral role.
  ///
  /// Returns a [Server] for advertising services and handling requests
  /// from client devices.
  ///
  /// Returns null on platforms that don't support peripheral role.
  /// Check [capabilities.canAdvertise] before calling.
  ///
  /// [lifecycleInterval] controls automatic lifecycle management between
  /// Bluey peers. When non-null (the default), the server hosts a hidden
  /// control service that Bluey clients use for heartbeat-based disconnect
  /// detection. This solves the iOS limitation where `CBPeripheralManager`
  /// has no callback for client disconnections. Set to null to disable
  /// lifecycle management and use raw BLE behavior.
  ///
  /// Example:
  /// ```dart
  /// final server = bluey.server();
  /// if (server != null) {
  ///   server.addService(myService);
  ///   await server.startAdvertising(name: 'My Device');
  /// }
  /// ```
  Server? server({
    Duration? lifecycleInterval = const Duration(seconds: 10),
    ServerId? identity,
  }) {
    if (!_platform.capabilities.canAdvertise) {
      return null;
    }
    return BlueyServer(
      _platform,
      _eventBus,
      lifecycleInterval: lifecycleInterval,
      identity: identity,
      logger: _logger,
    );
  }

  /// Construct a peer handle from a known [ServerId].
  ///
  /// No BLE activity happens until [BlueyPeer.connect] is called.
  ///
  /// [peerSilenceTimeout] controls how long after a peer-failure signal
  /// (heartbeat probe timeout or user-op timeout) without an intervening
  /// successful exchange before the peer is declared unreachable and a
  /// local disconnect is triggered. Defaults to
  /// [lifecycle.defaultPeerSilenceTimeout] (30 s); see that constant for
  /// the rationale (must exceed the OS link-supervision timeout).
  BlueyPeer peer(
    ServerId serverId, {
    Duration peerSilenceTimeout = lifecycle.defaultPeerSilenceTimeout,
  }) {
    return createBlueyPeer(
      platformApi: _platform,
      serverId: serverId,
      peerSilenceTimeout: peerSilenceTimeout,
      logger: _logger,
      events: _eventBus,
    );
  }

  /// Scan for nearby Bluey servers.
  ///
  /// Scans for nearby BLE devices, briefly connects to each candidate
  /// to check for the Bluey control service and read its `serverId`,
  /// and returns a list of [BlueyPeer]s deduplicated by [ServerId].
  ///
  /// [timeout] bounds the scan window. Defaults to 5 seconds.
  /// [probeTimeout] bounds each individual probe-connect attempt; one
  /// unresponsive candidate doesn't stall the whole session. Defaults
  /// to [PeerDiscovery.defaultProbeTimeout] (3 s).
  Future<List<BlueyPeer>> discoverPeers({
    Duration timeout = const Duration(seconds: 5),
    Duration probeTimeout = PeerDiscovery.defaultProbeTimeout,
  }) async {
    final discovery = PeerDiscovery(
      platformApi: _platform,
      logger: _logger,
      events: _eventBus,
    );
    final ids = await discovery.discover(
      timeout: timeout,
      probeTimeout: probeTimeout,
    );
    return ids
        .map((id) => createBlueyPeer(
              platformApi: _platform,
              serverId: id,
              logger: _logger,
              events: _eventBus,
            ))
        .toList(growable: false);
  }

  /// Release all resources.
  ///
  /// After calling dispose, this instance cannot be used.
  /// If this is the shared instance, it will be cleared so a new one
  /// can be created via [Bluey.shared].
  Future<void> dispose() async {
    await _stateSubscription?.cancel();
    await _platformLogSubscription?.cancel();
    await _stateController.close();
    await _eventBus.close();
    await _logger.dispose();
    if (_shared == this) {
      _shared = null;
    }
  }

  platform.PlatformLogLevel _mapLogLevelToPlatform(BlueyLogLevel level) {
    switch (level) {
      case BlueyLogLevel.trace:
        return platform.PlatformLogLevel.trace;
      case BlueyLogLevel.debug:
        return platform.PlatformLogLevel.debug;
      case BlueyLogLevel.info:
        return platform.PlatformLogLevel.info;
      case BlueyLogLevel.warn:
        return platform.PlatformLogLevel.warn;
      case BlueyLogLevel.error:
        return platform.PlatformLogLevel.error;
    }
  }

  BluetoothState _mapState(platform.BluetoothState platformState) {
    switch (platformState) {
      case platform.BluetoothState.unknown:
        return BluetoothState.unknown;
      case platform.BluetoothState.unsupported:
        return BluetoothState.unsupported;
      case platform.BluetoothState.unauthorized:
        return BluetoothState.unauthorized;
      case platform.BluetoothState.off:
        return BluetoothState.off;
      case platform.BluetoothState.on:
        return BluetoothState.on;
    }
  }

  /// Emits an event to the event bus.
  void _emitEvent(BlueyEvent event) {
    _eventBus.emit(event);
  }
}
