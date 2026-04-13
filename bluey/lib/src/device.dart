import 'dart:collection';
import 'dart:typed_data';
import 'package:meta/meta.dart';
import 'uuid.dart';

bool _listEquals<T>(List<T>? a, List<T>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Manufacturer-specific advertisement data.
///
/// Value object containing company ID and associated data.
@immutable
class ManufacturerData {
  final int companyId;
  final Uint8List data;

  const ManufacturerData(this.companyId, this.data);

  /// Well-known company IDs
  static const int apple = 0x004C;
  static const int google = 0x00E0;
  static const int microsoft = 0x0006;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ManufacturerData &&
        other.companyId == companyId &&
        _listEquals(other.data, data);
  }

  @override
  int get hashCode => Object.hash(companyId, Object.hashAll(data));

  @override
  String toString() =>
      'ManufacturerData(companyId: 0x${companyId.toRadixString(16).padLeft(4, '0')}, data: $data)';
}

/// BLE advertisement data.
///
/// Value object containing all data broadcast by a BLE peripheral.
/// Immutable - all collections are unmodifiable.
@immutable
class Advertisement {
  final List<UUID> serviceUuids;
  final Map<UUID, Uint8List> serviceData;
  final ManufacturerData? manufacturerData;
  final int? txPowerLevel;
  final bool isConnectable;

  Advertisement({
    required List<UUID> serviceUuids,
    required Map<UUID, Uint8List> serviceData,
    this.manufacturerData,
    this.txPowerLevel,
    required this.isConnectable,
  }) : serviceUuids = UnmodifiableListView(serviceUuids),
       serviceData = UnmodifiableMapView(serviceData);

  /// Creates an empty advertisement.
  factory Advertisement.empty() {
    return Advertisement(
      serviceUuids: [],
      serviceData: {},
      isConnectable: false,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Advertisement &&
        _listEquals(other.serviceUuids, serviceUuids) &&
        _mapsEqual(other.serviceData, serviceData) &&
        other.manufacturerData == manufacturerData &&
        other.txPowerLevel == txPowerLevel &&
        other.isConnectable == isConnectable;
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAll(serviceUuids),
    Object.hashAllUnordered(
      serviceData.entries.map(
        (e) => Object.hash(e.key, Object.hashAll(e.value)),
      ),
    ),
    manufacturerData,
    txPowerLevel,
    isConnectable,
  );

  @override
  String toString() {
    return 'Advertisement(serviceUuids: $serviceUuids, '
        'serviceData: ${serviceData.length} entries, '
        'manufacturerData: $manufacturerData, '
        'txPowerLevel: $txPowerLevel, '
        'isConnectable: $isConnectable)';
  }

  bool _mapsEqual(Map<UUID, Uint8List> a, Map<UUID, Uint8List> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key)) return false;
      if (!_listEquals(a[key], b[key])) return false;
    }
    return true;
  }
}

/// A BLE device with a stable identity.
///
/// This is an entity — two devices with the same [id] are considered equal,
/// even if other properties differ (e.g., name changed). This enables
/// deduplication in collections.
///
/// Immutable — use [copyWith] to create updated instances.
@immutable
class Device {
  /// Unique device identifier as a UUID.
  ///
  /// On iOS, this is the native CoreBluetooth UUID.
  /// On Android, this is derived from the MAC address.
  final UUID id;

  /// Hardware address used for platform connections.
  ///
  /// On Android, this is the MAC address (e.g., "AA:BB:CC:DD:EE:FF").
  /// On iOS, this is the same as [id] since iOS doesn't expose MAC addresses.
  final String address;

  /// Advertised device name, if available.
  final String? name;

  /// Signal strength in dBm (typically -30 to -100).
  final int rssi;

  /// Advertisement data broadcast by the device.
  final Advertisement advertisement;

  /// When this device was last seen.
  final DateTime lastSeen;

  Device({
    required this.id,
    String? address,
    this.name,
    required this.rssi,
    required this.advertisement,
    DateTime? lastSeen,
  }) : address = address ?? id.toString(),
       lastSeen = lastSeen ?? DateTime.now();

  /// Creates a copy with updated fields.
  ///
  /// To explicitly set [name] to null, pass null. To keep the existing value,
  /// don't pass the parameter.
  Device copyWith({
    Object? name = _sentinel,
    int? rssi,
    Advertisement? advertisement,
    DateTime? lastSeen,
  }) {
    return Device(
      id: id,
      address: address,
      name: name == _sentinel ? this.name : name as String?,
      rssi: rssi ?? this.rssi,
      advertisement: advertisement ?? this.advertisement,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }

  static const _sentinel = Object();

  @override
  bool operator ==(Object other) {
    // Entity equality: based on ID only
    return other is Device && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'Device(id: $id, name: $name, rssi: $rssi dBm, lastSeen: $lastSeen)';
  }
}
