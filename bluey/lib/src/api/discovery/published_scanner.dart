import 'dart:async';

import '../../features/discovery/application/open_scan.dart';
import '../../features/discovery/application/open_scanner.dart';
import '../../features/discovery/domain/scan_ask.dart';
import '../../features/discovery/domain/scan_filter.dart';
import '../../features/discovery/domain/scan_phase.dart';
import '../../features/discovery/domain/scanner_phase.dart';
import '../../platform/bluetooth_state.dart';
import '../../shared/domain/either.dart';
import '../../shared/domain/radio_outage.dart';
import '../../shared/domain/uuid.dart';
import '../../shared/exceptions.dart';
import 'scan_failure_translation.dart';
import 'scan_state.dart';
import 'scan_state_translation.dart';
import 'scanner.dart';

/// An app's [Scanner], one scanner of the radio scan every scanner of a
/// `Bluey` shares, so two scanners never replace or stop each other's scans.
final class PublishedScanner implements Scanner {
  PublishedScanner(this._scanner);

  final OpenScanner _scanner;

  /// The outage the scanner was lost to before it was disposed, kept because
  /// closing it makes it read as closed, and an app must still be told the
  /// outage, not the disposal, killed it.
  ScannerLost? _lostBeforeDisposal;

  bool _disposed = false;

  ScannerPhase get _phase {
    if (_lostBeforeDisposal case final lost?) return lost;
    if (_disposed) return const ScannerClosed();
    return _scanner.phase;
  }

  @override
  ScanState get state => scanStateOf(_phase);

  /// The current state first, to every listener, then each change; closes
  /// once the scanner is lost or closed, since its state never changes again.
  ///
  /// A scan the radio already serves passes through starting all the same,
  /// as its events do, so an app sees the states it always saw.
  @override
  Stream<ScanState> get stateChanges => Stream<ScanState>.multi((listener) {
    var last = state;
    listener.add(last);
    if (_isFinal(_phase)) {
      listener.closeSync();
      return;
    }
    late final StreamSubscription<ScannerPhase> following;
    following = _scanner.phases.listen((phase) {
      for (final next in _statesBetween(last, scanStateOf(phase))) {
        last = next;
        listener.addSync(next);
      }
      if (_isFinal(phase)) {
        unawaited(following.cancel());
        listener.closeSync();
      }
    }, onDone: listener.closeSync);
    listener.onCancel = following.cancel;
  }, isBroadcast: true);

  @override
  bool get isScanning => state == ScanState.scanning;

  @override
  Stream<ScanResult> scan({
    List<UUID>? services,
    Duration? timeout,
    ScanMode? mode,
  }) => switch (_scanner.scan(
    ScanAsk(filter: ScanFilter.of(services), mode: mode, timeLimit: timeout),
  )) {
    Left(:final value) =>
      throw StaleHandleException(
        cause: _invalidationOf(_lostBeforeDisposal ?? value.phase),
        instanceType: InvalidatedInstance.scanner,
      ),
    Right(:final value) => _resultsOf(value),
  };

  @override
  Future<void> stop() async {
    final answer = await _scanner.stop();
    if (answer case Left(:final value)) throw scanFailureAsException(value);
  }

  @override
  void dispose() {
    if (_disposed) return;
    if (_scanner.phase case final ScannerLost lost) _lostBeforeDisposal = lost;
    _disposed = true;
    unawaited(_scanner.close());
  }

  /// The scan's results for one listener; a scan that failed carries its
  /// failure as the one error before the stream ends, and cancelling leaves
  /// the scan.
  Stream<ScanResult> _resultsOf(OpenScan scan) async* {
    try {
      yield* scan.results;
    } finally {
      scan.leave();
    }
    if (await scan.ended case EndedByFailure(:final failure)) {
      throw scanFailureAsException(failure);
    }
  }
}

/// The states an app is told on the way from [from] to [to].
List<ScanState> _statesBetween(ScanState from, ScanState to) => switch ((
  from,
  to,
)) {
  _ when from == to => const [],
  (ScanState.stopped, ScanState.scanning) => const [
    ScanState.starting,
    ScanState.scanning,
  ],
  _ => [to],
};

bool _isFinal(ScannerPhase phase) =>
    phase is ScannerLost || phase is ScannerClosed;

InvalidationCause _invalidationOf(ScannerPhase phase) => switch (phase) {
  ScannerLost(:final outage) => AdapterTransitionInvalidation(
    _bluetoothStateOf(outage),
  ),
  _ => const DisposalInvalidation(),
};

BluetoothState _bluetoothStateOf(RadioOutage outage) => switch (outage) {
  RadioOutage.off => BluetoothState.off,
  RadioOutage.unauthorized => BluetoothState.unauthorized,
  RadioOutage.unsupported => BluetoothState.unsupported,
  RadioOutage.unknown => BluetoothState.unknown,
};
