import 'package:meta/meta.dart';

import 'radio_phase.dart';
import 'radio_scan_input.dart';
import 'radio_scan_step.dart';
import 'scan_ask.dart';
import 'scan_id.dart';
import 'scan_phase.dart';
import 'scanner_phase.dart';
import 'scanner_scans.dart';

export 'radio_scan_step.dart';

/// The one radio scan every open scan shares, which decides what each input
/// does to the radio and to every scan, so no two scans can ask the radio
/// for conflicting things.
///
/// It is a value: [on] answers the next radio scan and leaves this one as it
/// was. Coverage only widens while the radio scans, since narrowing would be
/// another radio start and platforms throttle starts; an ask while a stop is
/// in flight waits for the stop to settle.
@immutable
final class RadioScan {
  /// No scanner, no scan, the radio quiet.
  const RadioScan.quiet() : radio = const RadioQuiet(), _scanners = const {};

  RadioScan._(this.radio, Map<ScannerId, ScannerScans> scanners)
    : _scanners = Map.unmodifiable(scanners);

  /// Where the shared radio stands.
  final RadioPhase radio;

  final Map<ScannerId, ScannerScans> _scanners;

  /// Where [scan] stands, or null for a scan never asked.
  ScanPhase? phaseOf(ScanId scan) => _held(scan)?.phase;

  /// Where [scanner] stands, or null for a scanner never opened.
  ScannerPhase? standingOf(ScannerId scanner) => _scanners[scanner]?.standing;

  /// Answers what [input], which came at [at], does to the radio and every
  /// scan.
  RadioScanStep on(RadioScanInput input, {required DateTime at}) => switch ((
    radio,
    input,
  )) {
    (_, ScannerOpened(:final scanner)) => _opened(scanner),
    (_, ScannerDisposed(:final scanner)) => _disposed(scanner, at),
    (_, ResultHeard()) => RadioScanStep(this),
    (
      RadioQuiet() || RadioUnsure(),
      ScanAsked(:final scanner, :final id, :final ask),
    ) =>
      _servedAlone(scanner, id, ask),
    (
      RadioScanning(:final coverage),
      ScanAsked(:final scanner, :final id, :final ask),
    ) =>
      _servedAlongside(coverage, scanner, id, ask),
    (RadioStopping(), ScanAsked(:final scanner, :final id, :final ask)) =>
      RadioScanStep(_asked(scanner, id, ask, const Waiting())),
    (RadioQuiet() || RadioUnsure(), ScanLeft()) => RadioScanStep(this),
    (RadioScanning(), ScanLeft(:final id, :final end)) => _leftWhileScanning(
      id,
      end,
    ),
    (RadioStopping(), ScanLeft(:final id, :final end)) => _leftWhileStopping(
      id,
      end,
    ),
    (RadioStopping(), RadioStopped()) => _settled(
      ifNoneWait: const RadioQuiet(),
    ),
    (final RadioStopping stopping, RadioStopFailed()) => _settled(
      ifNoneWait:
          stopping.outage == null ? const RadioUnsure() : const RadioQuiet(),
    ),
    (
      RadioQuiet() || RadioScanning() || RadioUnsure(),
      RadioStopped() || RadioStopFailed(),
    ) =>
      throw StateError('A stop settled while no stop was in flight.'),
    (RadioScanning(), RadioRefused(:final failure)) => _ending(
      EndedByFailure(failure),
      radio: const RadioQuiet(),
    ),
    (RadioQuiet() || RadioUnsure() || RadioStopping(), RadioRefused()) =>
      RadioScanStep(this),
    (RadioScanning(), RadioWentAway(:final outage)) => _ending(
      EndedByRadioOutage(outage),
      radio: const RadioQuiet(),
    ),
    (RadioStopping(), RadioWentAway(:final outage)) => _ending(
      EndedByRadioOutage(outage),
      radio: RadioStopping(outage: outage),
      leaversToo: true,
    ),
    (RadioQuiet() || RadioUnsure(), RadioWentAway()) => RadioScanStep(
      RadioScan._(const RadioQuiet(), _scanners),
    ),
    (RadioScanning(), ShutDown()) => _ending(
      const EndedOnRequest(),
      radio: const RadioStopping(),
      duty: const StopTheRadio(),
    ),
    (RadioUnsure(), ShutDown()) => RadioScanStep(
      RadioScan._(const RadioStopping(), _scanners),
      duty: const StopTheRadio(),
    ),
    (final RadioStopping stopping, ShutDown()) => _ending(
      const EndedOnRequest(),
      radio: stopping,
    ),
    (RadioQuiet(), ShutDown()) => RadioScanStep(this),
  };

