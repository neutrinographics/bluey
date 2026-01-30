import 'dart:async';
import 'dart:typed_data';

import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;

import 'device.dart';
import 'server.dart';
import 'uuid.dart';

/// Concrete implementation of [Server] that delegates to the platform.
class BlueyServer implements Server {
  final platform.BlueyPlatform _platform;

  bool _isAdvertising = false;
  final Map<String, BlueyCentral> _connectedCentrals = {};

  final StreamController<Central> _connectionsController =
      StreamController<Central>.broadcast();

  StreamSubscription? _centralConnectionsSub;
  StreamSubscription? _centralDisconnectionsSub;

  BlueyServer(this._platform) {
    _centralConnectionsSub = _platform.centralConnections.listen(
      (platformCentral) {
        final central = BlueyCentral(
          platform: _platform,
          id: platformCentral.id,
          mtu: platformCentral.mtu,
        );
        _connectedCentrals[platformCentral.id] = central;
        _connectionsController.add(central);
      },
    );

    _centralDisconnectionsSub = _platform.centralDisconnections.listen(
      (centralId) {
        _connectedCentrals.remove(centralId);
      },
    );
  }

  @override
  bool get isAdvertising => _isAdvertising;

  @override
  Stream<Central> get connections => _connectionsController.stream;

  @override
  List<Central> get connectedCentrals => _connectedCentrals.values.toList();

  @override
  void addService(LocalService service) {
    final platformService = _mapLocalServiceToPlatform(service);
    _platform.addService(platformService);
  }

  @override
  void removeService(UUID uuid) {
    _platform.removeService(uuid.toString());
  }

  @override
  Future<void> startAdvertising({
    String? name,
    List<UUID>? services,
    ManufacturerData? manufacturerData,
    Duration? timeout,
  }) async {
    final config = platform.PlatformAdvertiseConfig(
      name: name,
      serviceUuids: services?.map((u) => u.toString()).toList() ?? [],
      manufacturerDataCompanyId: manufacturerData?.companyId,
      manufacturerData: manufacturerData?.data,
      timeoutMs: timeout?.inMilliseconds,
    );

    await _platform.startAdvertising(config);
    _isAdvertising = true;
  }

  @override
  Future<void> stopAdvertising() async {
    await _platform.stopAdvertising();
    _isAdvertising = false;
  }

  @override
  Future<void> notify(UUID characteristic, {required Uint8List data}) async {
    await _platform.notifyCharacteristic(characteristic.toString(), data);
  }

  @override
  Future<void> notifyTo(
    Central central,
    UUID characteristic, {
    required Uint8List data,
  }) async {
    final blueyCentral = central as BlueyCentral;
    await _platform.notifyCharacteristicTo(
      blueyCentral.platformId,
      characteristic.toString(),
      data,
    );
  }

  @override
  Future<void> dispose() async {
    if (_isAdvertising) {
      await stopAdvertising();
    }

    await _centralConnectionsSub?.cancel();
    await _centralDisconnectionsSub?.cancel();
    await _connectionsController.close();

    _connectedCentrals.clear();
  }

  // === Private mapping methods ===

  platform.PlatformLocalService _mapLocalServiceToPlatform(
      LocalService service) {
    return platform.PlatformLocalService(
      uuid: service.uuid.toString(),
      isPrimary: service.isPrimary,
      characteristics: service.characteristics
          .map(_mapLocalCharacteristicToPlatform)
          .toList(),
      includedServices:
          service.includedServices.map(_mapLocalServiceToPlatform).toList(),
    );
  }

  platform.PlatformLocalCharacteristic _mapLocalCharacteristicToPlatform(
      LocalCharacteristic characteristic) {
    return platform.PlatformLocalCharacteristic(
      uuid: characteristic.uuid.toString(),
      properties: platform.PlatformCharacteristicProperties(
        canRead: characteristic.properties.canRead,
        canWrite: characteristic.properties.canWrite,
        canWriteWithoutResponse:
            characteristic.properties.canWriteWithoutResponse,
        canNotify: characteristic.properties.canNotify,
        canIndicate: characteristic.properties.canIndicate,
      ),
      permissions:
          characteristic.permissions.map(_mapGattPermissionToPlatform).toList(),
      descriptors: characteristic.descriptors
          .map(_mapLocalDescriptorToPlatform)
          .toList(),
    );
  }

  platform.PlatformLocalDescriptor _mapLocalDescriptorToPlatform(
      LocalDescriptor descriptor) {
    return platform.PlatformLocalDescriptor(
      uuid: descriptor.uuid.toString(),
      permissions:
          descriptor.permissions.map(_mapGattPermissionToPlatform).toList(),
      value: descriptor.value,
    );
  }

  platform.PlatformGattPermission _mapGattPermissionToPlatform(
      GattPermission permission) {
    switch (permission) {
      case GattPermission.read:
        return platform.PlatformGattPermission.read;
      case GattPermission.readEncrypted:
        return platform.PlatformGattPermission.readEncrypted;
      case GattPermission.write:
        return platform.PlatformGattPermission.write;
      case GattPermission.writeEncrypted:
        return platform.PlatformGattPermission.writeEncrypted;
    }
  }
}

/// Concrete implementation of [Central].
class BlueyCentral implements Central {
  final platform.BlueyPlatform _platform;
  final String platformId;
  final int _mtu;

  BlueyCentral({
    required platform.BlueyPlatform platform,
    required String id,
    required int mtu,
  })  : _platform = platform,
        platformId = id,
        _mtu = mtu;

  @override
  UUID get id {
    // Convert the platform ID to a UUID
    // If it's already a UUID format, use it directly
    if (platformId.length == 36 && platformId.contains('-')) {
      return UUID(platformId);
    }
    // Otherwise, create a UUID from the string by padding
    final bytes = platformId.codeUnits;
    final padded = List<int>.filled(16, 0);
    for (var i = 0; i < bytes.length && i < 16; i++) {
      padded[i] = bytes[i];
    }
    // Convert to hex string
    final hex = padded.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return UUID(hex);
  }

  @override
  int get mtu => _mtu;

  @override
  Future<void> disconnect() async {
    await _platform.disconnectCentral(platformId);
  }
}
