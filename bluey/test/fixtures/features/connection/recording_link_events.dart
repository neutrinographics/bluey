import 'package:bluey/src/features/connection/application/ports/link_events.dart';
import 'package:bluey/src/features/connection/domain/link_event.dart';

/// A [LinkEvents] that keeps every event, so a test can assert what the
/// application raised, and in what order, without an edge to translate it.
class RecordingLinkEvents implements LinkEvents {
  /// Every event raised, in the order it was raised.
  final List<LinkEvent> raised = [];

  @override
  void raise(LinkEvent event) => raised.add(event);
}
