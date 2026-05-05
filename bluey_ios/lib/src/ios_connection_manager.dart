import 'dart:async';
import 'dart:typed_data';

import 'package:bluey_platform_interface/bluey_platform_interface.dart';
import 'package:flutter/services.dart' show PlatformException;

import 'messages.g.dart';
import 'uuid_utils.dart';

/// Catches a [PlatformException] thrown by Pigeon and re-throws it as the
/// matching typed platform-interface exception:
///
///   * `'gatt-timeout'` → [GattOperationTimeoutException]
///   * `'gatt-disconnected'` → [GattOperationDisconnectedException]
///   * `'gatt-status-failed'` → [GattOperationStatusFailedException] with
///     the native status extracted from `details`. iOS Swift does not
///     currently emit this code, but the translation is kept symmetric
///     with the Android contract so that any future native-side mapping
///     (e.g. of `CBError` numeric codes) surfaces as the same typed
///     exception.
///   * `'bluey-unknown'` → [GattOperationUnknownPlatformException]
///   * `'gatt-handle-invalidated'` → [GattOperationUnknownPlatformException]
///     preserving the code so the domain layer translates it to the typed
///     `AttributeHandleInvalidatedException`.
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
      final status = e.details is int ? e.details as int : -1;
      throw GattOperationStatusFailedException(operation, status);
    }
    if (e.code == 'bluey-unknown') {
      throw GattOperationUnknownPlatformException(
        operation,
        code: 'bluey-unknown',
        message: e.message,
      );
    }
    if (e.code == 'gatt-handle-invalidated') {
      throw GattOperationUnknownPlatformException(
        operation,
        code: 'gatt-handle-invalidated',
        message: e.message,
      );
    }
    rethrow;
  }
}

/// Handles BLE connection management, GATT client operations, bonding, PHY,
/// and connection parameter stubs for the iOS platform.
///
/// Delegates to [BlueyHostApi] for native communication and manages
/// per-device streams for connection state and notifications. Unlike Android,
/// iOS auto-negotiates MTU and does not expose bonding, PHY, or connection
/// parameter APIs.
class IosConnectionManager {
  final BlueyHostApi _hostApi;

  final Map<String, StreamController<PlatformConnectionState>>
  _connectionStateControllers = {};
  final Map<String, StreamController<PlatformNotification>>
  _notificationControllers = {};

  IosConnectionManager(this._hostApi);

  // === Connection ===

  /// Connects to a device and creates per-device streams.
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

  /// Returns the connection state stream for a connected device.
  Stream<PlatformConnectionState> connectionStateStream(String deviceId) {
    final controller = _connectionStateControllers[deviceId];
    if (controller == null) {
      return Stream.error(StateError('Device not connected: $deviceId'));
    }
    return controller.stream;
  }

  /// Returns the notification stream for a connected device.
  Stream<PlatformNotification> notificationStream(String deviceId) {
    final controller = _notificationControllers[deviceId];
    if (controller == null) {
      return Stream.error(StateError('Device not connected: $deviceId'));
    }
    return controller.stream;
  }

  // === Callback Handlers ===

  /// Handles connection state change events from the platform.
  void onConnectionStateChanged(ConnectionStateEventDto event) {
    final controller = _connectionStateControllers[event.deviceId];
    if (controller != null) {
      controller.add(_mapConnectionState(event.state));
    }
  }

  /// Handles notification events from the platform, expanding short UUIDs.
  void onNotification(NotificationEventDto event) {
    final controller = _notificationControllers[event.deviceId];
    if (controller != null) {
      controller.add(
        PlatformNotification(
          deviceId: event.deviceId,
          characteristicUuid: expandUuid(event.characteristicUuid),
          value: event.value,
        ),
      );
    }
  }

  /// Handles MTU change events from the platform.
  void onMtuChanged(MtuChangedEventDto event) {
    // MTU change callback - no action needed on iOS
  }

  // === GATT Client Operations ===

  /// Discovers services on a connected device, expanding short UUIDs.
  Future<List<PlatformService>> discoverServices(String deviceId) async {
    return _translateGattPlatformError('discoverServices', () async {
      final services = await _hostApi.discoverServices(deviceId);
      return services.map(_mapService).toList();
    });
  }

  /// Reads a characteristic value from a connected device by handle.
  Future<Uint8List> readCharacteristic(
    String deviceId,
    int characteristicHandle,
  ) async {
    return _translateGattPlatformError(
      'readCharacteristic',
      () => _hostApi.readCharacteristic(deviceId, characteristicHandle),
    );
  }

  /// Writes a characteristic value on a connected device by handle.
  Future<void> writeCharacteristic(
    String deviceId,
    int characteristicHandle,
    Uint8List value,
    bool withResponse,
  ) async {
    return _translateGattPlatformError(
      'writeCharacteristic',
      () => _hostApi.writeCharacteristic(
        deviceId,
        characteristicHandle,
        value,
        withResponse,
      ),
    );
  }

  /// Enables or disables notifications for a characteristic by handle.
  Future<void> setNotification(
    String deviceId,
    int characteristicHandle,
    bool enable,
  ) async {
    // Wrapped defensively for Phase 2 — no iOS timeout for setNotification today.
    return _translateGattPlatformError(
      'setNotification',
      () => _hostApi.setNotification(deviceId, characteristicHandle, enable),
    );
  }

