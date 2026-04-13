import 'package:meta/meta.dart';

/// Platform capability matrix.
///
/// Describes what BLE features are available on the current platform.
/// Immutable value object.
@immutable
class Capabilities {
  /// Whether scanning is supported.
  final bool canScan;

  /// Whether connecting to devices is supported.
  final bool canConnect;

  /// Whether peripheral (server) role is supported.
  final bool canAdvertise;

  /// Whether MTU negotiation is supported.
  final bool canRequestMtu;

  /// Maximum supported MTU.
  final int maxMtu;

  /// Whether background scanning is supported.
  final bool canScanInBackground;

  /// Whether background peripheral role is supported.
  final bool canAdvertiseInBackground;

  /// Whether pairing/bonding is supported.
  final bool canBond;

  /// Whether Bluetooth can be enabled programmatically.
  final bool canRequestEnable;

  const Capabilities({
    this.canScan = true,
    this.canConnect = true,
    this.canAdvertise = false,
    this.canRequestMtu = false,
    this.maxMtu = 23,
    this.canScanInBackground = false,
    this.canAdvertiseInBackground = false,
    this.canBond = false,
    this.canRequestEnable = false,
  });

  /// Android capabilities.
  static const android = Capabilities(
    canAdvertise: true,
    canRequestMtu: true,
    maxMtu: 517,
    canBond: true,
    canRequestEnable: true,
  );

  /// iOS capabilities.
  static const iOS = Capabilities(
    canAdvertise: true,
    maxMtu: 185,
    canScanInBackground: true,
    canAdvertiseInBackground: true,
  );

  /// macOS capabilities.
  static const macOS = Capabilities(
    canAdvertise: true,
    maxMtu: 185,
  );

  /// Windows capabilities.
  static const windows = Capabilities(
    canRequestMtu: true,
    maxMtu: 517,
  );

  /// Linux capabilities.
  static const linux = Capabilities(
    canAdvertise: true,
    canRequestMtu: true,
    maxMtu: 517,
  );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Capabilities &&
        other.canScan == canScan &&
        other.canConnect == canConnect &&
        other.canAdvertise == canAdvertise &&
        other.canRequestMtu == canRequestMtu &&
        other.maxMtu == maxMtu &&
        other.canScanInBackground == canScanInBackground &&
        other.canAdvertiseInBackground == canAdvertiseInBackground &&
        other.canBond == canBond &&
        other.canRequestEnable == canRequestEnable;
  }

  @override
  int get hashCode => Object.hash(
        canScan,
        canConnect,
        canAdvertise,
        canRequestMtu,
        maxMtu,
        canScanInBackground,
        canAdvertiseInBackground,
        canBond,
        canRequestEnable,
      );

  @override
  String toString() {
    return 'Capabilities('
        'canScan: $canScan, '
        'canConnect: $canConnect, '
        'canAdvertise: $canAdvertise, '
        'canRequestMtu: $canRequestMtu, '
        'maxMtu: $maxMtu, '
        'canScanInBackground: $canScanInBackground, '
        'canAdvertiseInBackground: $canAdvertiseInBackground, '
        'canBond: $canBond, '
        'canRequestEnable: $canRequestEnable)';
  }
}
