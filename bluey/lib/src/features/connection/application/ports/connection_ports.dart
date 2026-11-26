import '../../domain/link_features.dart';
import 'bonding.dart';
import 'links.dart';
import 'mtu_negotiation.dart';
import 'signal_strength.dart';

/// Everything Connection is handed about the radio, its ports and the fixed
/// facts of the platform, as one, so a host wires Connection in one line and
/// a new port reaches every host through this type.
final class ConnectionPorts {
  const ConnectionPorts({
    required this.links,
    required this.features,
    required this.mtu,
    required this.signal,
    required this.bonding,
  });

  /// The radio's links.
  final Links links;

  /// What the radio's links can do on this platform.
  final LinkFeatures features;

  /// How a link's MTU is agreed with its peer.
  final MtuNegotiation mtu;

  /// How well a link's peer is heard.
  final SignalStrength signal;

  /// How a link's device is bonded, and its bond followed.
  final Bonding bonding;
}
