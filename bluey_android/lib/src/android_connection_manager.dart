import 'dart:async';
import 'dart:typed_data';
import 'package:bluey_platform_interface/bluey_platform_interface.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'messages.g.dart';

/// Catches a [PlatformException] thrown by Pigeon and re-throws it as a
/// [GattOperationTimeoutException] when the platform error code is
/// `'gatt-timeout'`. Other errors propagate unchanged.
///
/// Kept package-private so the same wrapper can be used by every GATT
/// operation in this file without leaking translation logic into the
/// platform interface contract.
Future<T> _translateGattTimeout<T>(
  String operation,
  Future<T> Function() body,
) async {
  try {
    return await body();
  } on PlatformException catch (e) {
    if (e.code == 'gatt-timeout') {
      throw GattOperationTimeoutException(operation);
    }
    rethrow;
  }
}

/// Handles BLE connection management, GATT client operations,
/// bonding, PHY, and connection parameter stubs for the Android platform.
///
/// Delegates to [BlueyHostApi] for native communication and manages
/// per-device stream controllers for connection state and notifications.
class AndroidConnectionManager {
  final BlueyHostApi _hostApi;
  final Map<String, StreamController<PlatformConnectionState>>
      _connectionStateControllers = {};
  final Map<String, StreamController<PlatformNotification>>
      _notificationControllers = {};

  AndroidConnectionManager(this._hostApi);

  // === Connection ===

  /// Connects to a device and returns the connection ID.
  ///
  /// Creates per-device stream controllers for connection state
  /// and notifications.
  Future<String> connect(String deviceId, PlatformConnectConfig config) async {
    final dto = ConnectConfigDto(timeoutMs: config.timeoutMs, mtu: config.mtu);

    _connectionStateControllers[deviceId] =
        StreamController<PlatformConnectionState>.broadcast();

    _notificationControllers[deviceId] =
        StreamController<PlatformNotification>.broadcast();

    return await _hostApi.connect(deviceId, dto);
  }

  /// Disconnects from a device and cleans up per-device streams.
  Future<void> disconnect(String deviceId) async {
    await _hostApi.disconnect(deviceId);

    final stateController = _connectionStateControllers.remove(deviceId);
    await stateController?.close();

    final notificationController = _notificationControllers.remove(deviceId);
    await notificationController?.close();
  }

  /// Returns the connection state stream for the given device.
  ///
  /// Returns an error stream if the device is not connected.
  Stream<PlatformConnectionState> connectionStateStream(String deviceId) {
    final controller = _connectionStateControllers[deviceId];
    if (controller == null) {
      return Stream.error(StateError('Device not connected: $deviceId'));
    }
    return controller.stream;
  }

  /// Returns the notification stream for the given device.
  ///
  /// Returns an error stream if the device is not connected.
  Stream<PlatformNotification> notificationStream(String deviceId) {
    final controller = _notificationControllers[deviceId];
    if (controller == null) {
      return Stream.error(StateError('Device not connected: $deviceId'));
    }
    return controller.stream;
  }

  // === GATT Client Operations ===

  /// Discovers services on the connected device.
  Future<List<PlatformService>> discoverServices(String deviceId) async {
    return _translateGattTimeout('discoverServices', () async {
      final services = await _hostApi.discoverServices(deviceId);
      return services.map(_mapService).toList();
    });
  }

  /// Reads a characteristic value from the connected device.
  Future<Uint8List> readCharacteristic(
    String deviceId,
    String characteristicUuid,
  ) async {
    return _translateGattTimeout(
      'readCharacteristic',
      () => _hostApi.readCharacteristic(deviceId, characteristicUuid),
    );
  }

  /// Writes a characteristic value on the connected device.
  Future<void> writeCharacteristic(
    String deviceId,
    String characteristicUuid,
    Uint8List value,
    bool withResponse,
  ) async {
    return _translateGattTimeout(
      'writeCharacteristic',
      () => _hostApi.writeCharacteristic(
        deviceId,
        characteristicUuid,
        value,
        withResponse,
      ),
    );
  }

  /// Enables or disables notifications for a characteristic.
  Future<void> setNotification(
    String deviceId,
    String characteristicUuid,
    bool enable,
  ) async {
    // Wrapped defensively for Phase 2 — no Android timeout for setNotification today.
    return _translateGattTimeout(
      'setNotification',
      () => _hostApi.setNotification(deviceId, characteristicUuid, enable),
    );
  }

  /// Reads a descriptor value from the connected device.
  Future<Uint8List> readDescriptor(
    String deviceId,
    String descriptorUuid,
  ) async {
    return _translateGattTimeout(
      'readDescriptor',
      () => _hostApi.readDescriptor(deviceId, descriptorUuid),
    );
  }

  /// Writes a descriptor value on the connected device.
  Future<void> writeDescriptor(
    String deviceId,
    String descriptorUuid,
    Uint8List value,
  ) async {
    return _translateGattTimeout(
      'writeDescriptor',
      () => _hostApi.writeDescriptor(deviceId, descriptorUuid, value),
    );
  }

