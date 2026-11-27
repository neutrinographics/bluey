import 'dart:async';

import 'package:bluey/src/features/discovery/application/ports/scanning.dart';
import 'package:bluey/src/features/discovery/domain/scan_ask.dart';
import 'package:bluey/src/features/discovery/domain/scan_failure.dart';
import 'package:bluey/src/features/discovery/domain/scan_result.dart';
import 'package:bluey/src/shared/domain/either.dart';
import 'package:bluey/src/shared/domain/radio_outage.dart';

import 'scanning_contract.dart';

/// A radio in memory, so Discovery's application units can be tested against
/// [Scanning] without a platform.
///
/// It is its own [ScanningHarness], and adds counts of what was asked of it.
class InMemoryScanning implements Scanning, ScanningHarness {
  /// With [outagesAtOnce], an outage reaches its listeners inside the call
  /// that reports it, so a test can raise one in the middle of a step.
  InMemoryScanning({bool outagesAtOnce = false})
    : _outages = StreamController<RadioOutage>.broadcast(sync: outagesAtOnce);

  final StreamController<ScanReport> _reports = StreamController<ScanReport>();
  final StreamController<RadioOutage> _outages;
  final List<ScanCoverage> _coverages = [];
  ScanCoverage? _scanningFor;
  int _stopsAsked = 0;
  bool _failNextStop = false;
  Completer<void>? _heldStop;
  bool _holdNextStop = false;

  /// How many times a scan was asked for.
  int get scansAsked => _coverages.length;

  /// How many times a stop was asked for.
  int get stopsAsked => _stopsAsked;

  /// Every coverage a scan was asked for, in order.
  List<ScanCoverage> get coverages => List.unmodifiable(_coverages);

  @override
  Scanning get scanning => this;

  @override
  ScanCoverage? get scanningFor => _scanningFor;

  @override
  void scan(ScanCoverage coverage) {
    _coverages.add(coverage);
    _scanningFor = coverage;
  }

  @override
  Future<Either<ScanFailure, void>> stop() async {
    _stopsAsked++;
    final stopping = _scanningFor;
    if (_holdNextStop) {
      _holdNextStop = false;
      final held = _heldStop = Completer<void>();
      await held.future;
    }
    if (_failNextStop) {
      _failNextStop = false;
      return const Left(
        UnexpectedScanFailure('the radio did not stop', cause: 'in memory'),
      );
    }
    if (identical(_scanningFor, stopping)) _scanningFor = null;
    return const Right(null);
  }

  @override
  Stream<ScanReport> get reports => _reports.stream;

  @override
  Stream<RadioOutage> get outages => _outages.stream;

  @override
  void hear(ScanResult result) {
    if (_scanningFor == null) return;
    _reports.add(Heard(result));
  }

  @override
  void refuse(ScanRefusalReason reason) {
    if (_scanningFor == null) return;
    _scanningFor = null;
    _reports.add(Refused(ScanRefused(reason)));
  }

  @override
  void failNextStop() => _failNextStop = true;

  @override
  void holdNextStop() => _holdNextStop = true;

  @override
  void releaseStop() {
    _heldStop?.complete();
    _heldStop = null;
  }

  @override
  void outage(RadioOutage outage) => _outages.add(outage);
}
