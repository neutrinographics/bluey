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

  /// Whether reading and requesting the link-layer PHY is supported.
  ///
  /// When false, [BlueyPlatform.getPhy], [BlueyPlatform.phyStream], and
  /// [BlueyPlatform.requestPhy] are not implemented and the domain layer
  /// will not subscribe to or fetch PHY state on a connection.
  final bool canRequestPhy;

  /// Whether reading and requesting BLE connection parameters
  /// (interval, latency, supervision timeout) is supported.
  ///
  /// When false, [BlueyPlatform.getConnectionParameters] and
  /// [BlueyPlatform.requestConnectionParameters] are not implemented and
  /// the domain layer will not fetch connection parameters on a connection.
  final bool canRequestConnectionParameters;

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
    this.canRequestPhy = false,
    this.canRequestConnectionParameters = false,
    this.canRequestEnable = false,
  });

  /// Android capabilities.
  ///
  /// `canBond`, `canRequestPhy`, and `canRequestConnectionParameters` are
  /// currently `false` because the Dart-side bond/PHY/connection-parameter
  /// methods on `AndroidConnectionManager` are unimplemented (I035 Stage A
  /// throws `UnimplementedError`; Stage B will add the Pigeon plumbing).
  /// Flip them back on as each operation lands native + Pigeon support.
  static const android = Capabilities(
    canAdvertise: true,
    canRequestMtu: true,
    maxMtu: 517,
    canBond: false,
    canRequestPhy: false,
    canRequestConnectionParameters: false,
    canRequestEnable: true,
  );

  /// iOS capabilities.
  ///
  /// `canBond`, `canRequestPhy`, and `canRequestConnectionParameters` are
  /// `false`: iOS does not expose bond state, PHY information, or
  /// connection parameters via CoreBluetooth (see I200 wontfix).
  static const iOS = Capabilities(
    canAdvertise: true,
    maxMtu: 185,
    canScanInBackground: true,
    canAdvertiseInBackground: true,
    canBond: false,
    canRequestPhy: false,
    canRequestConnectionParameters: false,
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
        other.canRequestPhy == canRequestPhy &&
        other.canRequestConnectionParameters == canRequestConnectionParameters &&
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
        canRequestPhy,
        canRequestConnectionParameters,
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
        'canRequestPhy: $canRequestPhy, '
        'canRequestConnectionParameters: $canRequestConnectionParameters, '
        'canRequestEnable: $canRequestEnable)';
  }
}
