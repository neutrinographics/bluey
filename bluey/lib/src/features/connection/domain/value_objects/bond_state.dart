/// Bonding state of a device.
///
/// Bonding (also known as pairing) establishes a trusted relationship
/// between devices that persists across connections. Bonded devices
/// can reconnect without re-pairing and may have access to encrypted
/// characteristics.
enum BondState {
  /// No bond exists with this device.
  none,

  /// Bonding is in progress.
  ///
  /// The user may be prompted to confirm a pairing code.
  bonding,

  /// The device is bonded.
  ///
  /// The bond persists across disconnections and app restarts.
  bonded,
}
