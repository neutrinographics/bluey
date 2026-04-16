import 'dart:math';
import 'dart:typed_data';

/// Stable protocol-level identity of a Bluey server.
///
/// A `ServerId` is a random v4 UUID, generated once by a server and
/// persisted however the application sees fit. It is the stable handle
/// clients use to refer to a specific Bluey server across platform
/// identifier changes (iOS session rotation, Android MAC randomization).
///
/// `ServerId` is deliberately distinct from [UUID] to keep protocol
/// identity separate from service/characteristic UUIDs in the type
/// system.
class ServerId {
  final String value;

  static final _uuidPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );

  ServerId(String value) : value = value.toLowerCase() {
    if (!_uuidPattern.hasMatch(this.value)) {
      throw ArgumentError.value(value, 'value', 'not a well-formed UUID');
    }
  }

  /// Generates a new random v4 UUID-based ServerId.
  factory ServerId.generate() {
    final random = Random.secure();
    final bytes = Uint8List(16);
    for (var i = 0; i < 16; i++) {
      bytes[i] = random.nextInt(256);
    }
    // Set version 4 (0100 in bits 4-7 of byte 6)
    bytes[6] = (bytes[6] & 0x0F) | 0x40;
    // Set variant 1 (10xx in bits 6-7 of byte 8)
    bytes[8] = (bytes[8] & 0x3F) | 0x80;

    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final formatted =
        '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20, 32)}';
    return ServerId(formatted);
  }

  /// Creates a ServerId from a 16-byte representation.
  factory ServerId.fromBytes(Uint8List bytes) {
    if (bytes.length != 16) {
      throw ArgumentError.value(
        bytes.length,
        'bytes.length',
        'must be exactly 16',
      );
    }
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final formatted =
        '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20, 32)}';
    return ServerId(formatted);
  }

  /// Returns the 16-byte representation of this ServerId.
  Uint8List toBytes() {
    final hex = value.replaceAll('-', '');
    final bytes = Uint8List(16);
    for (var i = 0; i < 16; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is ServerId && other.value == value);

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
