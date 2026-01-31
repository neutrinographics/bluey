/// A 128-bit Bluetooth UUID with support for short-form notation.
///
/// This is a value object in the Domain layer. UUIDs are immutable and
/// equality is based on value, not identity.
///
/// Bluetooth UUIDs can be either:
/// - Full 128-bit: '0000180d-0000-1000-8000-00805f9b34fb'
/// - Short 16-bit (Bluetooth SIG assigned): '180d' or 0x180D
///
/// Short UUIDs are expanded using the Bluetooth base UUID:
/// 0000xxxx-0000-1000-8000-00805f9b34fb
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

  /// Normalizes a UUID string to lowercase with hyphens.
  static String _normalize(String value) {
    if (value.isEmpty) {
      throw ArgumentError('UUID cannot be empty');
    }

    // Remove hyphens and convert to lowercase
    final clean = value.replaceAll('-', '').toLowerCase();

    // Validate length
    if (clean.length != 32) {
      throw ArgumentError('UUID must be 32 hex characters (128 bits)');
    }

    // Validate hex characters
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(clean)) {
      throw ArgumentError('UUID must contain only hexadecimal characters');
    }

    // Add hyphens in standard format
    return '${clean.substring(0, 8)}-'
        '${clean.substring(8, 12)}-'
        '${clean.substring(12, 16)}-'
        '${clean.substring(16, 20)}-'
        '${clean.substring(20, 32)}';
  }
}
