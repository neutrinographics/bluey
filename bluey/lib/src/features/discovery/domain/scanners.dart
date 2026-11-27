import 'package:meta/meta.dart';

import '../../../shared/domain/radio_outage.dart';
import 'scan_ask.dart';
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

  /// How many scanners are held.
  int get length => _all.length;

  /// The scanner named [id], or null for one never opened or forgotten.
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

  /// What every scan waiting for the radio asked.
  List<ScanAsk> get waitingAsks => [
    for (final scan in scans)
      if (scan.phase is Waiting) scan.ask,
  ];

  /// These scanners with [id] asked by [scanner] for [ask], at [phase].
  Scanners asked(ScannerId scanner, ScanId id, ScanAsk ask, ScanPhase phase) =>
      withScanner(
        scanner,
        (_all[scanner] ?? const ScannerScans.none()).asked(id, ask, phase),
      );

  /// These scanners with [id] asked by [scanner], lost, and ended at once by
  /// the outage; null when [scanner] is not lost or [id] is already held.
  Scanners? askedWhileLost(ScannerId scanner, ScanId id, ScanAsk ask) {
    if (find(id) != null) return null;
    final lost = _all[scanner]?.askedWhileLost(id, ask);
    return lost == null ? null : withScanner(scanner, lost);
  }

  /// These scanners with the scan named [id] moved to [phase].
  Scanners movedOne(ScanId id, ScanPhase phase) =>
      moved((scan) => scan.id == id ? phase : null);

  /// The radio's stop settled: each leaver reaches the end it left with and
  /// every waiting scan is served.
  Scanners settled() => moved(
    (scan) => switch (scan.phase) {
      Leaving(:final end) => Ended(end),
      Waiting() => const Served(),
      Served() || Ended() => null,
    },
  );

  /// Every open scan, and with [leaversToo] every leaving one, ended for
  /// [end].
  Scanners ended(ScanEnd end, {required bool leaversToo}) => moved(
    (scan) =>
        scan.isOpen || (leaversToo && scan.phase is Leaving)
            ? Ended(end)
            : null,
  );

  /// Each scanner with its scans moved as [change] answers.
  Scanners moved(ScanPhase? Function(HeldScan scan) change) => Scanners._({
    for (final MapEntry(key: id, value: scanner) in _all.entries)
      id: scanner.moved(change),
  });

  /// Each scanner without the scans that had already ended, and without the
  /// closed scanners that have nothing left to end.
  Scanners withoutEnded() => Scanners._({
    for (final MapEntry(key: id, value: scanner) in _all.entries)
      if (!scanner.isSpent) id: scanner.withoutEnded(),
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
