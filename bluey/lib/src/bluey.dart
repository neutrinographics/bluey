import 'dart:async';
import 'dart:typed_data';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;

import 'bluey_connection.dart';
import 'bluey_server.dart';
import 'connection.dart';
import 'connection_state.dart';
import 'device.dart';
import 'exceptions.dart';
import 'server.dart';
import 'uuid.dart';

export 'connection_state.dart';

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
/// Example:
/// ```dart
/// final bluey = Bluey();
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
  static Bluey? _instance;

  final platform.BlueyPlatform _platform;

  StreamSubscription? _stateSubscription;
  final StreamController<BluetoothState> _stateController =
      StreamController<BluetoothState>.broadcast();
  final StreamController<BlueyException> _errorController =
      StreamController<BlueyException>.broadcast();

  BluetoothState _currentState = BluetoothState.unknown;

  /// Gets or creates the Bluey instance.
  ///
  /// This uses a singleton pattern to ensure the platform implementation
  /// is properly registered before being accessed.
  ///
  /// Typically you create one instance and reuse it throughout your app.
  /// Call [dispose] when done to release resources.
  factory Bluey() {
    var instance = _instance;
    if (instance == null) {
      _instance = instance = Bluey._internal(platform.BlueyPlatform.instance);
    }
    return instance;
  }

  /// Internal constructor.
  Bluey._internal(this._platform) {
    _stateSubscription = _platform.stateStream.listen((state) {
      _currentState = _mapState(state);
      _stateController.add(_currentState);
    }, onError: (error) => _stateController.addError(_wrapError(error)));
  }

  /// Platform capabilities.
  platform.Capabilities get capabilities => _platform.capabilities;

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
  /// Returns a stream of discovered [Device]s. The stream completes when
  /// scanning stops (timeout or [stopScan] called).
  ///
  /// [services] - Optional list of service UUIDs to filter by.
  /// [timeout] - Optional timeout duration.
  ///
  /// Example:
  /// ```dart
  /// await for (final device in bluey.scan(timeout: Duration(seconds: 10))) {
  ///   print('Found: ${device.name}');
  /// }
  /// ```
  Stream<Device> scan({List<UUID>? services, Duration? timeout}) {
    final config = platform.PlatformScanConfig(
      serviceUuids: services?.map((u) => u.toString()).toList() ?? [],
      timeoutMs: timeout?.inMilliseconds,
    );

    return _platform
        .scan(config)
        .map(_mapDevice)
        .handleError((error) => throw _wrapError(error));
  }

  /// Stop scanning for devices.
  Future<void> stopScan() async {
    try {
      await _platform.stopScan();
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

    try {
      // Use platformId for the actual connection (MAC address on Android)
      final connectionId = await _platform.connect(device.platformId, config);

      return BlueyConnection(
        platformInstance: _platform,
        connectionId: connectionId,
        deviceId: device.id,
      );
    } catch (e) {
      throw _wrapError(e);
    }
  }

  /// Create a GATT server for peripheral role.
  ///
  /// Returns a [Server] for advertising services and handling requests
  /// from central devices.
  ///
  /// Returns null on platforms that don't support peripheral role.
  /// Check [capabilities.canAdvertise] before calling.
  ///
  /// Example:
  /// ```dart
  /// final server = bluey.server();
  /// if (server != null) {
  ///   server.addService(myService);
  ///   await server.startAdvertising(name: 'My Device');
  /// }
  /// ```
  Server? server() {
    if (!_platform.capabilities.canAdvertise) {
      return null;
    }
    return BlueyServer(_platform);
  }

  /// Release all resources.
  ///
  /// After calling dispose, this instance cannot be used.
  /// The singleton is cleared, so a new instance can be created.
  Future<void> dispose() async {
    await _stateSubscription?.cancel();
    await _stateController.close();
    await _errorController.close();
    _instance = null;
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

  Device _mapDevice(platform.PlatformDevice platformDevice) {
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

    // Create device
    // Note: On Android, the device ID is a MAC address, not a UUID.
    // We create a UUID from the MAC by padding it, but preserve the original
    // platformId for connections.
    return Device(
      id: _deviceIdToUuid(platformDevice.id),
      platformId: platformDevice.id, // Keep original for platform calls
      name: platformDevice.name,
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
