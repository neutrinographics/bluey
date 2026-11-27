import 'package:meta/meta.dart';

import '../../../shared/domain/radio_outage.dart';
import 'scan_ask.dart';

/// Where the one radio shared by every scan stands, which is what decides
/// whether an ask is served at once, waits, or needs the radio restarted.
@immutable
sealed class RadioPhase {
  const RadioPhase();
}

/// The radio is not scanning.
final class RadioQuiet extends RadioPhase {
  const RadioQuiet();

  @override
  bool operator ==(Object other) => other is RadioQuiet;

  @override
  int get hashCode => (RadioQuiet).hashCode;
}

/// The radio was asked to scan for [coverage]; it confirms no start, so this
/// is what was asked, and a refusal arrives later.
final class RadioScanning extends RadioPhase {
  const RadioScanning(this.coverage);

  final ScanCoverage coverage;

  @override
  bool operator ==(Object other) =>
      other is RadioScanning && other.coverage == coverage;

  @override
  int get hashCode => Object.hash(RadioScanning, coverage);
}

/// A stop is in flight, and the phase is left only when it settles, so two
/// stops are never in flight at once.
final class RadioStopping extends RadioPhase {
  const RadioStopping({this.outage});

  /// Set when the radio went away while the stop was in flight: then the
  /// radio is not scanning however the stop settles, so a failed stop leaves
  /// it quiet rather than unsure.
  final RadioOutage? outage;

  @override
  bool operator ==(Object other) =>
      other is RadioStopping && other.outage == outage;

  @override
  int get hashCode => Object.hash(RadioStopping, outage);
}

/// A stop failed, so the radio may or may not still be scanning; no scan is
/// open. A new scan replaces whatever it is doing.
final class RadioUnsure extends RadioPhase {
  const RadioUnsure();

  @override
  bool operator ==(Object other) => other is RadioUnsure;

  @override
  int get hashCode => (RadioUnsure).hashCode;
}
