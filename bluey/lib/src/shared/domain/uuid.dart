import 'uuid_text.dart';

/// A 128-bit Bluetooth UUID with support for short-form notation.
///
/// This is a value object in the Domain layer. UUIDs are immutable and
/// equality is based on value, not identity.
///
/// Bluetooth UUIDs can be either:
/// - Full 128-bit: '0000180d-0000-1000-8000-00805f9b34fb'
/// - Short 16-bit (Bluetooth SIG assigned): created via `UUID.short(0x180D)`
///
/// Short UUIDs are expanded using the Bluetooth base UUID:
/// 0000xxxx-0000-1000-8000-00805f9b34fb
///
/// Note: The string constructor only accepts full 128-bit UUIDs (with or
/// without hyphens). Use `UUID.short()` for 16-bit short UUIDs.
class UUID {
  /// Bluetooth SIG base UUID
  static const String _baseUuid = '0000-1000-8000-00805f9b34fb';

  final String _value;

  /// Creates a UUID from a full 128-bit UUID string.
  ///
  /// Accepts formats:
  /// - With hyphens: '0000180d-0000-1000-8000-00805f9b34fb'
  /// - Without hyphens: '0000180d00001000800000805f9b34fb'
  ///
  /// Case insensitive.
  UUID(String value) : _value = _normalize(value);

  /// Creates a UUID from a 16-bit short value.
  ///
  /// Example: `UUID.short(0x180D)` creates the Heart Rate Service UUID.
  factory UUID.short(int value) {
    if (value < 0 || value > 0xFFFF) {
      throw ArgumentError('Short UUID must be between 0x0000 and 0xFFFF');
    }

    final hex = value.toRadixString(16).padLeft(4, '0');
    return UUID('0000$hex-$_baseUuid');
  }

  /// Whether this UUID uses the Bluetooth SIG base UUID (short form).
  bool get isShort {
    return _value.endsWith('-0000-1000-8000-00805f9b34fb') &&
        _value.startsWith('0000');
  }

  /// Returns the short form if applicable, otherwise the full UUID.
  String get shortString {
    if (isShort) {
      return _value.substring(4, 8);
    }
    return _value;
  }

  /// Returns a short representation for display purposes.
  /// Uses short form for standard Bluetooth UUIDs, first 8 chars otherwise.
  String toShortString() {
    if (isShort) {
      return _value.substring(4, 8);
    }
    return _value.substring(0, 8);
  }

  @override
  String toString() => _value;

  @override
  bool operator ==(Object other) {
    return other is UUID && other._value == _value;
  }

  @override
  int get hashCode => _value.hashCode;

  static String _normalize(String value) {
    final violation = uuidTextViolation(value);
    if (violation != null) throw ArgumentError(violation);
    return canonicalUuidText(value);
  }
}
