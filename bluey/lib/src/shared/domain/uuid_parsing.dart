import 'either.dart';
import 'failure.dart';
import 'uuid.dart';
import 'uuid_text.dart';

/// Text that names no UUID, kept whole so the log line can show what the
/// platform sent.
final class MalformedUuid implements Failure {
  const MalformedUuid(this.raw);

  /// The text that could not be read.
  final String raw;

  @override
  String get message => 'Not a UUID: "$raw"';

  @override
  bool operator ==(Object other) => other is MalformedUuid && other.raw == raw;

  @override
  int get hashCode => Object.hash(MalformedUuid, raw);
}

/// Reads a platform's UUID text without raising, because a device can send
/// anything and a scan must survive a malformed one.
///
/// Accepts the 4-hex-digit Bluetooth short form as well as full UUIDs.
Either<MalformedUuid, UUID> uuidFrom(String raw) {
  if (_isShortForm(raw)) {
    return Right(UUID.short(int.parse(raw, radix: 16)));
  }
  if (uuidTextViolation(raw) != null) return Left(MalformedUuid(raw));
  return Right(UUID(raw));
}

bool _isShortForm(String raw) => RegExp(r'^[0-9a-fA-F]{4}$').hasMatch(raw);
