import 'package:meta/meta.dart';

import '../../../shared/domain/radio_outage.dart';
import 'radio_phase.dart';
import 'radio_scan_input.dart';
import 'radio_scan_step.dart';
import 'result_routing.dart';
import 'scan_ask.dart';
import 'scan_id.dart';
import 'scan_phase.dart';
import 'scanner_phase.dart';
import 'scanner_scans.dart';
import 'scanners.dart';

export 'radio_scan_step.dart';

/// The one radio scan every open scan shares, which decides what each input
/// does to the radio and to every scan, so no two scans can ask the radio
/// for conflicting things.
///
/// It is a value: [on] answers the next radio scan and leaves this one as it
/// was. It alone raises the scan events, so no unit outside it derives a
/// scanner's standing. Coverage only widens while the radio scans, since
/// narrowing would be another radio start and platforms throttle starts; an
/// ask while a stop is in flight waits for the stop to settle.
@immutable
final class RadioScan {
  /// No scanner, no scan, the radio quiet.
  const RadioScan.quiet()
    : radio = const RadioQuiet(),
      _scanners = const Scanners.none();

  const RadioScan._(this.radio, this._scanners);

  /// Where the shared radio stands.
  final RadioPhase radio;

  final Scanners _scanners;

  /// Where [scan] stands, or null for a scan never asked or ended before the
  /// latest step.
  ScanPhase? phaseOf(ScanId scan) => _scanners.find(scan)?.phase;

  /// How many scans are still held, which stays bounded however many come
  /// and go.
  @visibleForTesting
  int get heldScanCount => _scanners.scans.length;

  /// Where [scanner] stands, or null for a scanner never opened.
  ScannerPhase? standingOf(ScannerId scanner) => _scanners[scanner]?.standing;

  /// Answers what [input], which came at [at], does to the radio and every
  /// scan, and the events that raised.
  ///
  /// A scan already ended when the input comes is forgotten, so the history
  /// held stays bounded. A [StateError] for an ask from a scanner never
  /// opened, lost or closed, for a scan already held, and for a scanner
  /// opened twice: the handles refuse those first.
  RadioScanStep on(RadioScanInput input, {required DateTime at}) {
    final kept = RadioScan._(radio, _scanners.withoutEnded());
    final next = kept._decided(input);
    return RadioScanStep(
      next.scan,
      events: switch (input) {
        ResultHeard(:final result) => resultRouted(
          result,
          radio: radio,
          scans: kept._scanners.scans,
          at: at,
        ),
        _ => next.scan._scanners.eventsSince(kept._scanners, at),
      },
      duty: next.duty,
    );
  }

  RadioScanStep _decided(RadioScanInput input) => switch ((radio, input)) {
    (_, ScannerOpened(:final scanner)) => _opened(scanner),
    (_, ScannerDisposed(:final scanner)) => _disposed(scanner),
    (_, ScanAsked(:final scanner, :final id)) when _refuses(scanner, id) =>
      throw StateError('Scan ${id.value} may not be asked by that scanner.'),
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
      lostTo: outage,
    ),
    (RadioStopping(), RadioWentAway(:final outage)) => _ending(
      EndedByRadioOutage(outage),
      radio: RadioStopping(outage: outage),
      leaversToo: true,
      lostTo: outage,
    ),
    (RadioQuiet() || RadioUnsure(), RadioWentAway(:final outage)) => _ending(
      EndedByRadioOutage(outage),
      radio: const RadioQuiet(),
      lostTo: outage,
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

  RadioScanStep _opened(ScannerId scanner) {
    if (_scanners[scanner] != null) {
      throw StateError('Scanner ${scanner.value} was opened twice.');
    }
    return RadioScanStep(
      RadioScan._(
        radio,
        _scanners.withScanner(scanner, const ScannerScans.none()),
      ),
    );
  }

  bool _refuses(ScannerId scanner, ScanId id) =>
      _scanners[scanner]?.mayAsk != true || _scanners.find(id) != null;

  /// Each of the scanner's open scans leaves as if told to one by one, so
  /// the last of all to leave stops the radio, once. The events are read
  /// off the whole move, so they are those of every leave in turn.
  RadioScanStep _disposed(ScannerId scanner) {
    final disposed = _scanners[scanner];
    if (disposed == null) return RadioScanStep(this);
    var step = RadioScanStep(this);
    for (final scan in disposed.scans.where((scan) => scan.isOpen)) {
      final next = step.scan._decided(
        ScanLeft(scan.id, const EndedOnRequest()),
      );
      step = RadioScanStep(next.scan, duty: next.duty ?? step.duty);
    }
    final left = step.scan._scanners;
    return RadioScanStep(
      RadioScan._(
        step.scan.radio,
        left.withScanner(scanner, (left[scanner] ?? disposed).closed()),
      ),
      duty: step.duty,
    );
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
    if (_scanners.find(id)?.isOpen != true) return RadioScanStep(this);
    final othersStay = _scanners.scans.any(
      (scan) => scan.isOpen && scan.id != id,
    );
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
      for (final scan in _scanners.scans)
        if (scan.phase is Waiting) scan.ask,
    ];
    final next =
        waiting.isEmpty ? ifNoneWait : RadioScanning(ScanCoverage.of(waiting));
    final scans = _scanners.moved(
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
  /// [end] at once; with [lostTo], every scanner is lost to that outage.
  RadioScanStep _ending(
    ScanEnd end, {
    required RadioPhase radio,
    bool leaversToo = false,
    RadioOutage? lostTo,
    RadioDuty? duty,
  }) {
    final moved = _scanners.moved(
      (scan) =>
          scan.isOpen || (leaversToo && scan.phase is Leaving)
              ? Ended(end)
              : null,
    );
    return RadioScanStep(
      RadioScan._(radio, lostTo == null ? moved : moved.lost(lostTo)),
      duty: duty,
    );
  }

  RadioScan _asked(
    ScannerId scanner,
    ScanId id,
    ScanAsk ask,
    ScanPhase phase, [
    RadioPhase? next,
  ]) {
    final scans = _scanners[scanner] ?? const ScannerScans.none();
    return RadioScan._(
      next ?? radio,
      _scanners.withScanner(scanner, scans.asked(id, ask, phase)),
    );
  }

  RadioScan _movedOne(ScanId id, ScanPhase phase, RadioPhase next) =>
      RadioScan._(
        next,
        _scanners.moved((scan) => scan.id == id ? phase : null),
      );
}
