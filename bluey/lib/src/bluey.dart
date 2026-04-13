import 'dart:async';
import 'dart:typed_data';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;

import 'advertisement.dart';
import 'bluey_connection.dart';
import 'bluey_server.dart';
import 'connection.dart';
import 'connection_state.dart';
import 'device.dart';
import 'event_bus.dart';
import 'events.dart';
import 'exceptions.dart';
import 'manufacturer_data.dart';
import 'scan_result.dart';
import 'server.dart';
import 'uuid.dart';

export 'events.dart';
export 'scan_result.dart';

/// The state of the Bluetooth adapter.
enum BluetoothState {
  /// Initial state before platform reports.
  unknown,

  /// Device doesn't support BLE.
  unsupported,

  /// Permission not granted.
  unauthorized,

  /// Bluetooth is disabled.
  off,

  /// Bluetooth is ready to use.
  on;

  /// Whether Bluetooth is ready for use.
  bool get isReady => this == BluetoothState.on;

  /// Whether Bluetooth can be enabled (only true when off).
  bool get canBeEnabled => this == BluetoothState.off;
}

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
/// await for (final device in bluey.scan()) {
///   print('Found: ${device.name}');
/// }
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
  Future<void> configure({bool cleanupOnActivityDestroy = true}) async {
    try {
      await _platform.configure(
        platform.BlueyConfig(
          cleanupOnActivityDestroy: cleanupOnActivityDestroy,
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

  /// Scan for nearby BLE devices.
  ///
  /// Returns a stream of [ScanResult]s. Each result pairs a stable [Device]
  /// identity with transient observation data (rssi, advertisement, lastSeen).
  /// The stream completes when scanning stops (timeout or [stopScan] called).
  ///
  /// [services] - Optional list of service UUIDs to filter by.
  /// [timeout] - Optional timeout duration.
  ///
  /// Example:
  /// ```dart
  /// await for (final result in bluey.scan(timeout: Duration(seconds: 10))) {
  ///   print('Found: ${result.device.name} at ${result.rssi} dBm');
  /// }
  /// ```
  Stream<ScanResult> scan({List<UUID>? services, Duration? timeout}) {
    final config = platform.PlatformScanConfig(
      serviceUuids: services?.map((u) => u.toString()).toList() ?? [],
      timeoutMs: timeout?.inMilliseconds,
    );

    _emitEvent(ScanStartedEvent(serviceFilter: services, timeout: timeout));

    return _platform
        .scan(config)
        .map((platformDevice) {
          final result = _mapScanResult(platformDevice);
          _emitEvent(
            DeviceDiscoveredEvent(
              deviceId: result.device.id,
              name: result.device.name,
              rssi: result.rssi,
            ),
          );
          return result;
        })
        .handleError((error) => throw _wrapError(error));
  }

  /// Stop scanning for devices.
  Future<void> stopScan() async {
    try {
      await _platform.stopScan();
      _emitEvent(ScanStoppedEvent());
    } catch (e) {
      throw _wrapError(e);
    }
  }

  /// Connect to a device.
  ///
  /// [device] - The device to connect to.
  /// [timeout] - Optional connection timeout.
  ///
  /// Returns a [Connection] for GATT operations.
  /// Throws [ConnectionException] if connection fails.
  Future<Connection> connect(Device device, {Duration? timeout}) async {
    final config = platform.PlatformConnectConfig(
      timeoutMs: timeout?.inMilliseconds,
      mtu: null,
    );

    _emitEvent(ConnectingEvent(deviceId: device.id));

    try {
      // Use address for the actual connection (MAC address on Android)
      final connectionId = await _platform.connect(device.address, config);

      _emitEvent(ConnectedEvent(deviceId: device.id));

      return BlueyConnection(
        platformInstance: _platform,
        connectionId: connectionId,
        deviceId: device.id,
      );
    } catch (e) {
      _emitEvent(
        ErrorEvent(
          message: 'Connection failed to ${device.id.toShortString()}',
          error: e,
        ),
      );
      throw _wrapError(e);
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
      id: _deviceIdToUuid(platformDevice.id),
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
  Server? server({Duration? lifecycleInterval = const Duration(seconds: 10)}) {
    if (!_platform.capabilities.canAdvertise) {
      return null;
    }
    return BlueyServer(
      _platform,
      _eventBus,
      lifecycleInterval: lifecycleInterval,
    );
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

  ConnectionState _mapConnectionState(
    platform.PlatformConnectionState platformState,
  ) {
    switch (platformState) {
      case platform.PlatformConnectionState.disconnected:
        return ConnectionState.disconnected;
      case platform.PlatformConnectionState.connecting:
        return ConnectionState.connecting;
      case platform.PlatformConnectionState.connected:
        return ConnectionState.connected;
      case platform.PlatformConnectionState.disconnecting:
        return ConnectionState.disconnecting;
    }
  }

  ScanResult _mapScanResult(platform.PlatformDevice platformDevice) {
    // Convert manufacturer data
    ManufacturerData? manufacturerData;
    if (platformDevice.manufacturerDataCompanyId != null &&
        platformDevice.manufacturerData != null) {
      manufacturerData = ManufacturerData(
        platformDevice.manufacturerDataCompanyId!,
        Uint8List.fromList(platformDevice.manufacturerData!),
      );
    }

    // Convert service UUIDs
    final serviceUuids =
        platformDevice.serviceUuids.map((s) => UUID(s)).toList();

    // Create advertisement
    final advertisement = Advertisement(
      serviceUuids: serviceUuids,
      serviceData: {}, // TODO: Add service data when platform supports it
      manufacturerData: manufacturerData,
      isConnectable: true, // TODO: Get from platform when available
    );

    // Create device (identity only)
    // Note: On Android, the device ID is a MAC address, not a UUID.
    // We create a UUID from the MAC by padding it, but preserve the original
    // address for connections.
    final device = Device(
      id: _deviceIdToUuid(platformDevice.id),
      address: platformDevice.id, // Keep original for platform calls
      name: platformDevice.name,
    );

    return ScanResult(
      device: device,
      rssi: platformDevice.rssi,
      advertisement: advertisement,
    );
  }

  /// Converts a platform device ID to a UUID.
  ///
  /// On Android, the ID is a MAC address (e.g., "AA:BB:CC:DD:EE:FF").
  /// On iOS, the ID is already a UUID.
  UUID _deviceIdToUuid(String id) {
    // Check if it's already a UUID format
    if (id.length == 36 && id.contains('-')) {
      return UUID(id);
    }

    // Convert MAC address to UUID format
    // Remove colons and pad to 32 hex chars
    final clean = id.replaceAll(':', '').toLowerCase();
    final padded = clean.padLeft(32, '0');
    return UUID(padded);
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
