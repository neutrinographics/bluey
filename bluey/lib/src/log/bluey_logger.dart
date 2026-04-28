import 'dart:async';

import 'log_event.dart';
import 'log_level.dart';

/// Internal, in-memory structured logger used across the Bluey domain.
///
/// Holds a broadcast stream of [BlueyLogEvent]s and a mutable minimum
/// severity threshold. Calls below the threshold are dropped without
/// allocating a [BlueyLogEvent].
///
/// This class is the *internal* sink — public exposure (e.g. via the
/// `Bluey` facade) is layered on top and out of scope for this type.
class BlueyLogger {
  /// Creates a logger with the given minimum severity threshold.
  BlueyLogger({BlueyLogLevel level = BlueyLogLevel.info}) : _minLevel = level;

  final StreamController<BlueyLogEvent> _controller =
      StreamController<BlueyLogEvent>.broadcast();
  BlueyLogLevel _minLevel;
  bool _disposed = false;

  /// Broadcast stream of structured events at or above the current
  /// [level]. Multiple subscribers each receive every event independently.
  Stream<BlueyLogEvent> get events => _controller.stream;

  /// Current minimum severity threshold. Events strictly below this level
  /// are dropped.
  BlueyLogLevel get level => _minLevel;

  /// Updates the minimum severity threshold. Takes effect for subsequent
  /// [log] calls.
  void setLevel(BlueyLogLevel level) {
    _minLevel = level;
  }

  /// Emits a [BlueyLogEvent] if [level] is at or above the current
  /// threshold and the logger has not been disposed.
  ///
  /// The event's `timestamp` is captured here using `DateTime.now()`.
  void log(
    BlueyLogLevel level,
    String context,
    String message, {
    Map<String, Object?> data = const {},
    String? errorCode,
  }) {
    if (_disposed) return;
    if (level.index < _minLevel.index) return;
    _controller.add(BlueyLogEvent(
      timestamp: DateTime.now(),
      level: level,
      context: context,
      message: message,
      data: data,
      errorCode: errorCode,
    ));
  }

  /// Closes the underlying broadcast stream. Subsequent [log] calls are
  /// no-ops and do not throw.
  Future<void> dispose() async {
    _disposed = true;
    await _controller.close();
  }
}
