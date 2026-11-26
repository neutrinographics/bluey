import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;

import '../../domain/capabilities.dart';

/// Bluey's [Capabilities] for the platform's own matrix, so the public API
/// names no type of the platform interface.
Capabilities capabilitiesFrom(platform.Capabilities source) => Capabilities(
  platformKind: _kindFrom(source.platformKind),
  canScan: source.canScan,
  canConnect: source.canConnect,
  canAdvertise: source.canAdvertise,
  canRequestMtu: source.canRequestMtu,
  maxMtu: source.maxMtu,
  canScanInBackground: source.canScanInBackground,
  canAdvertiseInBackground: source.canAdvertiseInBackground,
  canBond: source.canBond,
  canRequestPhy: source.canRequestPhy,
  canRequestConnectionParameters: source.canRequestConnectionParameters,
  canRequestEnable: source.canRequestEnable,
  canAdvertiseManufacturerData: source.canAdvertiseManufacturerData,
  reportsCentralDisconnects: source.reportsCentralDisconnects,
);

PlatformKind _kindFrom(platform.PlatformKind kind) => switch (kind) {
  platform.PlatformKind.android => PlatformKind.android,
  platform.PlatformKind.ios => PlatformKind.ios,
  platform.PlatformKind.fake => PlatformKind.fake,
  platform.PlatformKind.other => PlatformKind.other,
};
