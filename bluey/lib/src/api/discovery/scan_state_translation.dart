import '../../features/discovery/domain/scanner_phase.dart';
import 'scan_state.dart';

/// The state an app reads for a scanner in [phase], so Discovery can grow
/// words of its own while every app keeps reading the states it always has.
///
/// A closed scanner reads as stopped, as a disposed one always has; only an
/// outage makes it invalidated.
ScanState scanStateOf(ScannerPhase phase) => switch (phase) {
  ScannerIdle() => ScanState.stopped,
  ScannerStarting() => ScanState.starting,
  ScannerScanning() => ScanState.scanning,
  ScannerStopping() => ScanState.stopping,
  ScannerLost() => ScanState.invalidated,
  ScannerClosed() => ScanState.stopped,
};
