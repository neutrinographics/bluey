import 'dart:async';
import 'dart:developer' as dev;

import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;

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
import 'peer/bluey_peer.dart';
import 'peer/peer.dart';
import 'peer/peer_discovery.dart';
import 'peer/server_id.dart';
import 'platform/bluetooth_state.dart';
import 'shared/device_id_coercion.dart';
import 'shared/exceptions.dart';
import 'shared/gatt_timeouts.dart';
import 'shared/uuid.dart';

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

  StreamSubscription? _stateSubscription;
  final StreamController<BluetoothState> _stateController =
      StreamController<BluetoothState>.broadcast();
  final StreamController<BlueyException> _errorController =
      StreamController<BlueyException>.broadcast();

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
    }, onError: (error) => _stateController.addError(_wrapError(error)));
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
  }) async {
    try {
      await _platform.configure(
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
      );
    } catch (e) {
      throw _wrapError(e);
    }
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

  /// Stream of errors from Bluey operations.
  ///
  /// Subscribe to this stream to receive notifications about errors
  /// that occur during BLE operations. This is useful for logging
  /// or displaying error messages to the user.
  Stream<BlueyException> get errorStream => _errorController.stream;

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

  /// Get current Bluetooth state.
  Future<BluetoothState> get state async {
    try {
      final platformState = await _platform.getState();
      return _mapState(platformState);
    } catch (e) {
      throw _wrapError(e);
    }
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
  Future<bool> requestEnable() async {
    try {
      return await _platform.requestEnable();
    } catch (e) {
      throw _wrapError(e);
    }
  }

  /// Request Bluetooth permissions from the user.
  ///
  /// Returns true if all required permissions were granted, false otherwise.
  /// On Android 12+, this requests BLUETOOTH_SCAN and BLUETOOTH_CONNECT.
  /// On older Android versions, this requests BLUETOOTH, BLUETOOTH_ADMIN,
  /// and ACCESS_FINE_LOCATION.
  Future<bool> authorize() async {
    try {
      return await _platform.authorize();
    } catch (e) {
      throw _wrapError(e);
    }
  }

  /// Open system Bluetooth settings.
  Future<void> openSettings() async {
    try {
      await _platform.openSettings();
    } catch (e) {
      throw _wrapError(e);
    }
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
  /// [peerSilenceTimeout] - How long after a peer-failure signal (heartbeat
  ///   probe timeout or user-op timeout) without an intervening successful
  ///   exchange before the peer is declared unreachable and a local
  ///   disconnect is triggered. Only applies when the device is a Bluey
  ///   server. Defaults to [lifecycle.defaultPeerSilenceTimeout] (30 s),
  ///   chosen to exceed the typical OS link-supervision timeout (~20 s) so
  ///   the OS path fires first on genuine link loss.
  ///
  /// After connecting, this method automatically discovers services. If the
  /// device hosts the Bluey control service, the lifecycle heartbeat is
  /// started and the connection is upgraded in place so that it hides the
  /// control service. For non-Bluey devices a raw connection is returned.
  /// Callers can check [Connection.isBlueyServer] to distinguish.
  ///
  /// Throws [ConnectionException] if connection fails.
  Future<Connection> connect(
    Device device, {
    Duration? timeout,
    Duration peerSilenceTimeout = lifecycle.defaultPeerSilenceTimeout,
  }) async {
    final config = platform.PlatformConnectConfig(
      timeoutMs: timeout?.inMilliseconds,
      mtu: null,
    );

    dev.log(
      'connect started: deviceId=${device.id}, address=${device.address}',
      name: 'bluey.connection',
    );

    _emitEvent(ConnectingEvent(deviceId: device.id));

    try {
      // Use address for the actual connection (MAC address on Android)
      final connectionId = await _platform.connect(device.address, config);

      _emitEvent(ConnectedEvent(deviceId: device.id));

      final rawConnection = BlueyConnection(
        platformInstance: _platform,
        connectionId: connectionId,
        deviceId: device.id,
        peerSilenceTimeout: peerSilenceTimeout,
      );

      // Auto-upgrade: if the server hosts the Bluey control service,
      // start the lifecycle heartbeat and upgrade the connection in place.
      final connection = await _upgradeIfBlueyServer(
        rawConnection,
        peerSilenceTimeout: peerSilenceTimeout,
      );

      dev.log(
        'connect succeeded: deviceId=${device.id}',
        name: 'bluey.connection',
      );

      return connection;
    } catch (e) {
      dev.log(
        'connect failed: deviceId=${device.id}, exception=${e.runtimeType}',
        name: 'bluey.connection',
        level: 1000, // Level.SEVERE
        error: e,
      );
      _emitEvent(
        ErrorEvent(
          message: 'Connection failed to ${device.id.toShortString()}',
          error: e,
        ),
      );
      throw _wrapError(e);
    }
  }

  /// Checks if the connected device hosts the Bluey control service.
  /// If yes, reads the ServerId, starts the lifecycle heartbeat, and
  /// upgrades the connection in place. If not, returns the raw connection
  /// unchanged.
  Future<Connection> _upgradeIfBlueyServer(
    BlueyConnection rawConnection, {
    Duration peerSilenceTimeout = lifecycle.defaultPeerSilenceTimeout,
  }) async {
    try {
      dev.log('upgrade attempt: deviceId=${rawConnection.deviceId}', name: 'bluey.peer');

      // Fetch services before upgrade so the full list (including control
      // service) is available for the lifecycle client.
      final services = await rawConnection.services();

      final controlService = services
          .where((s) => lifecycle.isControlService(s.uuid.toString()))
          .firstOrNull;

      dev.log(
        controlService != null
            ? 'control service discovered'
            : 'no control service — peer is not a bluey peer',
        name: 'bluey.peer',
      );

      if (controlService == null) return rawConnection;

      // Read the ServerId
      final serverIdChar = controlService.characteristics
          .where(
            (c) => c.uuid.toString().toLowerCase() == lifecycle.serverIdCharUuid,
          )
          .firstOrNull;

      ServerId? serverId;
      if (serverIdChar != null) {
        try {
          final bytes = await serverIdChar.read();
          serverId = lifecycle.decodeServerId(bytes);
        } catch (_) {
          // ServerId read failed -- still upgrade for lifecycle benefits
        }
      }

      dev.log('serverId read: $serverId', name: 'bluey.peer');

      // Start lifecycle heartbeat
      final lifecycleClient = LifecycleClient(
        platformApi: _platform,
        connectionId: rawConnection.connectionId,
        peerSilenceTimeout: peerSilenceTimeout,
        onServerUnreachable: () {
          rawConnection.disconnect().catchError((_) {});
        },
      );
      lifecycleClient.start(allServices: services);

      // Upgrade the connection in place — sets isBlueyServer, enables
      // service filtering, and invalidates the service cache.
      rawConnection.upgrade(
        lifecycleClient: lifecycleClient,
        serverId: serverId ?? ServerId.generate(),
      );

      dev.log('upgrade complete: deviceId=${rawConnection.deviceId}', name: 'bluey.peer');

      return rawConnection;
    } catch (_) {
      // Service discovery failed -- return raw connection
      return rawConnection;
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
    final connection = await connect(
      device,
      timeout: timeout,
      peerSilenceTimeout: peerSilenceTimeout,
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
  Future<PeerConnection?> tryUpgrade(Connection connection) {
    return _tryBuildPeerConnection(connection);
  }

  /// Builds a [PeerConnection] wrapping [rawConnection] if the device
  /// hosts the lifecycle control service.
  ///
  /// Mirrors the detection logic in [_upgradeIfBlueyServer], but
  /// **does not mutate** the underlying [Connection] (no
  /// `BlueyConnection.upgrade` call). Instead, on success, a fresh
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
      dev.log(
        'tryBuildPeerConnection: deviceId=${rawConnection.deviceId}',
        name: 'bluey.peer',
      );

      // Fast path: the legacy auto-upgrade in [connect] already ran
      // and detected the control service in place. The connection's
      // [Connection.services] now filters out the control service, so
      // service discovery here would miss it. Use the upgraded state
      // (isBlueyServer + serverId) to build the wrapper directly.
      //
      // The legacy path's lifecycle client is stored on the
      // [BlueyConnection]; we still install a fresh lifecycle client
      // here so the new wrapper has its own heartbeat handle. This
      // means the legacy auto-upgrade lifecycle (installed by
      // [_upgradeIfBlueyServer]) and the wrapper's lifecycle coexist
      // until C.5 collapses the two paths.
      if (rawConnection.isBlueyServer) {
        final existingServerId = rawConnection.serverId;
        // We still need to discover services to start the lifecycle
        // client (it locates the heartbeat characteristic). Pass
        // `cache: false` to fetch the post-upgrade filtered tree if
        // available, but we'll rediscover the unfiltered tree by
        // pulling from the connection: the auto-upgrade has already
        // attached a lifecycle on the connection itself, so all we
        // need here is to compose a wrapper that exposes the
        // peer-protocol surface. Build a lifecycle client whose
        // start() will be a no-op (no control service in the
        // post-upgrade filtered tree) and let the legacy lifecycle
        // continue driving heartbeats.
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
        );
        return PeerConnection.create(
          connection: rawConnection,
          serverId: existingServerId ?? ServerId.generate(),
          lifecycleClient: lifecycleClient,
        );
      }

      final services = await rawConnection.services();

      final controlService = services
          .where((s) => lifecycle.isControlService(s.uuid.toString()))
          .firstOrNull;

      if (controlService == null) {
        dev.log(
          'no control service — peer is not a bluey peer',
          name: 'bluey.peer',
        );
        return null;
      }

      // Read the ServerId.
      final serverIdChar = controlService.characteristics
          .where(
            (c) =>
                c.uuid.toString().toLowerCase() == lifecycle.serverIdCharUuid,
          )
          .firstOrNull;

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
  Future<List<Device>> get bondedDevices async {
    try {
      final platformDevices = await _platform.getBondedDevices();
      return platformDevices.map(_mapDevice).toList();
    } catch (e) {
      throw _wrapError(e);
    }
  }

  /// Maps a platform device to a domain Device (identity only).
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
    );
  }

  /// Scan for nearby Bluey servers.
  ///
  /// Scans for nearby BLE devices, briefly connects to each candidate
  /// to check for the Bluey control service and read its `serverId`,
  /// and returns a list of [BlueyPeer]s deduplicated by [ServerId].
  ///
  /// [timeout] bounds the scan window. Defaults to 5 seconds.
  Future<List<BlueyPeer>> discoverPeers({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final discovery = PeerDiscovery(platformApi: _platform);
    final ids = await discovery.discover(timeout: timeout);
    return ids
        .map((id) => createBlueyPeer(
              platformApi: _platform,
              serverId: id,
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
    await _stateController.close();
    await _errorController.close();
    await _eventBus.close();
    if (_shared == this) {
      _shared = null;
    }
  }

  // === Private mapping methods ===

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

  /// Wraps platform errors in domain exceptions and emits to error stream.
  BlueyException _wrapError(Object error) {
    if (error is BlueyException) {
      _errorController.add(error);
      return error;
    }

    // Convert common platform errors to domain exceptions
    final message = error.toString().toLowerCase();

    BlueyException exception;

    if (message.contains('permission') || message.contains('unauthorized')) {
      exception = PermissionDeniedException(['Bluetooth']);
    } else if (message.contains('disabled') ||
        message.contains('bluetooth is off')) {
      exception = const BluetoothDisabledException();
    } else if (message.contains('unavailable') ||
        message.contains('unsupported')) {
      exception = const BluetoothUnavailableException();
    } else if (message.contains('timeout') && message.contains('connect')) {
      exception = ConnectionException(
        UUID.short(0x0000), // Unknown device
        ConnectionFailureReason.timeout,
      );
    } else if (message.contains('not connected') ||
        message.contains('device not found')) {
      exception = ConnectionException(
        UUID.short(0x0000),
        ConnectionFailureReason.deviceNotFound,
      );
    } else {
      // Generic fallback - preserve the original error message
      exception = BlueyPlatformException(error.toString(), cause: error);
    }

    _errorController.add(exception);
    return exception;
  }
}