  /// Requests a new MTU size for the connection.
  Future<int> requestMtu(String deviceId, int mtu) async {
    return _translateGattTimeout(
      'requestMtu',
      () => _hostApi.requestMtu(deviceId, mtu),
    );
  }

  /// Reads the RSSI for the connected device.
  Future<int> readRssi(String deviceId) async {
    return _translateGattTimeout(
      'readRssi',
      () => _hostApi.readRssi(deviceId),
    );
  }

  // === Bonding Stubs ===

  /// Returns the bond state for a device.
  Future<PlatformBondState> getBondState(String deviceId) async {
    // TODO: Implement when Android Pigeon API supports bonding
    return PlatformBondState.none;
  }

  /// Returns a stream of bond state changes for a device.
  Stream<PlatformBondState> bondStateStream(String deviceId) {
    // TODO: Implement when Android Pigeon API supports bonding
    return const Stream.empty();
  }

  /// Initiates bonding with a device.
  Future<void> bond(String deviceId) async {
    // TODO: Implement when Android Pigeon API supports bonding
  }

  /// Removes the bond with a device.
  Future<void> removeBond(String deviceId) async {
    // TODO: Implement when Android Pigeon API supports bonding
  }

  /// Returns all bonded devices.
  Future<List<PlatformDevice>> getBondedDevices() async {
    // TODO: Implement when Android Pigeon API supports bonding
    return [];
  }

  // === PHY Stubs ===

  /// Returns the current PHY for a device.
  Future<({PlatformPhy tx, PlatformPhy rx})> getPhy(String deviceId) async {
    // TODO: Implement when Android Pigeon API supports PHY
    return (tx: PlatformPhy.le1m, rx: PlatformPhy.le1m);
  }

  /// Returns a stream of PHY changes for a device.
  Stream<({PlatformPhy tx, PlatformPhy rx})> phyStream(String deviceId) {
    // TODO: Implement when Android Pigeon API supports PHY
    return const Stream.empty();
  }

  /// Requests a PHY change for a device.
  Future<void> requestPhy(
    String deviceId,
    PlatformPhy? txPhy,
    PlatformPhy? rxPhy,
  ) async {
    // TODO: Implement when Android Pigeon API supports PHY
  }

  // === Connection Parameters Stubs ===

  /// Returns the connection parameters for a device.
  Future<PlatformConnectionParameters> getConnectionParameters(
    String deviceId,
  ) async {
    // TODO: Implement when Android Pigeon API supports connection parameters
    return const PlatformConnectionParameters(
      intervalMs: 30,
      latency: 0,
      timeoutMs: 5000,
    );
  }

  /// Requests new connection parameters for a device.
  Future<void> requestConnectionParameters(
    String deviceId,
    PlatformConnectionParameters params,
  ) async {
    // TODO: Implement when Android Pigeon API supports connection parameters
  }

  // === Callback Handlers ===

  /// Handles connection state change events from the platform.
  void onConnectionStateChanged(ConnectionStateEventDto event) {
    final controller = _connectionStateControllers[event.deviceId];
    if (controller != null) {
      controller.add(_mapConnectionState(event.state));
    }
  }

  /// Handles notification events from the platform.
  void onNotification(NotificationEventDto event) {
    final controller = _notificationControllers[event.deviceId];
    if (controller != null) {
      controller.add(
        PlatformNotification(
          deviceId: event.deviceId,
          characteristicUuid: event.characteristicUuid,
          value: event.value,
        ),
      );
    }
  }

  /// Handles MTU changed events from the platform.
  void onMtuChanged(MtuChangedEventDto event) {
    // MTU change is also reflected through the callback
    // Currently we don't expose this as a separate stream
  }

  // === Private Mapping ===

  PlatformConnectionState _mapConnectionState(ConnectionStateDto dto) {
    switch (dto) {
      case ConnectionStateDto.disconnected:
        return PlatformConnectionState.disconnected;
      case ConnectionStateDto.connecting:
        return PlatformConnectionState.connecting;
      case ConnectionStateDto.connected:
        return PlatformConnectionState.connected;
      case ConnectionStateDto.disconnecting:
        return PlatformConnectionState.disconnecting;
    }
  }

  PlatformService _mapService(ServiceDto dto) {
    return PlatformService(
      uuid: dto.uuid,
      isPrimary: dto.isPrimary,
      characteristics: dto.characteristics.map(_mapCharacteristic).toList(),
      includedServices: dto.includedServices.map(_mapService).toList(),
    );
  }

  PlatformCharacteristic _mapCharacteristic(CharacteristicDto dto) {
    return PlatformCharacteristic(
      uuid: dto.uuid,
      properties: PlatformCharacteristicProperties(
        canRead: dto.properties.canRead,
        canWrite: dto.properties.canWrite,
        canWriteWithoutResponse: dto.properties.canWriteWithoutResponse,
        canNotify: dto.properties.canNotify,
        canIndicate: dto.properties.canIndicate,
      ),
      descriptors: dto.descriptors.map(_mapDescriptor).toList(),
    );
  }

  PlatformDescriptor _mapDescriptor(DescriptorDto dto) {
    return PlatformDescriptor(uuid: dto.uuid);
  }
}
