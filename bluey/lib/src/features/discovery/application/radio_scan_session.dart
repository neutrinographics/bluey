import 'dart:async';
import 'dart:collection';

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
import '../domain/scan_result.dart';
import '../domain/scanner_phase.dart';
import 'open_scan.dart';
import 'open_scanner.dart';
import 'ports/scan_events.dart';
import 'ports/scanning.dart';

/// Runs the one [RadioScan] every scanner of a `Bluey` shares: it feeds the
/// radio scan what the handles and the radio say, does what each step
/// answers, and tells each handle what concerns it, so no handle decides
/// anything and only this unit reaches the radio.
///
/// Inputs are fed one at a time: one raised while a step is being carried
/// out waits its turn, so every step starts from the radio scan the last one
/// left.
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
  final Queue<RadioScanInput> _inputs = Queue<RadioScanInput>();
  final Map<ScannerId, _Seat> _seats = {};
  final Map<ScanId, _Held> _scans = {};
  late final StreamSubscription<ScanReport> _reports;
  late final StreamSubscription<RadioOutage> _outages;
  RadioScan _radioScan = const RadioScan.quiet();
  bool _feeding = false;
  bool _disposed = false;
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
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _feed(const ShutDown());
    for (final seat in List.of(_seats.values)) {
      unawaited(seat.close());
    }
    await _stopInFlight;
    unawaited(_reports.cancel());
    unawaited(_outages.cancel());
  }

  void _feed(RadioScanInput input) {
    _inputs.add(input);
    if (_feeding) return;
    _feeding = true;
    try {
      while (_inputs.isNotEmpty) {
        _carryOut(_step(_inputs.removeFirst()));
      }
    } finally {
      _feeding = false;
    }
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
    final held = _Held(seat, () => _leave(id, const EndedOnRequest()));
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
      if (held.seat == seat) id,
  ];
}

/// One scan the session still owes an end: its results and its end.
final class _Held {
  _Held(this.seat, void Function() onCancel)
    : results = StreamController<ScanResult>(onCancel: onCancel);

  final _Seat seat;
  final StreamController<ScanResult> results;
  final Completer<ScanEnd> ended = Completer<ScanEnd>();

  void end(ScanEnd end) {
    unawaited(results.close());
    ended.complete(end);
  }
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

  @override
  Future<Either<ScanFailure, void>> stop() {
    final scans = _session._scansOf(this).toList();
    for (final scan in scans) {
      _session._leave(scan, const EndedOnRequest());
    }
    return _session._settlingOf(scans);
  }

  @override
  Future<void> close() => _closing ??= _closed();

  Future<void> _closed() async {
    final scans = _session._scansOf(this).toList();
    _session._feed(ScannerDisposed(id));
    _session._seats.remove(id);
    unawaited(_phases.close());
    await _session._settlingOf(scans);
  }
}
