import 'package:meta/meta.dart';

import '../../../shared/domain/radio_outage.dart';
import 'scan_phase.dart';

/// Where a scanner stands, in Discovery's own words, so the edge can map it
/// to the public scan state.
@immutable
sealed class ScannerPhase {
  const ScannerPhase();

  /// The standing of a scanner that is neither lost nor closed, from its
  /// scans: a served scan means it is scanning whatever else is going on, so
  /// an app is never told it is stopping while any of its scans still gets
  /// results.
  static ScannerPhase of(Iterable<ScanPhase> scans) {
    if (scans.any((scan) => scan is Served)) return const ScannerScanning();
    if (scans.any((scan) => scan is Waiting)) return const ScannerStarting();
    if (scans.any((scan) => scan is Leaving)) return const ScannerStopping();
    return const ScannerIdle();
  }
}

/// No scan is open.
final class ScannerIdle extends ScannerPhase {
  const ScannerIdle();

  @override
  bool operator ==(Object other) => other is ScannerIdle;

  @override
  int get hashCode => (ScannerIdle).hashCode;
}

/// A scan is asked for and none is served yet.
final class ScannerStarting extends ScannerPhase {
  const ScannerStarting();

  @override
  bool operator ==(Object other) => other is ScannerStarting;

  @override
  int get hashCode => (ScannerStarting).hashCode;
}

/// At least one scan receives results.
final class ScannerScanning extends ScannerPhase {
  const ScannerScanning();

  @override
  bool operator ==(Object other) => other is ScannerScanning;

  @override
  int get hashCode => (ScannerScanning).hashCode;
}

/// Every open scan is on its way out.
final class ScannerStopping extends ScannerPhase {
  const ScannerStopping();

  @override
  bool operator ==(Object other) => other is ScannerStopping;

  @override
  int get hashCode => (ScannerStopping).hashCode;
}

/// The radio became unusable under the scanner; it scans nothing until the
/// app asks again.
final class ScannerLost extends ScannerPhase {
  const ScannerLost(this.outage);

  final RadioOutage outage;

  @override
  bool operator ==(Object other) =>
      other is ScannerLost && other.outage == outage;

  @override
  int get hashCode => Object.hash(ScannerLost, outage);
}

/// The app is done with the scanner; final.
final class ScannerClosed extends ScannerPhase {
  const ScannerClosed();

  @override
  bool operator ==(Object other) => other is ScannerClosed;

  @override
  int get hashCode => (ScannerClosed).hashCode;
}
