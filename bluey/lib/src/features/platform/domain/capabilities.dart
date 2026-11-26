import 'package:meta/meta.dart';

/// Which platform a [Capabilities] describes, so code can offer a
/// platform's own extensions without guessing from its flags.
enum PlatformKind { android, ios, fake, other }

/// What the platform Bluey runs on can do, so an app can check before it
/// asks for something the platform would refuse.
///
/// Equal by value: two matrices with the same flags are the same matrix.
@immutable
class Capabilities {
  /// The platform this matrix describes.
  final PlatformKind platformKind;

  /// Whether scanning is supported.
  final bool canScan;

  /// Whether connecting to devices is supported.
  final bool canConnect;

  /// Whether this device can host a server and advertise it.
  final bool canAdvertise;

  /// Whether the app may ask for a larger MTU.
  final bool canRequestMtu;

  /// The largest MTU the platform supports.
  final int maxMtu;

  /// Whether scanning goes on while the app is in the background.
  final bool canScanInBackground;

  /// Whether advertising goes on while the app is in the background.
  final bool canAdvertiseInBackground;

  /// Whether pairing and bonding are supported.
  final bool canBond;

  /// Whether the link-layer PHY can be read and requested.
  final bool canRequestPhy;

  /// Whether the connection parameters (interval, latency, supervision
  /// timeout) can be read and requested.
  final bool canRequestConnectionParameters;

  /// Whether the app can turn Bluetooth on itself.
  final bool canRequestEnable;

  /// Whether an advertisement may carry manufacturer data; iOS refuses it
  /// when advertising as a peripheral.
  final bool canAdvertiseManufacturerData;

  /// Whether the platform tells the server when a client leaves, so silence
  /// from a client is advisory rather than taken as its leaving.
  final bool reportsCentralDisconnects;

  const Capabilities({
    required this.platformKind,
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
    this.canAdvertiseManufacturerData = false,
    this.reportsCentralDisconnects = false,
  });

  /// Android's matrix. Bonding, the PHY and the connection parameters read
  /// false until the Android implementation supports them.
  static const android = Capabilities(
    platformKind: PlatformKind.android,
    canAdvertise: true,
    canRequestMtu: true,
    maxMtu: 517,
    canBond: false,
    canRequestPhy: false,
    canRequestConnectionParameters: false,
    canRequestEnable: true,
    canAdvertiseManufacturerData: true,
    reportsCentralDisconnects: true,
  );

  /// iOS's matrix. CoreBluetooth exposes no bond state, PHY or connection
  /// parameters, and refuses manufacturer data in an advertisement.
  static const iOS = Capabilities(
    platformKind: PlatformKind.ios,
    canAdvertise: true,
    maxMtu: 185,
    canScanInBackground: true,
    canAdvertiseInBackground: true,
    canBond: false,
    canRequestPhy: false,
    canRequestConnectionParameters: false,
    canAdvertiseManufacturerData: false,
    reportsCentralDisconnects: true,
  );

  /// A matrix that allows everything, so a test need not think about
  /// gating unless it overrides a flag.
  static const fake = Capabilities(
    platformKind: PlatformKind.fake,
    canScan: true,
    canConnect: true,
    canAdvertise: true,
    canRequestMtu: true,
    maxMtu: 517,
    canScanInBackground: true,
    canAdvertiseInBackground: true,
    canBond: true,
    canRequestPhy: true,
    canRequestConnectionParameters: true,
    canRequestEnable: true,
    canAdvertiseManufacturerData: true,
    reportsCentralDisconnects: true,
  );

  /// macOS's matrix.
  static const macOS = Capabilities(
    platformKind: PlatformKind.other,
    canAdvertise: true,
    maxMtu: 185,
    reportsCentralDisconnects: true,
  );

  /// Windows's matrix.
  static const windows = Capabilities(
    platformKind: PlatformKind.other,
    canRequestMtu: true,
    maxMtu: 517,
    reportsCentralDisconnects: true,
  );

  /// Linux's matrix.
  static const linux = Capabilities(
    platformKind: PlatformKind.other,
    canAdvertise: true,
    canRequestMtu: true,
    maxMtu: 517,
    canRequestEnable: true,
    reportsCentralDisconnects: true,
  );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Capabilities &&
        other.platformKind == platformKind &&
        other.canScan == canScan &&
        other.canConnect == canConnect &&
        other.canAdvertise == canAdvertise &&
        other.canRequestMtu == canRequestMtu &&
        other.maxMtu == maxMtu &&
        other.canScanInBackground == canScanInBackground &&
        other.canAdvertiseInBackground == canAdvertiseInBackground &&
        other.canBond == canBond &&
        other.canRequestPhy == canRequestPhy &&
        other.canRequestConnectionParameters ==
            canRequestConnectionParameters &&
        other.canRequestEnable == canRequestEnable &&
        other.canAdvertiseManufacturerData == canAdvertiseManufacturerData &&
        other.reportsCentralDisconnects == reportsCentralDisconnects;
  }

  @override
  int get hashCode => Object.hash(
    platformKind,
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
    canAdvertiseManufacturerData,
    reportsCentralDisconnects,
  );

  @override
  String toString() {
    return 'Capabilities('
        'platformKind: $platformKind, '
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
        'canRequestEnable: $canRequestEnable, '
        'canAdvertiseManufacturerData: $canAdvertiseManufacturerData, '
        'reportsCentralDisconnects: $reportsCentralDisconnects)';
  }
}
