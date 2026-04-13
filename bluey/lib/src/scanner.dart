import 'scan_result.dart';
import 'uuid.dart';

/// Aggregate root for the Discovery bounded context.
///
/// A Scanner manages the lifecycle of BLE scanning operations. Obtain one
/// from [Bluey.scanner()], use it to discover nearby devices, and call
/// [dispose] when done.
///
/// This parallels [Server] for the GATT Server bounded context.
///
/// ## Usage
///
/// ```dart
/// final scanner = bluey.scanner();
///
/// // Scan for all devices
/// final subscription = scanner.scan().listen((result) {
///   print('Found: ${result.device.name} at ${result.rssi} dBm');
/// });
///
/// // Or scan with a service filter and timeout
/// final results = scanner.scan(
///   services: [UUID.short(0x180D)],
///   timeout: Duration(seconds: 10),
/// );
///
/// // Stop scanning
/// await scanner.stop();
///
/// // Release resources when done
/// scanner.dispose();
/// ```
abstract class Scanner {
  /// Whether a scan is currently in progress.
  bool get isScanning;

  /// Start scanning for nearby BLE devices.
  ///
  /// Returns a stream of [ScanResult]s. Each result pairs a stable device
  /// identity with transient observation data (rssi, advertisement, lastSeen).
  ///
  /// [services] - Optional list of service UUIDs to filter by.
  /// [timeout] - Optional timeout duration.
  Stream<ScanResult> scan({List<UUID>? services, Duration? timeout});

  /// Stop the current scan.
  ///
  /// Idempotent - calling stop when not scanning is a no-op.
  Future<void> stop();

  /// Release all resources held by this scanner.
  void dispose();
}
