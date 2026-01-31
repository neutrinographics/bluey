import 'dart:async';

import 'events.dart';

/// Global event bus for Bluey diagnostic events.
///
/// This is a singleton that collects events from all Bluey components.
/// Use [Bluey.events] to access the event stream.
class BlueyEventBus {
  static final BlueyEventBus _instance = BlueyEventBus._();

  /// Gets the singleton instance.
  static BlueyEventBus get instance => _instance;

  final StreamController<BlueyEvent> _controller =
      StreamController<BlueyEvent>.broadcast();

  BlueyEventBus._();

  /// Stream of all Bluey events.
  Stream<BlueyEvent> get stream => _controller.stream;

  /// Emit an event to the bus.
  void emit(BlueyEvent event) {
    if (!_controller.isClosed) {
      _controller.add(event);
    }
  }

  /// Close the event bus (typically only called during app shutdown).
  Future<void> close() async {
    await _controller.close();
  }
}
