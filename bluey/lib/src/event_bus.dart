import 'dart:async';

import 'events.dart';

/// Domain-side port for emitting [BlueyEvent]s. Aggregates that need to
/// publish events depend on this interface — not on [BlueyEventBus] —
/// per the Interface Segregation Principle: the aggregate only needs
/// `emit`, not `stream` (a consumer concern) or `close` (an
/// orchestrator concern).
///
/// Production wiring uses [BlueyEventBus] as the implementation. Tests
/// can supply a trivial in-memory `List<BlueyEvent>`-backed
/// implementation to assert emissions without needing a real
/// `StreamController`.
abstract class EventPublisher {
  /// Emit an event. Must be safe to call after the underlying transport
  /// has been closed (the typical implementation no-ops in that case).
  void emit(BlueyEvent event);
}

/// Event bus for Bluey diagnostic events.
///
/// Each [Bluey] instance has its own event bus. Use [Bluey.events] to access
/// the event stream. Implements [EventPublisher] for the emission side.
class BlueyEventBus implements EventPublisher {
  final StreamController<BlueyEvent> _controller =
      StreamController<BlueyEvent>.broadcast();

  /// Stream of all Bluey events.
  Stream<BlueyEvent> get stream => _controller.stream;

  /// Emit an event to the bus.
  @override
  void emit(BlueyEvent event) {
    if (!_controller.isClosed) {
      _controller.add(event);
    }
  }

  /// Close the event bus.
  Future<void> close() async {
    await _controller.close();
  }
}
