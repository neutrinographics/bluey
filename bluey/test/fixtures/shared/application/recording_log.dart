import 'package:bluey/src/shared/application/log.dart';
import 'package:bluey/src/shared/application/log_event.dart';
import 'package:bluey/src/shared/application/log_level.dart';

/// A [Log] that keeps every line, unfiltered, so a test can assert what a
/// unit logged without a stream or a level threshold in the way.
class RecordingLog implements Log {
  /// Every line logged, in the order it was logged.
  final List<BlueyLogEvent> records = [];

  @override
  void log(
    BlueyLogLevel level,
    String context,
    String message, {
    Map<String, Object?> data = const {},
    String? errorCode,
  }) {
    records.add(
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
}
