import 'dart:async';
import 'dart:typed_data';
import 'package:bluey_platform_interface/bluey_platform_interface.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'messages.g.dart';

/// Catches a [PlatformException] thrown by Pigeon and re-throws it as the
/// matching typed platform-interface exception for server-side operations:
///
///   * `'gatt-status-failed'` → [GattOperationStatusFailedException] with
///     the native status extracted from `details`.
///
/// Other errors propagate unchanged.
///
/// Kept package-private so the same wrapper can be used by every server
/// operation in this file without leaking translation logic into the
/// platform interface contract.
Future<T> _translateServerPlatformError<T>(
  String operation,
  Future<T> Function() body,
) async {
  try {
    return await body();
  } on PlatformException catch (e) {
    if (e.code == 'gatt-status-failed') {
      // Native status arrives in `details` as an int. Sentinel -1 handles
      // the rare marshaling paths where it could come back null / non-int.
      final status = e.details is int ? e.details as int : -1;
      throw GattOperationStatusFailedException(operation, status);
    }
    rethrow;
  }
}

/// Handles GATT server (peripheral) operations for the Android platform.
///
/// Delegates to [BlueyHostApi] for native communication and manages
/// streams for central connections, disconnections, and read/write requests.
class AndroidServer {
  final BlueyHostApi _hostApi;

  final StreamController<PlatformCentral> _centralConnectionsController =
      StreamController<PlatformCentral>.broadcast();
  final StreamController<String> _centralDisconnectionsController =
      StreamController<String>.broadcast();
  final StreamController<PlatformReadRequest> _readRequestsController =
      StreamController<PlatformReadRequest>.broadcast();
  final StreamController<PlatformWriteRequest> _writeRequestsController =
      StreamController<PlatformWriteRequest>.broadcast();

  AndroidServer(this._hostApi);

  // === Stream Getters ===

  /// Stream of central devices that connect to the server.
  Stream<PlatformCentral> get centralConnections =>
      _centralConnectionsController.stream;

  /// Stream of central device IDs that disconnect from the server.
  Stream<String> get centralDisconnections =>
      _centralDisconnectionsController.stream;

  /// Stream of read requests from connected centrals.
  Stream<PlatformReadRequest> get readRequests =>
      _readRequestsController.stream;

  /// Stream of write requests from connected centrals.
  Stream<PlatformWriteRequest> get writeRequests =>
      _writeRequestsController.stream;

  // === Service Management ===

  /// Adds a GATT service to the server. Returns the service with all
  /// characteristic and descriptor handles populated by the platform.
  Future<PlatformLocalService> addService(PlatformLocalService service) async {
    final dto = _mapLocalServiceToDto(service);
    final populated = await _hostApi.addService(dto);
    return _mapLocalServiceFromDto(populated);
  }

  /// Removes a GATT service from the server.
  Future<void> removeService(String serviceUuid) async {
    await _hostApi.removeService(serviceUuid);
  }

  // === Advertising ===

  /// Starts advertising with the given configuration.
  Future<void> startAdvertising(PlatformAdvertiseConfig config) async {
    final dto = AdvertiseConfigDto(
      name: config.name,
      serviceUuids: config.serviceUuids,
      manufacturerDataCompanyId: config.manufacturerDataCompanyId,
      manufacturerData: config.manufacturerData,
      timeoutMs: config.timeoutMs,
      mode: _mapAdvertiseModeToDto(config.mode),
    );
    await _hostApi.startAdvertising(dto);
  }

  /// Stops advertising.
  Future<void> stopAdvertising() async {
    await _hostApi.stopAdvertising();
  }

  // === Notifications / Indications ===

  /// Sends a notification to all connected centrals.
  Future<void> notifyCharacteristic(
    int characteristicHandle,
    Uint8List value,
  ) async {
    await _hostApi.notifyCharacteristic(characteristicHandle, value);
  }

  /// Sends a notification to a specific central.
  Future<void> notifyCharacteristicTo(
    String centralId,
    int characteristicHandle,
    Uint8List value,
  ) async {
    await _hostApi.notifyCharacteristicTo(
      centralId,
      characteristicHandle,
      value,
    );
  }

