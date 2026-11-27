/// What a step of the radio scan raises for others to hear of: a scan or a
/// scanner moving, or a result reaching scans.
///
/// Sealed so that whoever publishes these switches over every kind with no
/// default, and a new kind does not compile until it is published.
sealed class ScanEvent {
  /// When the input that raised it came.
  DateTime get at;
}
