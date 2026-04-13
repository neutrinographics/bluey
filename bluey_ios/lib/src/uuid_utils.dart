/// Bluetooth SIG base UUID suffix for short UUID expansion.
const bluetoothBaseUuidSuffix = '-0000-1000-8000-00805f9b34fb';

/// Expands a short UUID (4 or 8 hex chars) to full 128-bit UUID string.
///
/// CoreBluetooth may return UUIDs in short form. This function normalizes
/// them to the full 128-bit format expected by the domain layer.
///
/// Examples:
/// - "180F" -> "0000180f-0000-1000-8000-00805f9b34fb"
/// - "12345678" -> "12345678-0000-1000-8000-00805f9b34fb"
/// - Full UUID -> returned as-is (lowercased with hyphens)
String expandUuid(String uuid) {
  // Remove any existing hyphens and lowercase
  final clean = uuid.replaceAll('-', '').toLowerCase();

  // 16-bit short UUID (4 hex chars)
  if (clean.length == 4) {
    return '0000$clean$bluetoothBaseUuidSuffix';
  }

  // 32-bit short UUID (8 hex chars)
  if (clean.length == 8) {
    return '$clean$bluetoothBaseUuidSuffix';
  }

  // Full 128-bit UUID (32 hex chars) - add hyphens in standard format
  if (clean.length == 32) {
    return '${clean.substring(0, 8)}-'
        '${clean.substring(8, 12)}-'
        '${clean.substring(12, 16)}-'
        '${clean.substring(16, 20)}-'
        '${clean.substring(20, 32)}';
  }

  // Unknown format - return as-is and let the domain layer handle validation
  return uuid.toLowerCase();
}
