import 'links.dart';

/// Everything Connection asks of the radio, handed over as one, so a host
/// wires Connection in one line and a new port reaches every host through
/// this type.
final class ConnectionPorts {
  const ConnectionPorts({required this.links});

  /// The radio's links.
  final Links links;
}
