/// The one rule for what text is a full 128-bit UUID, shared by the throwing
/// [UUID] constructor and by `uuidFrom`, so the two can never disagree about
/// what is malformed.

/// Why [raw] is not a full 128-bit UUID, or null when it is one.
String? uuidTextViolation(String raw) {
  if (raw.isEmpty) return 'UUID cannot be empty';
  final clean = _stripped(raw);
  if (clean.length != 32) {
    return 'UUID must be 32 hex characters (128 bits). '
        'Use UUID.short() for 16-bit short UUIDs.';
  }
  if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(clean)) {
    return 'UUID must contain only hexadecimal characters';
  }
  return null;
}

/// The canonical lower-case hyphenated form of [raw], which must already
/// satisfy [uuidTextViolation].
String canonicalUuidText(String raw) {
  final clean = _stripped(raw);
  return '${clean.substring(0, 8)}-'
      '${clean.substring(8, 12)}-'
      '${clean.substring(12, 16)}-'
      '${clean.substring(16, 20)}-'
      '${clean.substring(20, 32)}';
}

String _stripped(String raw) => raw.replaceAll('-', '').toLowerCase();
