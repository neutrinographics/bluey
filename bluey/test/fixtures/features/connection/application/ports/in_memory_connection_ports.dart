import 'package:bluey/src/features/connection/application/ports/connection_ports.dart';
import 'package:bluey/src/features/connection/domain/link_features.dart';

import 'in_memory_links.dart';

/// Links that can do everything the specification allows, so a test of the
/// edge meets no platform limit it did not ask for.
const unlimitedLinkFeatures = LinkFeatures(
  canBond: true,
  canRequestPhy: true,
  canRequestParameters: true,
  canRequestMtu: true,
  maxMtu: 517,
);

/// Every port as its in-memory double, for tests of the edge that need no
/// platform.
ConnectionPorts inMemoryConnectionPorts({
  InMemoryLinks? links,
  LinkFeatures features = unlimitedLinkFeatures,
}) => ConnectionPorts(links: links ?? InMemoryLinks(), features: features);
