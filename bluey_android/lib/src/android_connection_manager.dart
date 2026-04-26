import 'dart:async';
import 'dart:typed_data';
import 'package:bluey_platform_interface/bluey_platform_interface.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'messages.g.dart';

/// Catches a [PlatformException] thrown by Pigeon and re-throws it as the
/// matching typed platform-interface exception:
///
///   * `'gatt-timeout'` → [GattOperationTimeoutException]
///   * `'gatt-disconnected'` → [GattOperationDisconnectedException]
///   * `'gatt-status-failed'` → [GattOperationStatusFailedException] with
///     the native status extracted from `details`.
///   * `'bluey-permission-denied'` → [PlatformPermissionDeniedException]
///
/// Other errors propagate unchanged.
///
/// Kept package-private so the same wrapper can be used by every GATT
/// operation in this file without leaking translation logic into the
/// platform interface contract.
Future<T> _translateGattPlatformError<T>(
  String operation,
  Future<T> Function() body,
) async {
  try {
    return await body();
  } on PlatformException catch (e) {
    if (e.code == 'gatt-timeout') {
      throw GattOperationTimeoutException(operation);
    }
    if (e.code == 'gatt-disconnected') {
      throw GattOperationDisconnectedException(operation);
    }
    if (e.code == 'gatt-status-failed') {
      // Native status arrives in `details` as an int. Sentinel -1 handles
      // the rare marshaling paths where it could come back null / non-int.
      final status = e.details is int ? e.details as int : -1;
      throw GattOperationStatusFailedException(operation, status);
    }
    if (e.code == 'bluey-permission-denied') {
      final permission = e.details is String ? e.details as String : 'unknown';
      throw PlatformPermissionDeniedException(
        operation,
        permission: permission,
        message: e.message,
      );
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
    return _translateGattPlatformError('discoverServices', () async {
      final services = await _hostApi.discoverServices(deviceId);
      return services.map(_mapService).toList();
    });
  }

  /// Reads a characteristic value from the connected device.
  Future<Uint8List> readCharacteristic(
    String deviceId,
    String characteristicUuid,
  ) async {
    return _translateGattPlatformError(
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
    return _translateGattPlatformError(
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
    return _translateGattPlatformError(
      'setNotification',
      () => _hostApi.setNotification(deviceId, characteristicUuid, enable),
    );
  }

  /// Reads a descriptor value from the connected device.
  Future<Uint8List> readDescriptor(
    String deviceId,
    String descriptorUuid,
  ) async {
    return _translateGattPlatformError(
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
    return _translateGattPlatformError(
      'writeDescriptor',
      () => _hostApi.writeDescriptor(deviceId, descriptorUuid, value),
    );
  }

  /// Requests a new MTU size for the connection.
  Future<int> requestMtu(String deviceId, int mtu) async {
    return _translateGattPlatformError(
      'requestMtu',
      () => _hostApi.requestMtu(deviceId, mtu),
    );
  }

  /// Reads the RSSI for the connected device.
  Future<int> readRssi(String deviceId) async {
    return _translateGattPlatformError(
      'readRssi',
      () => _hostApi.readRssi(deviceId),
    );
  }

  // === Bonding (unimplemented; see I035) ===
  //
  // The Pigeon schema does not yet declare bond/PHY/connection-parameter
  // operations, so the Dart-side adapter has nothing to delegate to.
  // Until the Pigeon plumbing lands (Stage B), the stubs throw
  // UnimplementedError rather than silently returning hardcoded values
  // so the API does not lie to callers. Companion change in
  // `Capabilities.android` flips `canBond` to false so the capability
  // matrix reflects reality.

  /// Returns the bond state for a device.
  Future<PlatformBondState> getBondState(String deviceId) async {
    throw UnimplementedError('Android: getBondState not yet implemented (I035)');
  }

  /// Returns a stream of bond state changes for a device.
  Stream<PlatformBondState> bondStateStream(String deviceId) {
    throw UnimplementedError(
      'Android: bondStateStream not yet implemented (I035)',
    );
  }

  /// Initiates bonding with a device.
  Future<void> bond(String deviceId) async {
    throw UnimplementedError('Android: bond not yet implemented (I035)');
  }

  /// Removes the bond with a device.
  Future<void> removeBond(String deviceId) async {
    throw UnimplementedError('Android: removeBond not yet implemented (I035)');
  }

  /// Returns all bonded devices.
  Future<List<PlatformDevice>> getBondedDevices() async {
    throw UnimplementedError(
      'Android: getBondedDevices not yet implemented (I035)',
    );
  }

  // === PHY (unimplemented; see I035) ===

  /// Returns the current PHY for a device.
  Future<({PlatformPhy tx, PlatformPhy rx})> getPhy(String deviceId) async {
    throw UnimplementedError('Android: getPhy not yet implemented (I035)');
  }

  /// Returns a stream of PHY changes for a device.
  Stream<({PlatformPhy tx, PlatformPhy rx})> phyStream(String deviceId) {
    throw UnimplementedError('Android: phyStream not yet implemented (I035)');
  }

  /// Requests a PHY change for a device.
  Future<void> requestPhy(
    String deviceId,
    PlatformPhy? txPhy,
    PlatformPhy? rxPhy,
  ) async {
    throw UnimplementedError('Android: requestPhy not yet implemented (I035)');
  }

  // === Connection Parameters (unimplemented; see I035) ===

  /// Returns the connection parameters for a device.
  Future<PlatformConnectionParameters> getConnectionParameters(
    String deviceId,
  ) async {
    throw UnimplementedError(
      'Android: getConnectionParameters not yet implemented (I035)',
    );
  }

  /// Requests new connection parameters for a device.
  Future<void> requestConnectionParameters(
    String deviceId,
    PlatformConnectionParameters params,
  ) async {
    throw UnimplementedError(
      'Android: requestConnectionParameters not yet implemented (I035)',
    );
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
