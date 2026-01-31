import 'dart:async';
import 'dart:typed_data';

import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;

import 'device.dart';
import 'event_bus.dart';
import 'events.dart';
import 'server.dart';
import 'uuid.dart';

/// Concrete implementation of [Server] that delegates to the platform.
class BlueyServer implements Server {
  final platform.BlueyPlatform _platform;
  final BlueyEventBus _eventBus;

  bool _isAdvertising = false;
  final Map<String, BlueyCentral> _connectedCentrals = {};

  final StreamController<Central> _connectionsController =
      StreamController<Central>.broadcast();

  StreamSubscription? _centralConnectionsSub;
  StreamSubscription? _centralDisconnectionsSub;

  BlueyServer(this._platform, this._eventBus) {
    _emitEvent(const ServerStartedEvent(source: 'BlueyServer'));

    _centralConnectionsSub = _platform.centralConnections.listen((
      platformCentral,
    ) {
      _emitEvent(
        CentralConnectedEvent(
          centralId: platformCentral.id,
          mtu: platformCentral.mtu,
          source: 'BlueyServer',
        ),
      );
      final central = BlueyCentral(
        platform: _platform,
        id: platformCentral.id,
        mtu: platformCentral.mtu,
      );
      _connectedCentrals[platformCentral.id] = central;
      _connectionsController.add(central);
    });

    _centralDisconnectionsSub = _platform.centralDisconnections.listen((
      centralId,
    ) {
      _emitEvent(
        CentralDisconnectedEvent(centralId: centralId, source: 'BlueyServer'),
      );
      _connectedCentrals.remove(centralId);
    });
  }

  @override
  bool get isAdvertising => _isAdvertising;

  @override
  Stream<Central> get connections => _connectionsController.stream;

  @override
  List<Central> get connectedCentrals => _connectedCentrals.values.toList();

  @override
  Future<void> addService(HostedService service) async {
    final platformService = _mapHostedServiceToPlatform(service);
    await _platform.addService(platformService);
    _emitEvent(
      ServiceAddedEvent(serviceId: service.uuid, source: 'BlueyServer'),
    );
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
    _emitEvent(
      AdvertisingStartedEvent(
        name: name,
        services: services,
        source: 'BlueyServer',
      ),
    );
  }

  @override
  Future<void> stopAdvertising() async {
    await _platform.stopAdvertising();
    _isAdvertising = false;
    _emitEvent(const AdvertisingStoppedEvent(source: 'BlueyServer'));
  }

  @override
  Future<void> notify(UUID characteristic, {required Uint8List data}) async {
    await _platform.notifyCharacteristic(characteristic.toString(), data);
    _emitEvent(
      NotificationSentEvent(
        characteristicId: characteristic,
        valueLength: data.length,
        source: 'BlueyServer',
      ),
    );
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
    _emitEvent(
      NotificationSentEvent(
        characteristicId: characteristic,
        valueLength: data.length,
        centralId: blueyCentral.platformId,
        source: 'BlueyServer',
      ),
    );
  }

  @override
  Future<void> dispose() async {
    if (_isAdvertising) {
      await stopAdvertising();
    }

    // Close the GATT server and disconnect all centrals
    // This is important on Android to prevent zombie BLE connections
    await _platform.closeServer();

    await _centralConnectionsSub?.cancel();
    await _centralDisconnectionsSub?.cancel();
    await _connectionsController.close();

    _connectedCentrals.clear();
  }

  // === Private mapping methods ===

  platform.PlatformLocalService _mapHostedServiceToPlatform(
    HostedService service,
  ) {
    return platform.PlatformLocalService(
      uuid: service.uuid.toString(),
      isPrimary: service.isPrimary,
      characteristics:
          service.characteristics
              .map(_mapHostedCharacteristicToPlatform)
              .toList(),
      includedServices:
          service.includedServices.map(_mapHostedServiceToPlatform).toList(),
    );
  }

  platform.PlatformLocalCharacteristic _mapHostedCharacteristicToPlatform(
    HostedCharacteristic characteristic,
  ) {
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
      descriptors:
          characteristic.descriptors
              .map(_mapHostedDescriptorToPlatform)
              .toList(),
    );
  }

  platform.PlatformLocalDescriptor _mapHostedDescriptorToPlatform(
    HostedDescriptor descriptor,
  ) {
    return platform.PlatformLocalDescriptor(
      uuid: descriptor.uuid.toString(),
      permissions:
          descriptor.permissions.map(_mapGattPermissionToPlatform).toList(),
      value: descriptor.value,
    );
  }

  platform.PlatformGattPermission _mapGattPermissionToPlatform(
    GattPermission permission,
  ) {
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

  void _emitEvent(BlueyEvent event) {
    _eventBus.emit(event);
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
  }) : _platform = platform,
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