  RadioScanStep _opened(ScannerId scanner) =>
      _scanners.containsKey(scanner)
          ? RadioScanStep(this)
          : RadioScanStep(
            RadioScan._(radio, {
              ..._scanners,
              scanner: const ScannerScans.none(),
            }),
          );

  /// Each of the scanner's open scans leaves as if told to one by one, so
  /// the last of all to leave stops the radio, once.
  RadioScanStep _disposed(ScannerId scanner, DateTime at) {
    final open = _scanners[scanner]?.scans.where((scan) => scan.isOpen) ?? [];
    var step = RadioScanStep(this);
    for (final scan in open) {
      final next = step.scan.on(
        ScanLeft(scan.id, const EndedOnRequest()),
        at: at,
      );
      step = RadioScanStep(next.scan, duty: next.duty ?? step.duty);
    }
    return step;
  }

  RadioScanStep _servedAlone(ScannerId scanner, ScanId id, ScanAsk ask) {
    final coverage = ScanCoverage.of([ask]);
    return RadioScanStep(
      _asked(scanner, id, ask, const Served(), RadioScanning(coverage)),
      duty: ScanFor(coverage),
    );
  }

  RadioScanStep _servedAlongside(
    ScanCoverage coverage,
    ScannerId scanner,
    ScanId id,
    ScanAsk ask,
  ) {
    if (coverage.covers(ask)) {
      return RadioScanStep(_asked(scanner, id, ask, const Served()));
    }
    final widened = coverage.widenedBy(ask);
    return RadioScanStep(
      _asked(scanner, id, ask, const Served(), RadioScanning(widened)),
      duty: ScanFor(widened),
    );
  }

  RadioScanStep _leftWhileScanning(ScanId id, ScanEnd end) {
    if (_held(id)?.isOpen != true) return RadioScanStep(this);
    final othersStay = _allScans.any((scan) => scan.isOpen && scan.id != id);
    if (othersStay) return RadioScanStep(_movedOne(id, Ended(end), radio));
    return RadioScanStep(
      _movedOne(id, Leaving(end), const RadioStopping()),
      duty: const StopTheRadio(),
    );
  }

  RadioScanStep _leftWhileStopping(ScanId id, ScanEnd end) =>
      phaseOf(id) is Waiting
          ? RadioScanStep(_movedOne(id, Ended(end), radio))
          : RadioScanStep(this);

  /// The stop settled: each leaver reaches the end it left with, and the
  /// scans that waited for the stop are served together.
  RadioScanStep _settled({required RadioPhase ifNoneWait}) {
    final waiting = [
      for (final scan in _allScans)
        if (scan.phase is Waiting) scan.ask,
    ];
    final next =
        waiting.isEmpty ? ifNoneWait : RadioScanning(ScanCoverage.of(waiting));
    final scans = _movedEach(
      (scan) => switch (scan.phase) {
        Leaving(:final end) => Ended(end),
        Waiting() => const Served(),
        Served() || Ended() => null,
      },
    );
    return RadioScanStep(
      RadioScan._(next, scans),
      duty: next is RadioScanning ? ScanFor(next.coverage) : null,
    );
  }

  /// Every open scan, and with [leaversToo] every leaving one, ends for
  /// [end] at once.
  RadioScanStep _ending(
    ScanEnd end, {
    required RadioPhase radio,
    bool leaversToo = false,
    RadioDuty? duty,
  }) => RadioScanStep(
    RadioScan._(
      radio,
      _movedEach(
        (scan) =>
            scan.isOpen || (leaversToo && scan.phase is Leaving)
                ? Ended(end)
                : null,
      ),
    ),
    duty: duty,
  );

  Iterable<HeldScan> get _allScans =>
      _scanners.values.expand((scanner) => scanner.scans);

  HeldScan? _held(ScanId id) =>
      _scanners.values.map((scans) => scans.find(id)).nonNulls.firstOrNull;

  RadioScan _asked(
    ScannerId scanner,
    ScanId id,
    ScanAsk ask,
    ScanPhase phase, [
    RadioPhase? next,
  ]) {
    final scans = _scanners[scanner] ?? const ScannerScans.none();
    return RadioScan._(next ?? radio, {
      ..._scanners,
      scanner: scans.asked(id, ask, phase),
    });
  }

  RadioScan _movedOne(ScanId id, ScanPhase phase, RadioPhase next) =>
      RadioScan._(next, _movedEach((scan) => scan.id == id ? phase : null));

  Map<ScannerId, ScannerScans> _movedEach(
    ScanPhase? Function(HeldScan scan) change,
  ) => {
    for (final MapEntry(key: id, value: scans) in _scanners.entries)
      id: scans.moved(change),
  };
}
