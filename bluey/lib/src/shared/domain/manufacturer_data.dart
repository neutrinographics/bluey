import 'dart:typed_data';
import 'package:meta/meta.dart';

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