  /// Sends an indication to all connected centrals.
  ///
  /// Android uses the same API for notifications and indications.
  /// The characteristic's properties determine which is used.
  Future<void> indicateCharacteristic(
    int characteristicHandle,
    Uint8List value,
  ) async {
    await _hostApi.notifyCharacteristic(characteristicHandle, value);
  }

  /// Sends an indication to a specific central.
  ///
  /// Android uses the same API for notifications and indications.
  /// The characteristic's properties determine which is used.
  Future<void> indicateCharacteristicTo(
    String centralId,
    int characteristicHandle,
    Uint8List value,
  ) async {
    await _hostApi.notifyCharacteristicTo(
      centralId,
      characteristicHandle,
      value,
    );
  }

  // === Request Handling ===

  /// Responds to a read request from a central.
  Future<void> respondToReadRequest(
    int requestId,
    PlatformGattStatus status,
    Uint8List? value,
  ) async {
    await _translateServerPlatformError(
      'respondToReadRequest',
      () => _hostApi.respondToReadRequest(
        requestId,
        _mapGattStatusToDto(status),
        value,
      ),
    );
  }

  /// Responds to a write request from a central.
  Future<void> respondToWriteRequest(
    int requestId,
    PlatformGattStatus status,
  ) async {
    await _translateServerPlatformError(
      'respondToWriteRequest',
      () => _hostApi.respondToWriteRequest(
        requestId,
        _mapGattStatusToDto(status),
      ),
    );
  }

  // === Client Management ===

  /// Closes the GATT server.
  Future<void> closeServer() async {
    await _hostApi.closeServer();
  }

  // === Callback Handlers ===

  /// Handles a central connection event from the platform.
  void onCentralConnected(CentralDto central) {
    _centralConnectionsController.add(
      PlatformCentral(id: central.id, mtu: central.mtu),
    );
  }

  /// Handles a central disconnection event from the platform.
  void onCentralDisconnected(String centralId) {
    _centralDisconnectionsController.add(centralId);
  }

  /// Handles a read request event from the platform.
  void onReadRequest(ReadRequestDto request) {
    _readRequestsController.add(
      PlatformReadRequest(
        requestId: request.requestId,
        centralId: request.centralId,
        characteristicUuid: request.characteristicUuid,
        offset: request.offset,
        characteristicHandle: request.characteristicHandle,
      ),
    );
  }

  /// Handles a write request event from the platform.
  void onWriteRequest(WriteRequestDto request) {
    _writeRequestsController.add(
      PlatformWriteRequest(
        requestId: request.requestId,
        centralId: request.centralId,
        characteristicUuid: request.characteristicUuid,
        value: request.value,
        offset: request.offset,
        responseNeeded: request.responseNeeded,
        characteristicHandle: request.characteristicHandle,
      ),
    );
  }

  // === Private Mapping ===

  LocalServiceDto _mapLocalServiceToDto(PlatformLocalService service) {
    return LocalServiceDto(
      uuid: service.uuid,
      isPrimary: service.isPrimary,
      characteristics:
          service.characteristics.map(_mapLocalCharacteristicToDto).toList(),
      includedServices:
          service.includedServices.map(_mapLocalServiceToDto).toList(),
    );
  }

  LocalCharacteristicDto _mapLocalCharacteristicToDto(
    PlatformLocalCharacteristic characteristic,
  ) {
    return LocalCharacteristicDto(
      uuid: characteristic.uuid,
      properties: CharacteristicPropertiesDto(
        canRead: characteristic.properties.canRead,
        canWrite: characteristic.properties.canWrite,
        canWriteWithoutResponse:
            characteristic.properties.canWriteWithoutResponse,
        canNotify: characteristic.properties.canNotify,
        canIndicate: characteristic.properties.canIndicate,
      ),
      permissions:
          characteristic.permissions.map(_mapGattPermissionToDto).toList(),
      descriptors:
          characteristic.descriptors.map(_mapLocalDescriptorToDto).toList(),
      handle: characteristic.handle,
    );
  }

