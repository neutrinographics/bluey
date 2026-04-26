import 'uuid.dart';

/// Coerces a platform device identifier into a domain-level [UUID].
///
/// Two platform conventions converge here:
///
/// - **iOS** identifies peripherals with UUIDs already (`CBPeripheral.identifier`).
///   Inputs in 36-character hyphenated form pass through unchanged.
/// - **Android** identifies devices with MAC addresses (e.g.
///   `"AA:BB:CC:DD:EE:FF"`). The colons are stripped, the hex is
///   lowercased, and the result is left-padded with zeros to 32 hex
///   characters before being parsed as a UUID. This produces a
///   deterministic — but synthetic — UUID for the device.
///
/// This synthesis is a workaround, not a model: see
/// [I006](../../../../docs/backlog/I006-mac-to-uuid-truncation.md)
/// for the underlying typed-identifier issue. I057 consolidated the
/// previously-duplicated copies of this function so that I006's eventual
/// fix has only one site to rewrite.
UUID deviceIdToUuid(String id) {
  // Already in UUID format (iOS path).
  if (id.length == 36 && id.contains('-')) {
    return UUID(id);
  }
  // MAC address (Android path): strip colons, lowercase, left-pad to 32 hex.
  final clean = id.replaceAll(':', '').toLowerCase();
  final padded = clean.padLeft(32, '0');
  return UUID(padded);
}
