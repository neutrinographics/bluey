import '../../features/connection/application/ports/link_events.dart';
import '../../features/connection/domain/link_end.dart';
import '../../features/connection/domain/link_event.dart';
import '../../shared/application/event_publisher.dart';
import '../../shared/domain/bluey_event.dart';
import 'connection_events.dart';

/// Publishes what happened to the links as the events an app reads on
/// `bluey.events`, so the lifecycle can grow words of its own while every
/// app keeps the events and reasons it always had.
final class PublishedLinkEvents implements LinkEvents {
  PublishedLinkEvents(this._publisher);

  final EventPublisher _publisher;

  @override
  void raise(LinkEvent event) => _publisher.emit(_publicOf(event));

  static BlueyEvent _publicOf(LinkEvent event) => switch (event) {
    LinkOpenBegan(:final device, :final at) => ConnectingEvent(
      deviceAddress: device,
      timestamp: at,
    ),
    LinkOpened(:final device, :final at) => ConnectedEvent(
      deviceAddress: device,
      timestamp: at,
    ),
    LinkEnded(:final device, :final at, :final end) => DisconnectedEvent(
      deviceAddress: device,
      reason: _reasonOf(end),
      timestamp: at,
    ),
  };

  static String _reasonOf(LinkEnd end) => switch (end) {
    EndedOnRequest() => 'requested',
    EndedByDrop() => 'linkLoss',
    EndedByRadioOutage() => 'radioOutage',
  };
}
