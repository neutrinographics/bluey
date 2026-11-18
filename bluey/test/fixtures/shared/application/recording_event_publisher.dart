import 'package:bluey/src/shared/application/event_publisher.dart';
import 'package:bluey/src/shared/domain/bluey_event.dart';

/// An [EventPublisher] that keeps every event, so a test can assert what a
/// unit published without listening to a stream.
class RecordingEventPublisher implements EventPublisher {
  /// Every event published, in the order it was published.
  final List<BlueyEvent> events = [];

  @override
  void emit(BlueyEvent event) => events.add(event);
}
