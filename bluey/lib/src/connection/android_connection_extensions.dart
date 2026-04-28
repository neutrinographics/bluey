import 'connection.dart' show BondState, ConnectionParameters, Phy;

/// Android-specific [Connection] extensions.
///
/// Bonding, PHY, and connection-parameter operations are exposed only on
/// Android. iOS does not provide central-side APIs for these operations
/// (per Apple's CoreBluetooth design); accessing `Connection.android` on
/// iOS returns `null`.
///
/// Access via `Connection.android` with the null-aware operator:
/// ```dart
/// await connection.android?.bond();
/// final phy = connection.android?.txPhy ?? Phy.le1m;
/// ```
abstract class AndroidConnectionExtensions {
  // === Bonding ===

  /// Current bonding state.
  ///
  /// Returns the current bond state between this device and the local device.
  BondState get bondState;

  /// Stream of bonding state changes.
  ///
  /// Emits whenever the bonding state changes. Use this to react to
  /// bonding completion or failure.
  Stream<BondState> get bondStateChanges;

  /// Initiate bonding/pairing with the device.
  ///
  /// This will start the bonding process, which may prompt the user to
  /// confirm a pairing code on one or both devices.
  ///
  /// The [bondStateChanges] stream will emit [BondState.bonding] when
  /// the process starts, and [BondState.bonded] when complete.
  ///
  /// Throws [DisconnectedException] if not connected.
  Future<void> bond();

  /// Remove bond with the device.
  ///
  /// This removes the stored bonding information. The device will need
  /// to be paired again for encrypted characteristic access.
  ///
  /// Throws [DisconnectedException] if not connected.
  Future<void> removeBond();

  // === PHY ===

  /// Current transmit PHY.
  ///
  /// Returns the PHY being used for transmitting data to the device.
  Phy get txPhy;

  /// Current receive PHY.
  ///
  /// Returns the PHY being used for receiving data from the device.
  Phy get rxPhy;

  /// Stream of PHY changes.
  ///
  /// Emits whenever either the transmit or receive PHY changes.
  /// The record contains both the new transmit and receive PHY values.
  Stream<({Phy tx, Phy rx})> get phyChanges;

  /// Request specific PHY settings.
  ///
  /// Requests the controller to use the specified PHY for transmit and/or
  /// receive. The actual PHY used may differ based on what the remote
  /// device supports.
  ///
  /// [txPhy] - Preferred transmit PHY. If null, no preference is specified.
  /// [rxPhy] - Preferred receive PHY. If null, no preference is specified.
  ///
  /// The [phyChanges] stream will emit when the PHY actually changes.
  ///
  /// Throws [DisconnectedException] if not connected.
  Future<void> requestPhy({Phy? txPhy, Phy? rxPhy});

  // === Connection Parameters ===

  /// Current connection parameters.
  ///
  /// Returns the current connection parameters including interval,
  /// latency, and supervision timeout.
  ConnectionParameters get connectionParameters;

  /// Request updated connection parameters.
  ///
  /// Requests the controller to use the specified connection parameters.
  /// The actual parameters used may differ based on what the remote
  /// device and controller support.
  ///
  /// [params] - The desired connection parameters.
  ///
  /// Throws [DisconnectedException] if not connected.
  Future<void> requestConnectionParameters(ConnectionParameters params);
}
