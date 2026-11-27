import 'package:meta/meta.dart';

import '../../../shared/domain/radio_outage.dart';
import 'scan_event.dart';
import 'scan_id.dart';
import 'scan_phase.dart';
import 'scanner_scans.dart';

/// Every scanner of the radio scan, kept in the order they were opened,
/// which is the order their events are raised in.
@immutable
final class Scanners {
  const Scanners.none() : _all = const {};

  Scanners._(Map<ScannerId, ScannerScans> all) : _all = Map.unmodifiable(all);

  final Map<ScannerId, ScannerScans> _all;

  /// The scanner named [id], or null for one never opened.
  ScannerScans? operator [](ScannerId id) => _all[id];

  /// Every scan held, scanner by scanner.
  Iterable<HeldScan> get scans =>
      _all.values.expand((scanner) => scanner.scans);

  /// The scan named [id], or null when no scanner holds it.
  HeldScan? find(ScanId id) =>
      _all.values.map((scanner) => scanner.find(id)).nonNulls.firstOrNull;

  /// These scanners with [id] now standing as [scanner].
  Scanners withScanner(ScannerId id, ScannerScans scanner) =>
      Scanners._({..._all, id: scanner});

  /// Each scanner with its scans moved as [change] answers.
  Scanners moved(ScanPhase? Function(HeldScan scan) change) => Scanners._({
    for (final MapEntry(key: id, value: scanner) in _all.entries)
      id: scanner.moved(change),
  });

  /// Each scanner without the scans that had already ended.
  Scanners withoutEnded() => Scanners._({
    for (final MapEntry(key: id, value: scanner) in _all.entries)
      id: scanner.withoutEnded(),
  });

  /// Every scanner lost to [outage], idle or not.
  Scanners lost(RadioOutage outage) => Scanners._({
    for (final MapEntry(key: id, value: scanner) in _all.entries)
      id: scanner.lost(outage),
  });

  /// What every scanner raised in moving from [before] to these.
  List<ScanEvent> eventsSince(Scanners before, DateTime at) => [
    for (final MapEntry(key: id, value: scanner) in _all.entries)
      ...scanner.eventsSince(before[id] ?? const ScannerScans.none(), id, at),
  ];
}
