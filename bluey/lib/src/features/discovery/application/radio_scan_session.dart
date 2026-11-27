import 'dart:async';
import '../../../shared/application/log.dart';
import '../../../shared/application/log_level.dart';
import '../../../shared/application/now.dart';
import '../../../shared/domain/either.dart';
import '../../../shared/domain/radio_outage.dart';
import '../domain/radio_duty.dart';
import '../domain/radio_scan.dart';
import '../domain/radio_scan_input.dart';
import '../domain/scan_ask.dart';
import '../domain/scan_event.dart';
import '../domain/scan_failure.dart';
import '../domain/scan_id.dart';
import '../domain/scan_phase.dart';
import '../domain/scanner_phase.dart';
import 'open_scan.dart';
import 'open_scanner.dart';
import 'owed_scan.dart';
import 'scan_turns.dart';
import 'ports/scan_events.dart';
import 'ports/scanning.dart';

/// Runs the one [RadioScan] every scanner of a `Bluey` shares: it feeds the
/// radio scan what the handles and the radio say, does what each step
/// answers, and tells each handle what concerns it, so no handle decides
/// anything and only this unit reaches the radio.
///
/// Inputs are fed one at a time ([ScanTurns]): one raised while a step is
/// being carried out waits its turn, and so does a handle's call that reads
/// the radio scan, so a listener told synchronously can call back safely.
final class RadioScanSession {
  RadioScanSession({
    required Scanning scanning,
    required ScanEvents events,
    required Log log,
    required Now now,
  }) : _scanning = scanning,
       _events = events,
       _log = log,
       _now = now {
    _reports = scanning.reports.listen(
      (report) => _feed(switch (report) {
        Heard(:final result) => ResultHeard(result),
        Refused(:final failure) => RadioRefused(failure),
      }),
    );
    _outages = scanning.outages.listen(
      (outage) => _feed(RadioWentAway(outage)),
    );
  }

  final Scanning _scanning;
  final ScanEvents _events;
  final Log _log;
  final Now _now;
  late final ScanTurns _turns = ScanTurns(_take);
  final Map<ScannerId, _Seat> _seats = {};
  final Map<ScanId, OwedScan> _scans = {};
  late final StreamSubscription<ScanReport> _reports;
  late final StreamSubscription<RadioOutage> _outages;
  RadioScan _radioScan = const RadioScan.quiet();
  bool _disposed = false;
  Future<void>? _disposal;
  int _lastScanner = 0;
  int _lastScan = 0;
  Future<Either<ScanFailure, void>>? _stopInFlight;

  /// A new scanner, idle. A [StateError] once the session is disposed.
  OpenScanner openScanner() {
    if (_disposed) throw StateError('The radio scan session is disposed.');
    final id = ScannerId(++_lastScanner);
    final seat = _seats[id] = _Seat(this, id);
    _feed(ScannerOpened(id));
    return OpenScanner(seat);
  }

  /// Ends every scan and closes every scanner, and answers once the radio
  /// stop that needed, or one already in flight, has settled.
  Future<void> dispose() => _disposal ??= _shutDown();

  Future<void> _shutDown() async {
    _disposed = true;
    final stopped = Completer<void>();
    _decide(() {
      _feed(const ShutDown());
      for (final seat in List.of(_seats.values)) {
        unawaited(seat.close());
      }
      _decide(() => stopped.complete(_stopInFlight?.then((_) {})));
    });
    await stopped.future;
    unawaited(_reports.cancel());
    unawaited(_outages.cancel());
  }

  void _feed(RadioScanInput input) => _turns.feed(input);

  void _decide(void Function() decision) => _turns.decide(decision);

  /// A scan asked behind an outage that lost its scanner ends with that
  /// outage, since the radio scan refuses an ask from a lost scanner; a
  /// closed scanner never gets this far, as its seat refuses at once.
  void _take(RadioScanInput input) {
    if (input case ScanAsked(:final scanner, :final id)) {
      if (_radioScan.standingOf(scanner) case ScannerLost(:final outage)) {
        _scans.remove(id)?.end(EndedByRadioOutage(outage));
        return;
      }
    }
    _carryOut(_step(input));
  }

