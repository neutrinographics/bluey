import 'package:meta/meta.dart';

import '../../../shared/domain/either.dart';
import '../../../shared/domain/failure.dart';
import '../domain/scan_ask.dart';
import '../domain/scan_failure.dart';
import '../domain/scanner_phase.dart';
import 'open_scan.dart';

/// What an [OpenScanner] asks of the session that runs its scanner, so the
/// handle holds no state and decides nothing of its own.
abstract interface class ScannerSeat {
  ScannerPhase get phase;

  Stream<ScannerPhase> get phases;

  Either<ScannerUnusable, OpenScan> scan(ScanAsk ask);

  Future<Either<ScanFailure, void>> stop();

  Future<void> close();
}

/// The handle of one scanner, so an app's scanner, or one probe of peer
/// discovery, opens scans and stops them without touching anyone else's.
final class OpenScanner {
  const OpenScanner(this._seat);

  final ScannerSeat _seat;

  /// Where the scanner stands, as the radio scan last said.
  ScannerPhase get phase => _seat.phase;

  /// Each change of [phase], for any number of listeners; closes when the
  /// scanner is closed.
  Stream<ScannerPhase> get phases => _seat.phases;

  /// Opens a scan for [ask]. Answers [ScannerUnusable] from a scanner that
  /// is lost or closed, since those never scan again.
  Either<ScannerUnusable, OpenScan> scan(ScanAsk ask) => _seat.scan(ask);

  /// Every scan of this scanner leaves. Answers when the radio stop that
  /// caused, if any, has settled, so a caller that awaits it knows the radio
  /// is free; a failed stop answers its failure, and the scans still end.
  Future<Either<ScanFailure, void>> stop() => _seat.stop();

  /// Every scan leaves and the scanner can never scan again. Answers when
  /// the radio stop that caused, if any, has settled.
  Future<void> close() => _seat.close();
}

/// A scan asked of a scanner that is lost or closed.
@immutable
final class ScannerUnusable implements Failure {
  const ScannerUnusable(this.phase);

  /// Lost or closed: why the scanner cannot scan.
  final ScannerPhase phase;

  @override
  String get message => switch (phase) {
    ScannerLost(:final outage) =>
      'The scanner was lost when the radio went away (${outage.name}).',
    _ => 'The scanner is closed.',
  };

  @override
  bool operator ==(Object other) =>
      other is ScannerUnusable && other.phase == phase;

  @override
  int get hashCode => Object.hash(ScannerUnusable, phase);
}
