import 'log_event.dart';
import 'log_level.dart';

/// The port a unit writes its structured log lines through, so placed code
/// logs without naming the logger that filters, streams and bridges them.
abstract interface class Log {
  /// Writes one line. An implementation may drop it, below its threshold or
  /// once disposed, so a caller never relies on a line being kept.
  ///
  /// [context] is a coarse subsystem tag such as `bluey.connection`, and
  /// [errorCode] a machine-stable identifier for a failure, kept apart from
  /// [message] so filters can key on it. The line becomes a [BlueyLogEvent].
  void log(
    BlueyLogLevel level,
    String context,
    String message, {
    Map<String, Object?> data = const {},
    String? errorCode,
  });
}
