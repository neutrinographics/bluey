/// @docImport '../../bluey.dart';
library;

import '../../shared/domain/uuid.dart';
import '../../features/discovery/domain/scan_mode.dart';
import '../../features/discovery/domain/scan_result.dart';
import 'scan_state.dart';

export '../../features/discovery/domain/advertisement.dart';
export '../../features/discovery/domain/device.dart';
export '../../features/discovery/domain/scan_mode.dart';
export '../../features/discovery/domain/scan_result.dart';

/// The app's face of scanning: one scanner of the radio scan every scanner
/// of a [Bluey] shares, so two scanners never replace or stop each other's
/// scans. Obtain one from [Bluey.scanner] and [dispose] it when done.
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
  /// Current scan state. Replays via [stateChanges]. See [ScanState].
  ScanState get state;

  /// State transitions, replayed on subscribe (per-subscriber Stream.multi
  /// pattern). Terminal: emits [ScanState.invalidated] then closes on
  /// adapter invalidation.
  Stream<ScanState> get stateChanges;

  /// Whether a scan is currently in progress. Derived from [state].
  /// Kept for ergonomic convenience.
  bool get isScanning;

  /// Start scanning for nearby BLE devices.
  ///
  /// Returns a stream of [ScanResult]s. Each result pairs a stable device
  /// identity with transient observation data (rssi, advertisement, lastSeen).
  ///
  /// [services] - Optional list of service UUIDs to filter by.
  /// [timeout] - Optional timeout duration.
  /// [mode] - Optional scan duty cycle (Android only; see [ScanMode]).
  ///
  /// The scan starts at the call, so a stream nobody listens to buffers its
  /// results until [stop], its [timeout] or [dispose] ends it. Several scans
  /// per scanner may be open at once, each with its own filter and timeout.
  /// A refused scan arrives as one stream error, then done.
  Stream<ScanResult> scan({
    List<UUID>? services,
    Duration? timeout,
    ScanMode? mode,
  });

  /// Stop the current scan.
  ///
  /// Idempotent - calling stop when not scanning is a no-op.
  Future<void> stop();

  /// Release all resources held by this scanner.
  void dispose();
}