  /// Stores what [input] does, then tells of it, so whoever hears of a step
  /// reads the radio scan as the step left it.
  RadioScanStep _step(RadioScanInput input) {
    final step = _radioScan.on(input, at: _now());
    _radioScan = step.scan;
    for (final seat in List.of(_seats.values)) {
      seat.moved(_radioScan.standingOf(seat.id));
    }
    for (final event in step.events) {
      _events.raise(event);
      switch (event) {
        case ResultDelivered(:final result, :final scans):
          for (final id in scans) {
            _scans[id]?.results.add(result);
          }
        case ScanEnded(:final scan, :final end):
          _scans.remove(scan)?.end(end);
        case ScannerBeganStarting() ||
            ScannerStarted() ||
            ScannerBeganStopping() ||
            ScannerStopped():
          break;
      }
    }
    return step;
  }

  void _carryOut(RadioScanStep step) {
    switch (step.duty) {
      case ScanFor(:final coverage):
        _scanning.scan(coverage);
      case StopTheRadio():
        _stopInFlight = _stop();
      case null:
        break;
    }
  }

  Future<Either<ScanFailure, void>> _stop() async {
    final answer = await _scanning.stop();
    _stopInFlight = null;
    switch (answer) {
      case Left(:final value):
        _log.log(
          BlueyLogLevel.warn,
          'bluey',
          'scan stop failed',
          data: {'error': value.message},
          errorCode: value.runtimeType.toString(),
        );
        _feed(RadioStopFailed(value));
      case Right():
        _feed(const RadioStopped());
    }
    return answer;
  }

  OpenScan _open(_Seat seat, ScanAsk ask) {
    final id = ScanId(++_lastScan);
    final held = OwedScan(seat.id, () => _leave(id, const EndedOnRequest()));
    _scans[id] = held;
    final scan = OpenScan(
      id: id,
      results: held.results.stream,
      ended: held.ended.future,
      leaveWith: (end) => _leave(id, end),
      timeLimit: ask.timeLimit,
    );
    _feed(ScanAsked(seat.id, id, ask));
    return scan;
  }

  void _leave(ScanId id, ScanEnd end) {
    if (_scans.containsKey(id)) _feed(ScanLeft(id, end));
  }

  /// The stop in flight when one of [scans] is leaving for it, since then
  /// that stop is the one whose settling ends them.
  Future<Either<ScanFailure, void>> _settlingOf(Iterable<ScanId> scans) {
    final inFlight = _stopInFlight;
    final waitsForStop = scans.any((id) => _radioScan.phaseOf(id) is Leaving);
    if (inFlight != null && waitsForStop) return inFlight;
    return Future.value(const Right(null));
  }

  Iterable<ScanId> _scansOf(_Seat seat) => [
    for (final MapEntry(key: id, value: held) in _scans.entries)
      if (held.scanner == seat.id) id,
  ];
}

/// One scanner as the session tracks it: the phase the radio scan last gave
/// it, kept once the radio scan forgets a closed scanner.
final class _Seat implements ScannerSeat {
  _Seat(this._session, this.id);

  final RadioScanSession _session;
  final ScannerId id;
  final StreamController<ScannerPhase> _phases =
      StreamController<ScannerPhase>.broadcast();
  Future<void>? _closing;

  @override
  ScannerPhase phase = const ScannerIdle();

  @override
  Stream<ScannerPhase> get phases => _phases.stream;

  void moved(ScannerPhase? next) {
    if (next == null || next == phase) return;
    phase = next;
    _phases.add(next);
  }

  @override
  Either<ScannerUnusable, OpenScan> scan(ScanAsk ask) => switch (phase) {
    ScannerLost() || ScannerClosed() => Left(ScannerUnusable(phase)),
    _ when _closing != null => const Left(ScannerUnusable(ScannerClosed())),
    _ => Right(_session._open(this, ask)),
  };

  /// Decided once the inputs queued before it are stepped, so a stop made
  /// from inside a step leaves the scans those steps leave open.
  @override
  Future<Either<ScanFailure, void>> stop() {
    final settled = Completer<Either<ScanFailure, void>>();
    _session._decide(() {
      final scans = _session._scansOf(this).toList();
      for (final scan in scans) {
        _session._leave(scan, const EndedOnRequest());
      }
      _session._decide(() => settled.complete(_session._settlingOf(scans)));
    });
    return settled.future;
  }

  @override
  Future<void> close() => _closing ??= _closed();

  /// The seat is let go only once its disposal has been stepped, so its
  /// phases tell it closed before they end.
  Future<void> _closed() {
    final settled = Completer<void>();
    _session._decide(() {
      final scans = _session._scansOf(this).toList();
      _session._feed(ScannerDisposed(id));
      _session._decide(() {
        _session._seats.remove(id);
        unawaited(_phases.close());
        settled.complete(_session._settlingOf(scans).then((_) {}));
      });
    });
    return settled.future;
  }
}
