import 'package:meta/meta.dart';

/// Severity for a structured log event emitted by a platform implementation.
///
/// Ordering is significant: callers filter events by passing the minimum
/// level to [BlueyPlatform.setLogLevel], and any event whose [PlatformLogEvent.level]
/// has a lower [Enum.index] than the configured minimum is dropped.
enum PlatformLogLevel { trace, debug, info, warn, error }

/// A single structured log record emitted by a platform implementation
/// (Android Kotlin, iOS Swift, etc.) and forwarded to Dart.
///
/// This is a value object: instances are immutable and equality is by
/// value across every field, including a deep, order-independent
/// comparison of the [data] map.
///
/// Mirrors [BlueyLogEvent] in the `bluey` package; the platform-interface
/// layer keeps its own type so that [BlueyPlatform] has no dependency on
/// the domain layer.
@immutable
class PlatformLogEvent {
  /// When the event was produced. Captured by the platform at log time.
  final DateTime timestamp;

  /// Severity of the event.
  final PlatformLogLevel level;

  /// Coarse subsystem tag (e.g. `'bluey.android.connection'`,
  /// `'bluey.ios.peripheral'`).
  final String context;

  /// Human-readable message.
  final String message;

  /// Optional structured key/value context.
  ///
  /// Defaults to an empty const map. Values are nullable to allow
  /// callers to mix scalar types without forcing stringification at the
  /// call site.
  final Map<String, Object?> data;

  /// Optional stable error code (e.g. `'GATT_133'`).
  ///
  /// Distinct from [message] so that filters and metrics can key on a
  /// machine-stable identifier.
  final String? errorCode;

  const PlatformLogEvent({
    required this.timestamp,
    required this.level,
    required this.context,
    required this.message,
    this.data = const {},
    this.errorCode,
  });

  @override
  bool operator ==(Object other) =>
      other is PlatformLogEvent &&
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
      'PlatformLogEvent(${level.name} $context: $message'
      '${data.isEmpty ? '' : ' data=$data'}'
      '${errorCode == null ? '' : ' errorCode=$errorCode'}'
      ' @$timestamp)';

  static bool _mapEquals(
    Map<String, Object?> a,
    Map<String, Object?> b,
  ) {
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
