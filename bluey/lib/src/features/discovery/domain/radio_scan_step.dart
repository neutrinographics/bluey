import 'package:meta/meta.dart';

import 'radio_scan.dart';
import 'scan_ask.dart';
import 'scan_event.dart';

/// What the owner of the radio scan must now do to the radio because of a
/// step, which the aggregate cannot do itself: it touches no radio.
@immutable
sealed class RadioDuty {
  const RadioDuty();
}

/// Ask the radio to scan for [coverage]. A platform scan replaces whatever
/// the radio is doing, so the one duty both starts and widens a scan.
final class ScanFor extends RadioDuty {
  const ScanFor(this.coverage);

  final ScanCoverage coverage;

  @override
  bool operator ==(Object other) =>
      other is ScanFor && other.coverage == coverage;

  @override
  int get hashCode => Object.hash(ScanFor, coverage);
}

/// Ask the radio to stop, and feed back how the stop settled.
final class StopTheRadio extends RadioDuty {
  const StopTheRadio();

  @override
  bool operator ==(Object other) => other is StopTheRadio;

  @override
  int get hashCode => (StopTheRadio).hashCode;
}

/// The answer to one input: the radio scan as it now stands, what it raised
/// and the duty, if any, the input left its owner.
final class RadioScanStep {
  RadioScanStep(this.scan, {List<ScanEvent> events = const [], this.duty})
    : events = List.unmodifiable(events);

  /// The radio scan after the input.
  final RadioScan scan;

  /// What the step raised, in order.
  final List<ScanEvent> events;

  /// What the owner must now do to the radio, or null when nothing is due.
  final RadioDuty? duty;
}
