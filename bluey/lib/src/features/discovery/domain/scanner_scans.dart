import 'package:meta/meta.dart';

import 'scan_ask.dart';
import 'scan_id.dart';
import 'scan_phase.dart';
import 'scanner_phase.dart';

/// One scan a scanner holds: what it asked and where it stands.
@immutable
final class HeldScan {
  const HeldScan(this.id, this.ask, this.phase);

  final ScanId id;
  final ScanAsk ask;
  final ScanPhase phase;

  /// Whether the scan still counts for the radio: asked and not yet told to
  /// end.
  bool get isOpen => phase is Waiting || phase is Served;
}

/// One scanner, an entity of the radio scan: the scans it asked for, in the
/// order asked, kept after they end so their end can still be read.
@immutable
final class ScannerScans {
  const ScannerScans.none() : scans = const [];

  ScannerScans._(List<HeldScan> scans) : scans = List.unmodifiable(scans);

  final List<HeldScan> scans;

  /// Where the scanner stands, from its own scans alone, since the radio's
  /// phase is not a scanner's business.
  ScannerPhase get standing => ScannerPhase.of(scans.map((scan) => scan.phase));

  /// The scan named [id], or null when this scanner never asked it.
  HeldScan? find(ScanId id) {
    for (final scan in scans) {
      if (scan.id == id) return scan;
    }
    return null;
  }

  /// This scanner with [id] asked for [ask], standing at [phase].
  ScannerScans asked(ScanId id, ScanAsk ask, ScanPhase phase) =>
      ScannerScans._([...scans, HeldScan(id, ask, phase)]);

  /// This scanner with each scan moved to what [change] answers for it,
  /// or left where it is when [change] answers null.
  ScannerScans moved(ScanPhase? Function(HeldScan scan) change) =>
      ScannerScans._([
        for (final scan in scans)
          HeldScan(scan.id, scan.ask, change(scan) ?? scan.phase),
      ]);
}
