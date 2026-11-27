import '../../../../shared/domain/either.dart';
import '../../../../shared/domain/radio_outage.dart';
import '../../domain/scan_ask.dart';
import '../../domain/scan_failure.dart';
import '../../domain/scan_result.dart';

/// The one way Discovery's application layer reaches the radio's scan, so a
/// session can be run over a double and over the platform alike, and never
/// learn the platform's words.
///
/// The radio runs at most one scan: asking again replaces what it scans for,
/// and results keep arriving on the same [reports].
abstract interface class Scanning {
  /// Starts scanning for [coverage], or changes what the running scan covers.
  ///
  /// A platform that refuses says so on [reports], since the refusal may
  /// arrive after this call has returned.
  void scan(ScanCoverage coverage);

  /// Stops scanning. Stopping when nothing scans succeeds, so a caller never
  /// has to know whether a refusal already ended the scan.
  Future<Either<ScanFailure, void>> stop();

  /// What the radio reports about the scan, for one listener. Reports that
  /// arrive before the listener does are kept. Carries no errors.
  Stream<ScanReport> get reports;

  /// Each time the adapter leaves `on`, for any number of listeners.
  Stream<RadioOutage> get outages;
}

/// What the radio says about the scan it runs.
sealed class ScanReport {
  const ScanReport();
}

/// The radio heard a device.
final class Heard extends ScanReport {
  const Heard(this.result);

  final ScanResult result;

  @override
  bool operator ==(Object other) => other is Heard && other.result == result;

  @override
  int get hashCode => Object.hash(Heard, result);
}

/// The radio ended the running scan by refusing it, which leaves it not
/// scanning.
final class Refused extends ScanReport {
  const Refused(this.failure);

  final ScanFailure failure;

  @override
  bool operator ==(Object other) =>
      other is Refused && other.failure == failure;

  @override
  int get hashCode => Object.hash(Refused, failure);
}
