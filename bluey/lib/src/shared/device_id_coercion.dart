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
/// This synthesis is a workaround, not a model — a 48-bit MAC zero-padded
/// to 128 bits is not a real UUID, just a deterministic placeholder. The
/// proper fix is a typed device-identifier value object that can hold
/// either form natively; until that lands, every site that needs a UUID
/// from a platform device id calls through here so there's only one
/// place to rewrite.
UUID deviceIdToUuid(String id) {
  if (id.length == 36 && id.contains('-')) {
    return UUID(id);
  }
  final clean = id.replaceAll(':', '').toLowerCase();
  final padded = clean.padLeft(32, '0');
  return UUID(padded);
}
