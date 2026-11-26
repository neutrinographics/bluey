import '../domain/bluey_event.dart';

/// The port a unit publishes [BlueyEvent]s through. A unit that only emits
/// depends on this, not on the bus, so it can neither read the stream nor
/// close it, and a test can hand it a list-backed double.
abstract interface class EventPublisher {
  /// Publishes [event]. Safe to call after the transport has closed: the
  /// event is then dropped, never raised.
  void emit(BlueyEvent event);
}
