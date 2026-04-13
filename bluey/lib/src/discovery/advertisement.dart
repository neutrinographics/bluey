import 'dart:collection';
import 'dart:typed_data';
import 'package:meta/meta.dart';

import '../shared/manufacturer_data.dart';
import '../shared/uuid.dart';

bool _listEquals<T>(List<T>? a, List<T>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
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
