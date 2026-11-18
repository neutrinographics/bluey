import 'dart:async';

import 'package:bluey_platform_interface/bluey_platform_interface.dart';

import '../application/log.dart';
import '../application/log_event.dart';
import '../application/log_level.dart';

/// Internal, in-memory structured logger used across the Bluey domain.
///
/// Holds a broadcast stream of [BlueyLogEvent]s and a mutable minimum
/// severity threshold. Calls below the threshold are dropped without
/// allocating a [BlueyLogEvent].
///
/// This class is the *internal* sink — public exposure (e.g. via the
/// `Bluey` facade) is layered on top and out of scope for this type.
class BlueyLogger implements Log {
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
  @override
  void log(
    BlueyLogLevel level,
    String context,
    String message, {
    Map<String, Object?> data = const {},
    String? errorCode,
  }) {
    if (_disposed) return;
    if (level.index < _minLevel.index) return;
    _controller.add(
      BlueyLogEvent(
        timestamp: DateTime.now(),
        level: level,
        context: context,
        message: message,
        data: data,
        errorCode: errorCode,
      ),
    );
  }

  /// Forwards a structured log event originating in the platform (native)
  /// implementation onto the unified [events] stream.
  ///
  /// Bypasses the level filter: native sides apply their own filter
  /// before marshalling, so any event arriving here has already been
  /// authorised by the configured threshold.
  ///
  /// No-op once [dispose] has been called.
  void injectFromPlatform(PlatformLogEvent event) {
    if (_disposed) return;
    _controller.add(
      BlueyLogEvent(
        timestamp: event.timestamp,
        level: _mapPlatformLevel(event.level),
        context: event.context,
        message: event.message,
        data: event.data,
        errorCode: event.errorCode,
      ),
    );
  }

  /// Closes the underlying broadcast stream. Subsequent [log] calls are
  /// no-ops and do not throw.
  Future<void> dispose() async {
    _disposed = true;
    await _controller.close();
  }

  /// The platform's name for [level], which the native side filters by, so
  /// a level set on Bluey costs no Pigeon traffic for the lines it drops.
  static PlatformLogLevel platformLevelOf(BlueyLogLevel level) {
    switch (level) {
      case BlueyLogLevel.trace:
        return PlatformLogLevel.trace;
      case BlueyLogLevel.debug:
        return PlatformLogLevel.debug;
      case BlueyLogLevel.info:
        return PlatformLogLevel.info;
      case BlueyLogLevel.warn:
        return PlatformLogLevel.warn;
      case BlueyLogLevel.error:
        return PlatformLogLevel.error;
    }
  }

  static BlueyLogLevel _mapPlatformLevel(PlatformLogLevel level) {
    switch (level) {
      case PlatformLogLevel.trace:
        return BlueyLogLevel.trace;
      case PlatformLogLevel.debug:
        return BlueyLogLevel.debug;
      case PlatformLogLevel.info:
        return BlueyLogLevel.info;
      case PlatformLogLevel.warn:
        return BlueyLogLevel.warn;
      case PlatformLogLevel.error:
        return BlueyLogLevel.error;
    }
  }
}
