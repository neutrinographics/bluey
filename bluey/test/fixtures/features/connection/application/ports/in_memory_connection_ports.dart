import 'package:bluey/src/features/connection/application/ports/connection_ports.dart';
import 'package:bluey/src/features/connection/domain/link_features.dart';

import 'in_memory_links.dart';
import 'in_memory_mtu_negotiation.dart';
import 'in_memory_signal_strength.dart';

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
  InMemoryMtuNegotiation? mtu,
  InMemorySignalStrength? signal,
}) => ConnectionPorts(
  links: links ?? InMemoryLinks(),
  features: features,
  mtu: mtu ?? InMemoryMtuNegotiation(),
  signal: signal ?? InMemorySignalStrength(),
);
