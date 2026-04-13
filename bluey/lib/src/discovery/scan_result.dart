import 'package:meta/meta.dart';

import 'advertisement.dart';
import 'device.dart';

/// A single scan observation pairing a [Device] with transient data.
///
/// Value object - equality is based on all fields. This separates the
/// stable device identity ([Device]) from the per-observation data
/// (rssi, advertisement, lastSeen) that changes with each scan event.
@immutable
class ScanResult {
  /// The discovered device.
  final Device device;

  /// Signal strength in dBm (typically -30 to -100).
  final int rssi;

  /// Advertisement data broadcast by the device.
  final Advertisement advertisement;

  /// When this scan result was observed.
  final DateTime lastSeen;

  ScanResult({
    required this.device,
    required this.rssi,
    required this.advertisement,
    DateTime? lastSeen,
  }) : lastSeen = lastSeen ?? DateTime.now();

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ScanResult &&
        other.device == device &&
        other.rssi == rssi &&
        other.advertisement == advertisement &&
        other.lastSeen == lastSeen;
  }

  @override
  int get hashCode => Object.hash(device, rssi, advertisement, lastSeen);

  @override
  String toString() {
    return 'ScanResult(device: ${device.id}, rssi: $rssi dBm, '
        'advertisement: $advertisement)';
  }
}
