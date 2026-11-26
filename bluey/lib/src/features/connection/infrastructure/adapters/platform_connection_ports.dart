import 'package:bluey_platform_interface/bluey_platform_interface.dart';

import '../../../../shared/application/log.dart';
import '../../application/ports/connection_ports.dart';
import 'platform_link_features.dart';
import 'platform_links.dart';

/// Connection's ports over [platform], what a phone runs on.
ConnectionPorts platformConnectionPorts(
  BlueyPlatform platform, {
  required Log log,
}) => ConnectionPorts(
  links: PlatformLinks(platform, log: log),
  features: linkFeaturesFrom(platform.capabilities),
);
