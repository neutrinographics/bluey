import 'dart:async';
import 'dart:typed_data';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;

import 'connection_state.dart';
import 'device.dart';
import 'exceptions.dart';
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
  final platform.BlueyPlatform _platform;

  StreamSubscription? _stateSubscription;
  final StreamController<BluetoothState> _stateController =
      StreamController<BluetoothState>.broadcast();

  /// Creates a new Bluey instance.
  ///
  /// Typically you create one instance and reuse it throughout your app.
  /// Call [dispose] when done to release resources.
  Bluey() : _platform = platform.BlueyPlatform.instance {
    _stateSubscription = _platform.stateStream.listen(
      (state) => _stateController.add(_mapState(state)),
      onError: (error) => _stateController.addError(_wrapError(error)),
    );
  }

  /// Platform capabilities.
  platform.Capabilities get capabilities => _platform.capabilities;

  /// Stream of Bluetooth state changes.
  ///
  /// Emits whenever Bluetooth is enabled, disabled, or permissions change.
  Stream<BluetoothState> get stateStream => _stateController.stream;

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
  Stream<Device> scan({
    List<UUID>? services,
    Duration? timeout,
  }) {
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
  /// Returns a stream of connection state changes.
  /// Throws [ConnectionException] if connection fails.
  Future<Stream<ConnectionState>> connect(
    Device device, {
    Duration? timeout,
  }) async {
    final config = platform.PlatformConnectConfig(
      timeoutMs: timeout?.inMilliseconds,
      mtu: null,
    );

    try {
      final connectionId =
          await _platform.connect(device.id.toString(), config);
      return _platform
          .connectionStateStream(connectionId)
          .map(_mapConnectionState)
          .handleError((error) => throw _wrapError(error));
    } catch (e) {
      throw _wrapError(e);
    }
  }

  /// Disconnect from a device.
  Future<void> disconnect(Device device) async {
    try {
      await _platform.disconnect(device.id.toString());
    } catch (e) {
      throw _wrapError(e);
    }
  }

  /// Release all resources.
  ///
  /// After calling dispose, this instance cannot be used.
  Future<void> dispose() async {
    await _stateSubscription?.cancel();
    await _stateController.close();
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
      platform.PlatformConnectionState platformState) {
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
    // We create a UUID from the MAC by padding it.
    return Device(
      id: _deviceIdToUuid(platformDevice.id),
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

  /// Wraps platform errors in domain exceptions.
  BlueyException _wrapError(Object error) {
    if (error is BlueyException) {
      return error;
    }

    // Convert common platform errors to domain exceptions
    final message = error.toString();

    if (message.contains('permission') || message.contains('unauthorized')) {
      return PermissionDeniedException(['Bluetooth']);
    }

    if (message.contains('disabled') || message.contains('off')) {
      return const BluetoothDisabledException();
    }

    if (message.contains('unavailable') || message.contains('unsupported')) {
      return const BluetoothUnavailableException();
    }

    if (message.contains('timeout')) {
      return ConnectionException(
        UUID.short(0x0000), // Unknown device
        ConnectionFailureReason.timeout,
      );
    }

    // Generic fallback
    return ConnectionException(
      UUID.short(0x0000),
      ConnectionFailureReason.unknown,
    );
  }
}