  LocalDescriptorDto _mapLocalDescriptorToDto(
    PlatformLocalDescriptor descriptor,
  ) {
    return LocalDescriptorDto(
      uuid: descriptor.uuid,
      permissions: descriptor.permissions.map(_mapGattPermissionToDto).toList(),
      value: descriptor.value,
      handle: descriptor.handle,
    );
  }

  PlatformLocalService _mapLocalServiceFromDto(LocalServiceDto dto) {
    return PlatformLocalService(
      uuid: dto.uuid,
      isPrimary: dto.isPrimary,
      characteristics:
          dto.characteristics.map(_mapLocalCharacteristicFromDto).toList(),
      includedServices:
          dto.includedServices.map(_mapLocalServiceFromDto).toList(),
    );
  }

  PlatformLocalCharacteristic _mapLocalCharacteristicFromDto(
    LocalCharacteristicDto dto,
  ) {
    return PlatformLocalCharacteristic(
      uuid: dto.uuid,
      properties: PlatformCharacteristicProperties(
        canRead: dto.properties.canRead,
        canWrite: dto.properties.canWrite,
        canWriteWithoutResponse: dto.properties.canWriteWithoutResponse,
        canNotify: dto.properties.canNotify,
        canIndicate: dto.properties.canIndicate,
      ),
      permissions: dto.permissions.map(_mapGattPermissionFromDto).toList(),
      descriptors: dto.descriptors.map(_mapLocalDescriptorFromDto).toList(),
      handle: dto.handle,
    );
  }

  PlatformLocalDescriptor _mapLocalDescriptorFromDto(LocalDescriptorDto dto) {
    return PlatformLocalDescriptor(
      uuid: dto.uuid,
      permissions: dto.permissions.map(_mapGattPermissionFromDto).toList(),
      value: dto.value,
      handle: dto.handle,
    );
  }

  PlatformGattPermission _mapGattPermissionFromDto(GattPermissionDto dto) {
    switch (dto) {
      case GattPermissionDto.read:
        return PlatformGattPermission.read;
      case GattPermissionDto.readEncrypted:
        return PlatformGattPermission.readEncrypted;
      case GattPermissionDto.write:
        return PlatformGattPermission.write;
      case GattPermissionDto.writeEncrypted:
        return PlatformGattPermission.writeEncrypted;
    }
  }

  GattPermissionDto _mapGattPermissionToDto(PlatformGattPermission permission) {
    switch (permission) {
      case PlatformGattPermission.read:
        return GattPermissionDto.read;
      case PlatformGattPermission.readEncrypted:
        return GattPermissionDto.readEncrypted;
      case PlatformGattPermission.write:
        return GattPermissionDto.write;
      case PlatformGattPermission.writeEncrypted:
        return GattPermissionDto.writeEncrypted;
    }
  }

  GattStatusDto _mapGattStatusToDto(PlatformGattStatus status) {
    switch (status) {
      case PlatformGattStatus.success:
        return GattStatusDto.success;
      case PlatformGattStatus.readNotPermitted:
        return GattStatusDto.readNotPermitted;
      case PlatformGattStatus.writeNotPermitted:
        return GattStatusDto.writeNotPermitted;
      case PlatformGattStatus.invalidOffset:
        return GattStatusDto.invalidOffset;
      case PlatformGattStatus.invalidAttributeLength:
        return GattStatusDto.invalidAttributeLength;
      case PlatformGattStatus.insufficientAuthentication:
        return GattStatusDto.insufficientAuthentication;
      case PlatformGattStatus.insufficientEncryption:
        return GattStatusDto.insufficientEncryption;
      case PlatformGattStatus.requestNotSupported:
        return GattStatusDto.requestNotSupported;
    }
  }

  AdvertiseModeDto? _mapAdvertiseModeToDto(PlatformAdvertiseMode? mode) {
    if (mode == null) return null;
    switch (mode) {
      case PlatformAdvertiseMode.lowPower:
        return AdvertiseModeDto.lowPower;
      case PlatformAdvertiseMode.balanced:
        return AdvertiseModeDto.balanced;
      case PlatformAdvertiseMode.lowLatency:
        return AdvertiseModeDto.lowLatency;
    }
  }
}