  /// Reads a descriptor value from a connected device by handle.
  Future<Uint8List> readDescriptor(
    String deviceId,
    int characteristicHandle,
    int descriptorHandle,
  ) async {
    return _translateGattPlatformError(
      'readDescriptor',
      () => _hostApi.readDescriptor(
        deviceId,
        characteristicHandle,
        descriptorHandle,
      ),
    );
  }

  /// Writes a descriptor value on a connected device by handle.
  Future<void> writeDescriptor(
    String deviceId,
    int characteristicHandle,
    int descriptorHandle,
    Uint8List value,
  ) async {
    return _translateGattPlatformError(
      'writeDescriptor',
      () => _hostApi.writeDescriptor(
        deviceId,
        characteristicHandle,
        descriptorHandle,
        value,
      ),
    );
  }

  /// Reads the current RSSI for a connected device.
  Future<int> readRssi(String deviceId) async {
    return _translateGattPlatformError(
      'readRssi',
      () => _hostApi.readRssi(deviceId),
    );
  }

  /// iOS automatically negotiates MTU; requesting a specific MTU is
  /// not supported.
  Future<int> requestMtu(String deviceId, int mtu) async {
    throw UnsupportedError(
      'iOS does not support requesting a specific MTU. '
      'MTU is automatically negotiated by the system.',
    );
  }

  /// Largest single ATT write payload the platform will accept for the
  /// active connection. Forwards to
  /// `CBPeripheral.maximumWriteValueLength(for:)` via Pigeon.
  Future<int> getMaximumWriteLength(
    String deviceId, {
    required bool withResponse,
  }) async {
    return _translateGattPlatformError(
      'getMaximumWriteLength',
      () => _hostApi.getMaximumWriteLength(deviceId, withResponse),
    );
  }

  // === Bonding (iOS handles automatically) ===

  /// iOS does not expose bond state; always returns [PlatformBondState.none].
  Future<PlatformBondState> getBondState(String deviceId) async {
    return PlatformBondState.none;
  }

  /// iOS does not expose bond state changes; returns an empty stream.
  Stream<PlatformBondState> bondStateStream(String deviceId) {
    return const Stream.empty();
  }

  /// iOS handles bonding automatically when accessing encrypted
  /// characteristics. This is a no-op.
  Future<void> bond(String deviceId) async {
    // No-op on iOS
  }

  /// iOS does not allow programmatic bond removal.
  Future<void> removeBond(String deviceId) async {
    throw UnsupportedError(
      'iOS does not support removing bonds programmatically. '
      'Users must remove the device from Settings > Bluetooth.',
    );
  }

  /// iOS does not provide a list of bonded devices.
  Future<List<PlatformDevice>> getBondedDevices() async {
    return [];
  }

  // === PHY (limited iOS support) ===

  /// iOS does not expose PHY information.
  Future<({PlatformPhy tx, PlatformPhy rx})> getPhy(String deviceId) async {
    throw UnsupportedError('iOS does not support reading PHY information.');
  }

  /// iOS does not expose PHY changes; returns an empty stream.
  Stream<({PlatformPhy tx, PlatformPhy rx})> phyStream(String deviceId) {
    return const Stream.empty();
  }

  /// iOS does not support requesting PHY settings.
  Future<void> requestPhy(
    String deviceId,
    PlatformPhy? txPhy,
    PlatformPhy? rxPhy,
  ) async {
    throw UnsupportedError('iOS does not support requesting PHY settings.');
  }

  // === Connection Parameters (not available on iOS) ===

  /// iOS does not support reading connection parameters.
  Future<PlatformConnectionParameters> getConnectionParameters(
    String deviceId,
  ) async {
    throw UnsupportedError(
      'iOS does not support reading connection parameters.',
    );
  }

  /// iOS does not support requesting connection parameters.
  Future<void> requestConnectionParameters(
    String deviceId,
    PlatformConnectionParameters params,
  ) async {
    throw UnsupportedError(
      'iOS does not support requesting connection parameters.',
    );
  }

  // === DTO Mapping ===

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
      uuid: expandUuid(dto.uuid),
      isPrimary: dto.isPrimary,
      characteristics: dto.characteristics.map(_mapCharacteristic).toList(),
      includedServices: dto.includedServices.map(_mapService).toList(),
    );
  }

  PlatformCharacteristic _mapCharacteristic(CharacteristicDto dto) {
    return PlatformCharacteristic(
      uuid: expandUuid(dto.uuid),
      properties: PlatformCharacteristicProperties(
        canRead: dto.properties.canRead,
        canWrite: dto.properties.canWrite,
        canWriteWithoutResponse: dto.properties.canWriteWithoutResponse,
        canNotify: dto.properties.canNotify,
        canIndicate: dto.properties.canIndicate,
      ),
      descriptors: dto.descriptors.map(_mapDescriptor).toList(),
      handle: dto.handle,
    );
  }

  PlatformDescriptor _mapDescriptor(DescriptorDto dto) {
    return PlatformDescriptor(uuid: expandUuid(dto.uuid), handle: dto.handle);
  }
}
