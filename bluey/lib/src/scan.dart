/// Scan mode affects power usage and latency during BLE scanning.
enum ScanMode {
  /// Balanced power and latency (default).
  ///
  /// Use this mode for typical scanning scenarios.
  balanced,

  /// Lower latency, higher power usage.
  ///
  /// Use this when you need to discover devices quickly and
  /// battery life is less of a concern.
  lowLatency,

  /// Lower power usage, higher latency.
  ///
  /// Use this for long-running background scans where
  /// battery life is important.
  lowPower,
}
