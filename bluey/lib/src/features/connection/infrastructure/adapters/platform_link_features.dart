import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;

import '../../domain/link_features.dart';

/// What links can do, read from the platform's own account of itself.
LinkFeatures linkFeaturesFrom(platform.Capabilities source) => LinkFeatures(
  canBond: source.canBond,
  canRequestPhy: source.canRequestPhy,
  canRequestParameters: source.canRequestConnectionParameters,
  canRequestMtu: source.canRequestMtu,
  maxMtu: source.maxMtu,
);
