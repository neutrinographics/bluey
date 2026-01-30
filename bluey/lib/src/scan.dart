import 'device.dart';

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

/// A stream of discovered devices with scan control.
///
/// This is an enhanced [Stream] that provides control over the scanning
/// process. The stream emits [Device] objects as they are discovered.
///
/// Example:
/// ```dart
/// final scanStream = bluey.scan();
///
/// // Listen to discovered devices
/// scanStream.listen((device) {
///   print('Found: ${device.name}');
///
///   // Stop scanning once we find our device
///   if (device.name == 'My Device') {
///     scanStream.stop();
///   }
/// });
/// ```
abstract class ScanStream extends Stream<Device> {
  /// Stop scanning.
  ///
  /// This will close the stream and stop consuming power for scanning.
  /// After calling stop, the stream will complete (onDone will be called).
  Future<void> stop();

  /// Whether scanning is currently active.
  ///
  /// Returns true if scanning is in progress, false if stopped
  /// or not yet started.
  bool get isScanning;
}
