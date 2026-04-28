import 'dart:async';
import 'dart:typed_data';
import 'package:bluey_platform_interface/bluey_platform_interface.dart';
import 'messages.g.dart';
import 'uuid_utils.dart';

/// Handles GATT server (peripheral) operations for the iOS platform.
///
/// Delegates to [BlueyHostApi] for native communication and manages
/// streams for central connections, disconnections, and read/write requests.
/// Unlike Android, iOS does not support advertise mode settings and uses
/// `expandUuid` on incoming characteristic UUIDs from CoreBluetooth.
class IosServer {
  final BlueyHostApi _hostApi;

  final StreamController<PlatformCentral> _centralConnectionsController =
      StreamController<PlatformCentral>.broadcast();
  final StreamController<String> _centralDisconnectionsController =
      StreamController<String>.broadcast();
  final StreamController<PlatformReadRequest> _readRequestsController =
      StreamController<PlatformReadRequest>.broadcast();
  final StreamController<PlatformWriteRequest> _writeRequestsController =
      StreamController<PlatformWriteRequest>.broadcast();

  IosServer(this._hostApi);

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

  /// Adds a GATT service to the server.
  Future<void> addService(PlatformLocalService service) async {
    final dto = _mapLocalServiceToDto(service);
    await _hostApi.addService(dto);
  }

  /// Removes a GATT service from the server.
  Future<void> removeService(String serviceUuid) async {
    await _hostApi.removeService(serviceUuid);
  }

  // === Advertising ===

  /// Starts advertising with the given configuration.
  ///
  /// Note: iOS does not support advertise mode settings (that's Android-only).
  Future<void> startAdvertising(PlatformAdvertiseConfig config) async {
    final dto = AdvertiseConfigDto(
      name: config.name,
      serviceUuids: config.serviceUuids,
      manufacturerDataCompanyId: config.manufacturerDataCompanyId,
      manufacturerData: config.manufacturerData,
      timeoutMs: config.timeoutMs,
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
    String characteristicUuid,
    Uint8List value, {
    int? characteristicHandle,
  }) async {
    await _hostApi.notifyCharacteristic(
      characteristicUuid,
      value,
      characteristicHandle,
    );
  }

  /// Sends a notification to a specific central.
  Future<void> notifyCharacteristicTo(
    String centralId,
    String characteristicUuid,
    Uint8List value, {
    int? characteristicHandle,
  }) async {
    await _hostApi.notifyCharacteristicTo(
      centralId,
      characteristicUuid,
      value,
      characteristicHandle,
    );
  }

  /// Sends an indication to all connected centrals.
  ///
  /// iOS uses the same updateValue method for both notifications and
  /// indications. The characteristic's properties determine which is used.
  Future<void> indicateCharacteristic(
    String characteristicUuid,
    Uint8List value, {
    int? characteristicHandle,
  }) async {
    await _hostApi.notifyCharacteristic(
      characteristicUuid,
      value,
      characteristicHandle,
    );
  }

  /// Sends an indication to a specific central.
  ///
  /// iOS uses the same updateValue method for both notifications and
  /// indications. The characteristic's properties determine which is used.
  Future<void> indicateCharacteristicTo(
    String centralId,
    String characteristicUuid,
    Uint8List value, {
    int? characteristicHandle,
  }) async {
    await _hostApi.notifyCharacteristicTo(
      centralId,
      characteristicUuid,
      value,
      characteristicHandle,
    );
  }

  // === Request Handling ===

  /// Responds to a read request from a central.
  Future<void> respondToReadRequest(
    int requestId,
    PlatformGattStatus status,
    Uint8List? value,
  ) async {
    await _hostApi.respondToReadRequest(
      requestId,
      _mapGattStatusToDto(status),
      value,
    );
  }

  /// Responds to a write request from a central.
  Future<void> respondToWriteRequest(
    int requestId,
    PlatformGattStatus status,
  ) async {
    await _hostApi.respondToWriteRequest(
      requestId,
      _mapGattStatusToDto(status),
    );
  }

  // === Client Management ===

  /// Disconnects a connected central.
  Future<void> disconnectCentral(String centralId) async {
    await _hostApi.disconnectCentral(centralId);
  }

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
  ///
  /// Expands short UUIDs from CoreBluetooth to full 128-bit format.
  void onReadRequest(ReadRequestDto request) {
    _readRequestsController.add(
      PlatformReadRequest(
        requestId: request.requestId,
        centralId: request.centralId,
        characteristicUuid: expandUuid(request.characteristicUuid),
        offset: request.offset,
        characteristicHandle: request.characteristicHandle,
      ),
    );
  }

  /// Handles a write request event from the platform.
  ///
  /// Expands short UUIDs from CoreBluetooth to full 128-bit format.
  void onWriteRequest(WriteRequestDto request) {
    _writeRequestsController.add(
      PlatformWriteRequest(
        requestId: request.requestId,
        centralId: request.centralId,
        characteristicUuid: expandUuid(request.characteristicUuid),
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
    );
  }

  LocalDescriptorDto _mapLocalDescriptorToDto(
    PlatformLocalDescriptor descriptor,
  ) {
    return LocalDescriptorDto(
      uuid: descriptor.uuid,
      permissions: descriptor.permissions.map(_mapGattPermissionToDto).toList(),
      value: descriptor.value,
    );
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
}
