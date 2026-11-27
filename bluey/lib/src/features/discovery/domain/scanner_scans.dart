import 'package:meta/meta.dart';

import '../../../shared/domain/radio_outage.dart';
import 'scan_ask.dart';
import 'scan_event.dart';
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
/// order asked, and whether it is lost or closed for good.
///
/// An ended scan is kept for one step only, so its end can be read in the
/// step that ended it and a scanner that lives for hours holds few scans.
@immutable
final class ScannerScans {
  const ScannerScans.none()
    : scans = const [],
      _terminal = null,
      _closedByApp = false;

  ScannerScans._(List<HeldScan> scans, this._terminal, this._closedByApp)
    : scans = List.unmodifiable(scans);

  final List<HeldScan> scans;

  /// Lost or closed, set by the radio scan and never undone: closing a lost
  /// scanner keeps it lost, so its holder is still told the outage ended it.
  final ScannerPhase? _terminal;

  /// Whether the app closed the scanner, lost first or not.
  final bool _closedByApp;

  /// Where the scanner stands: lost or closed once it is, otherwise from its
  /// own scans alone, since the radio's phase is not a scanner's business.
  ScannerPhase get standing => _terminal ?? _ownStanding;

  /// Whether nothing is left to tell of the scanner: the app closed it and
  /// none of its scans is still to end.
  bool get isSpent =>
      _closedByApp && scans.every((scan) => scan.phase is Ended);

  /// Whether the scanner may still ask for scans.
  bool get mayAsk => _terminal == null;

  ScannerPhase get _ownStanding =>
      ScannerPhase.of(scans.map((scan) => scan.phase));

  /// The scan named [id], or null when this scanner does not hold it.
  HeldScan? find(ScanId id) {
    for (final scan in scans) {
      if (scan.id == id) return scan;
    }
    return null;
  }

  /// This scanner with [id] asked for [ask], standing at [phase].
  ScannerScans asked(ScanId id, ScanAsk ask, ScanPhase phase) => ScannerScans._(
    [...scans, HeldScan(id, ask, phase)],
    _terminal,
    _closedByApp,
  );

  /// This scanner with [id] asked for [ask] and ended at once by the outage
  /// that lost it, or null when the scanner is not lost.
  ScannerScans? askedWhileLost(ScanId id, ScanAsk ask) => switch (_terminal) {
    ScannerLost(:final outage) => asked(
      id,
      ask,
      Ended(EndedByRadioOutage(outage)),
    ),
    _ => null,
  };

  /// This scanner with each scan moved to what [change] answers for it,
  /// or left where it is when [change] answers null.
  ScannerScans moved(ScanPhase? Function(HeldScan scan) change) =>
      ScannerScans._(
        [
          for (final scan in scans)
            HeldScan(scan.id, scan.ask, change(scan) ?? scan.phase),
        ],
        _terminal,
        _closedByApp,
      );

  /// This scanner without the scans that had already ended.
  ScannerScans withoutEnded() => ScannerScans._(
    [
      for (final scan in scans)
        if (scan.phase is! Ended) scan,
    ],
    _terminal,
    _closedByApp,
  );

  /// This scanner lost to [outage], unless the app already closed it.
  ScannerScans lost(RadioOutage outage) =>
      ScannerScans._(scans, _terminal ?? ScannerLost(outage), _closedByApp);

  /// This scanner closed by the app; a scan still leaving keeps its place
  /// until the radio's stop ends it.
  ScannerScans closed() =>
      ScannerScans._(scans, _terminal ?? const ScannerClosed(), true);

  /// What [scanner] raised in moving from [before] to this: each scan that
  /// ended, then the change of the scanner's own standing.
  ///
  /// The standing compared is the one its scans give, not lost or closed,
  /// so a closed scanner's leaving scan still raises what any scan leaving
  /// raises.
  List<ScanEvent> eventsSince(
    ScannerScans before,
    ScannerId scanner,
    DateTime at,
  ) {
    final ended = [
      for (final scan in scans)
        if (scan.phase case Ended(
          :final end,
        ) when before.find(scan.id)?.phase is! Ended)
          (scan.id, end),
    ];
    ScanAsk latest() => scans.lastWhere((scan) => scan.phase is! Ended).ask;
    final from = before._ownStanding;
    final to = _ownStanding;
    final moved = switch ((from, to)) {
      _ when from == to => const <ScanEvent>[],
      (ScannerStarting(), ScannerScanning()) => [
        ScannerStarted(scanner, latest(), at),
      ],
      (_, ScannerScanning()) => [
        ScannerBeganStarting(scanner, latest(), at),
        ScannerStarted(scanner, latest(), at),
      ],
      (_, ScannerStarting()) => [ScannerBeganStarting(scanner, latest(), at)],
      (_, ScannerStopping()) => [ScannerBeganStopping(scanner, at)],
      _ => [
        if (ended.lastOrNull case (_, final end))
          ScannerStopped(scanner, end, at),
      ],
    };
    return [for (final (id, end) in ended) ScanEnded(id, end, at), ...moved];
  }
}
