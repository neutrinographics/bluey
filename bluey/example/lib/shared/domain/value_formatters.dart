import 'dart:typed_data';

/// Utility class for formatting byte values for display.
class ValueFormatters {
  ValueFormatters._();

  /// Formats bytes as a hex string with spaces between each byte.
  /// Example: [0x01, 0x02, 0x0A] -> "01 02 0A"
  static String formatHex(Uint8List bytes) {
    return bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(' ');
  }

  /// Formats bytes as an ASCII string, replacing non-printable characters with '.'.
  /// Example: [0x48, 0x69, 0x00] -> "Hi."
  static String formatAscii(Uint8List bytes) {
    return String.fromCharCodes(
      bytes.map(
        (b) => b >= 32 && b < 127 ? b : 46, // Replace non-printable with '.'
      ),
    );
  }

  /// Parses a hex string into bytes.
  /// Accepts formats like "01 02 03", "010203", "01-02-03".
  /// Throws [FormatException] if the input is invalid.
  static Uint8List parseHex(String hex) {
    final clean = hex.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    if (clean.isEmpty || clean.length % 2 != 0) {
      throw const FormatException('Invalid hex string');
    }
    final bytes = <int>[];
    for (var i = 0; i < clean.length; i += 2) {
      bytes.add(int.parse(clean.substring(i, i + 2), radix: 16));
    }
    return Uint8List.fromList(bytes);
  }

  /// Validates a hex string and returns an error message if invalid,
  /// or null if valid.
  static String? validateHex(String hex) {
    if (hex.isEmpty) return null;

    final clean = hex.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    if (clean.isEmpty) {
      return 'Enter hex characters (0-9, A-F)';
    }
    if (clean.length % 2 != 0) {
      return 'Hex string must have even length';
    }
    return null;
  }
}
