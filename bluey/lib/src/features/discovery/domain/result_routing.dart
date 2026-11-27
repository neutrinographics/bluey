import 'radio_phase.dart';
import 'scan_event.dart';
import 'scan_id.dart';
import 'scan_phase.dart';
import 'scan_result.dart';
import 'scanner_scans.dart';

/// What hearing [result] raises while the radio is at [radio]: one delivery
/// to the served scans that should get it, or nothing when none should.
///
/// A scan gets a result its own filter shows. A result that shows none of
/// the services the radio scans for was matched by the operating system on
/// something Dart cannot see (iOS matches services in the overflow area and
/// reports only the primary packet's), so every served scan gets it rather
/// than none.
List<ScanEvent> resultRouted(
  ScanResult result, {
  required RadioPhase radio,
  required Iterable<HeldScan> scans,
  required DateTime at,
}) {
  if (radio is! RadioScanning) return const [];
  final advertisement = result.advertisement;
  final matchedUnseen = !radio.coverage.filter.shows(advertisement);
  final getting = <ScanId>{
    for (final scan in scans)
      if (scan.phase is Served &&
          (matchedUnseen || scan.ask.filter.shows(advertisement)))
        scan.id,
  };
  return getting.isEmpty ? const [] : [ResultDelivered(result, getting, at)];
}
