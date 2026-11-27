import '../../../shared/domain/radio_outage.dart';
import 'scan_ask.dart';
import 'scan_failure.dart';
import 'scan_id.dart';
import 'scan_phase.dart';
import 'scan_result.dart';

/// Everything that can happen to scanning. The set is closed, so a
/// `RadioScan` that answers each of them answers everything it can meet.
sealed class RadioScanInput {
  const RadioScanInput();
}

/// The app took a new scanner.
final class ScannerOpened extends RadioScanInput {
  const ScannerOpened(this.scanner);

  final ScannerId scanner;
}

/// The app is done with a scanner, so every scan it holds leaves.
final class ScannerDisposed extends RadioScanInput {
  const ScannerDisposed(this.scanner);

  final ScannerId scanner;
}

/// A scanner asked for a scan.
final class ScanAsked extends RadioScanInput {
  const ScanAsked(this.scanner, this.id, this.ask);

  final ScannerId scanner;
  final ScanId id;
  final ScanAsk ask;
}

/// A scan was told to end, for [end].
final class ScanLeft extends RadioScanInput {
  const ScanLeft(this.id, this.end);

  final ScanId id;
  final ScanEnd end;
}

/// The stop in flight settled: the radio is not scanning.
final class RadioStopped extends RadioScanInput {
  const RadioStopped();
}

/// The stop in flight failed, so the radio may still be scanning.
final class RadioStopFailed extends RadioScanInput {
  const RadioStopFailed(this.failure);

  final ScanFailure failure;
}

/// The platform refused the scan the radio was asked for.
final class RadioRefused extends RadioScanInput {
  const RadioRefused(this.failure);

  final ScanFailure failure;
}

/// The radio became unusable.
final class RadioWentAway extends RadioScanInput {
  const RadioWentAway(this.outage);

  final RadioOutage outage;
}

/// The radio heard an advertisement.
final class ResultHeard extends RadioScanInput {
  const ResultHeard(this.result);

  final ScanResult result;
}

/// Bluey is being disposed, so every scan ends and the radio is stopped.
final class ShutDown extends RadioScanInput {
  const ShutDown();
}
