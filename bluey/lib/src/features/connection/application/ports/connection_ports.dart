import '../../domain/link_features.dart';
import 'links.dart';

/// Everything Connection asks of the radio, handed over as one, so a host
/// wires Connection in one line and a new port reaches every host through
/// this type.
final class ConnectionPorts {
  const ConnectionPorts({required this.links, required this.features});

  /// The radio's links.
  final Links links;

  /// What the radio's links can do on this platform.
  final LinkFeatures features;
}
