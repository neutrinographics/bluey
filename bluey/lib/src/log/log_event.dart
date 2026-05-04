import 'package:meta/meta.dart';

import 'log_level.dart';

/// A single structured log record emitted by the Bluey internal logger.
///
/// This is a value object: instances are immutable and equality is by value
/// across every field, including a deep comparison of the [data] map.
///
/// The [data] map carries optional structured key/value context (e.g. a
/// device address, attempt count, error status). It uses
/// `Map<String, Object?>` so callers can mix scalar types without forcing
/// stringification at the call site.
@immutable
class BlueyLogEvent {
  /// When the event was produced. Captured by the logger at log time.
  final DateTime timestamp;

  /// Severity of the event.
  final BlueyLogLevel level;

  /// Coarse subsystem tag (e.g. `'connection'`, `'gatt_client'`).
  ///
  /// Intended for filtering and grouping; not free-form prose.
  final String context;

  /// Human-readable message.
  final String message;

  /// Optional structured key/value context.
  ///
  /// Defaults to an empty const map. Callers should treat this as immutable.
  final Map<String, Object?> data;

  /// Optional stable error code (e.g. `'GATT_133'`).
  ///
  /// Distinct from [message] so that filters and metrics can key on a
  /// machine-stable identifier.
  final String? errorCode;

  const BlueyLogEvent({
    required this.timestamp,
    required this.level,
    required this.context,
    required this.message,
    this.data = const {},
    this.errorCode,
  });

  @override
  bool operator ==(Object other) =>
      other is BlueyLogEvent &&
      other.timestamp == timestamp &&
      other.level == level &&
      other.context == context &&
      other.message == message &&
      other.errorCode == errorCode &&
      _mapEquals(other.data, data);

  @override
  int get hashCode => Object.hash(
    timestamp,
    level,
    context,
    message,
    errorCode,
    _mapHash(data),
  );

  @override
  String toString() =>
      'BlueyLogEvent(${level.name} $context: $message'
      '${data.isEmpty ? '' : ' data=$data'}'
      '${errorCode == null ? '' : ' errorCode=$errorCode'}'
      ' @$timestamp)';

  static bool _mapEquals(Map<String, Object?> a, Map<String, Object?> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key)) return false;
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  static int _mapHash(Map<String, Object?> map) {
    // Order-independent hash: XOR of per-entry hashes.
    var h = 0;
    for (final entry in map.entries) {
      h ^= Object.hash(entry.key, entry.value);
    }
    return h;
  }
}
