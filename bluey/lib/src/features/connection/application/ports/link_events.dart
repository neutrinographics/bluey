import '../../domain/link_event.dart';

/// Where Connection tells of what happened to its links, so the application
/// names no audience and each edge words the events for its own readers.
abstract interface class LinkEvents {
  /// Tells of [event]; events of one link are raised in the order they
  /// happened.
  void raise(LinkEvent event);
}
