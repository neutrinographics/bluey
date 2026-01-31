import 'dart:async';

import 'events.dart';

/// Event bus for Bluey diagnostic events.
///
/// Each [Bluey] instance has its own event bus. Use [Bluey.events] to access
/// the event stream.
class BlueyEventBus {
  final StreamController<BlueyEvent> _controller =
      StreamController<BlueyEvent>.broadcast();

  /// Stream of all Bluey events.
  Stream<BlueyEvent> get stream => _controller.stream;

  /// Emit an event to the bus.
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
