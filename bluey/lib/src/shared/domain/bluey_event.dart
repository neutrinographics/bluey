import 'package:meta/meta.dart';

/// The base of every context's events, so each context can declare its own
/// events in its own domain and still reach an app through one stream.
///
/// It is not sealed: an exhaustive switch over events needs a default
/// branch, because a later slice may add events in another file.
@immutable
abstract class BlueyEvent {
  /// When this event occurred.
  final DateTime timestamp;

  /// Optional source component that generated this event.
  final String? source;

  BlueyEvent({DateTime? timestamp, this.source})
    : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() => '[$runtimeType] ${_formatTime(timestamp)}';

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}.'
        '${time.millisecond.toString().padLeft(3, '0')}';
  }
}
