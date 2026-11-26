/// BLE Physical Layer (PHY) options.
///
/// The PHY determines the radio modulation used for the connection,
/// affecting throughput, range, and power consumption.
enum Phy {
  /// 1 Mbps PHY (default, most compatible).
  ///
  /// This is the standard BLE PHY supported by all BLE devices.
  /// Good balance of range, speed, and compatibility.
  le1m,

  /// 2 Mbps PHY (faster, shorter range).
  ///
  /// Doubles the data rate compared to LE 1M, reducing transmission
  /// time and power consumption for large transfers. However, it has
  /// slightly reduced range. Requires Bluetooth 5.0+.
  le2m,

  /// Coded PHY (longer range, slower).
  ///
  /// Uses forward error correction for improved sensitivity, enabling
  /// significantly longer range (up to 4x LE 1M). The tradeoff is lower
  /// throughput. Requires Bluetooth 5.0+.
  leCoded,
}

/// The PHY of each direction of a link, which can differ.
typedef PhyPair = ({Phy tx, Phy rx});
