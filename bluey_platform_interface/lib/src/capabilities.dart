import 'package:meta/meta.dart';

/// Discriminator identifying the platform an implementation targets.
///
/// Used by domain-layer code (e.g. `BlueyConnection.android` /
/// `BlueyConnection.ios` getters) to decide which platform-tagged
/// extensions to expose. Replaces the prior heuristic that inferred iOS
/// from the absence of Android-only capability flags.
enum PlatformKind { android, ios, fake, other }

/// Platform capability matrix.
///
/// Describes what BLE features are available on the current platform.
/// Immutable value object.
@immutable
class Capabilities {
  /// Discriminator identifying which platform implementation produced
  /// this matrix. Used by domain-layer code to gate platform-specific
  /// extension surfaces.
  final PlatformKind platformKind;

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
  final bool canRequestPhy;

  /// Whether reading and requesting BLE connection parameters
  /// (interval, latency, supervision timeout) is supported.
  final bool canRequestConnectionParameters;

  /// Whether Bluetooth can be enabled programmatically.
  final bool canRequestEnable;

  /// Whether the platform's advertising surface accepts manufacturer data.
  ///
  /// iOS rejects manufacturer data when advertising as a peripheral
  /// (CBPeripheralManager only accepts a name and service UUID list);
  /// Android accepts it. The `Server.startAdvertising` call gates on
  /// this flag when `manufacturerData != null`.
  final bool canAdvertiseManufacturerData;

  /// Whether the platform delivers an authoritative client-disconnect signal
  /// for this device's GATT server — making heartbeat silence advisory rather
  /// than a disconnect inference.
  /// `true` on Android (`onConnectionStateChange`). `true` on iOS via Pattern B
  /// (I338): `CBPeripheralManager` has no native client-disconnect callback
  /// (I201), so a central unsubscribing from the dedicated lifecycle presence
  /// characteristic stands in as the signal (`didUnsubscribeFrom`).
  /// Flipping this to `false` re-enables the dormant silence-eviction handshake
  /// as a fallback if the presence signal proves unreliable on hardware. Note
  /// the reserved-status eviction is Android-only: iOS `CBPeripheralManager`
  /// cannot put an application-range ATT status (0x80) on the wire, so on iOS
  /// the fallback degrades to Stage-1 silence-disconnect, not the full
  /// handshake. The eviction machinery is slated for removal (backlog I340).
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

  /// Android capabilities.
  ///
  /// `canBond`, `canRequestPhy`, and `canRequestConnectionParameters` are
  /// currently `false` because the Dart-side bond/PHY/connection-parameter
  /// methods on `AndroidConnectionManager` are unimplemented (I035 Stage A
  /// throws `UnimplementedError`; Stage B will add the Pigeon plumbing).
  /// Flip them back on as each operation lands native + Pigeon support.
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

  /// iOS capabilities.
  ///
  /// `canBond`, `canRequestPhy`, `canRequestConnectionParameters`, and
  /// `canAdvertiseManufacturerData` are `false`: iOS does not expose bond
  /// state, PHY information, or connection parameters via CoreBluetooth
  /// (see I200 wontfix), and `CBPeripheralManager` rejects manufacturer
  /// data in advertisement payloads (see I204 wontfix).
  ///
  /// `reportsCentralDisconnects` is `true` (I338, Pattern B). Although
  /// `CBPeripheralManager` has no native client-disconnect callback (I201),
  /// iOS now derives an authoritative central-disconnect signal from the
  /// presence-characteristic unsubscribe event: when a central stops
  /// subscribing to the lifecycle presence characteristic, the native layer
  /// emits `onCentralDisconnected`, which feeds the existing
  /// `centralDisconnections` authoritative disconnect path. iOS therefore
  /// takes the AUTHORITATIVE branch in `BlueyServer._handleLifecycleSilence`,
  /// making heartbeat silence advisory (no eviction) — it is NOT inferred
  /// from heartbeat-silence and NOT a generic native callback.
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

  /// Permissive default for fakes / tests.
  ///
  /// Sets every capability flag we currently model to `true` so the
  /// majority of tests don't need to think about gating. Tests that
  /// exercise capability-gated branches override individual flags.
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

  /// macOS capabilities.
  static const macOS = Capabilities(
    platformKind: PlatformKind.other,
    canAdvertise: true,
    maxMtu: 185,
    reportsCentralDisconnects: true,
  );

  /// Windows capabilities.
  static const windows = Capabilities(
    platformKind: PlatformKind.other,
    canRequestMtu: true,
    maxMtu: 517,
    reportsCentralDisconnects: true,
  );

  /// Linux capabilities.
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
