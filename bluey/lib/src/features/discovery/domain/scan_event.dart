import 'package:meta/meta.dart';

import 'scan_ask.dart';
import 'scan_id.dart';
import 'scan_phase.dart';
import 'scan_result.dart';

/// What a step of the radio scan raises for others to hear of: a scan or a
/// scanner moving, or a result reaching scans.
///
/// Sealed so that whoever publishes these switches over every kind with no
/// default, and a new kind does not compile until it is published.
@immutable
sealed class ScanEvent {
  const ScanEvent();

  /// When the input that raised it came.
  DateTime get at;
}

/// A scanner with no scan served asked for one, which the radio may not
/// serve yet.
final class ScannerBeganStarting extends ScanEvent {
  const ScannerBeganStarting(this.scanner, this.ask, this.at);

  final ScannerId scanner;

  /// What the scanner's latest open scan asked for.
  final ScanAsk ask;

  @override
  final DateTime at;

  @override
  bool operator ==(Object other) =>
      other is ScannerBeganStarting &&
      other.scanner == scanner &&
      other.ask == ask &&
      other.at == at;

  @override
  int get hashCode => Object.hash(ScannerBeganStarting, scanner, ask, at);
}

/// A scanner's scan now receives results.
final class ScannerStarted extends ScanEvent {
  const ScannerStarted(this.scanner, this.ask, this.at);

  final ScannerId scanner;

  /// What the scanner's latest open scan asked for.
  final ScanAsk ask;

  @override
  final DateTime at;

  @override
  bool operator ==(Object other) =>
      other is ScannerStarted &&
      other.scanner == scanner &&
      other.ask == ask &&
      other.at == at;

  @override
  int get hashCode => Object.hash(ScannerStarted, scanner, ask, at);
}

/// Every scan of a scanner is on its way out and the radio is stopping for
/// them.
final class ScannerBeganStopping extends ScanEvent {
  const ScannerBeganStopping(this.scanner, this.at);

  final ScannerId scanner;

  @override
  final DateTime at;

  @override
  bool operator ==(Object other) =>
      other is ScannerBeganStopping &&
      other.scanner == scanner &&
      other.at == at;

  @override
  int get hashCode => Object.hash(ScannerBeganStopping, scanner, at);
}

/// A scanner has no scan left, and [end] is why its last one ended.
final class ScannerStopped extends ScanEvent {
  const ScannerStopped(this.scanner, this.end, this.at);

  final ScannerId scanner;
  final ScanEnd end;

  @override
  final DateTime at;

  @override
  bool operator ==(Object other) =>
      other is ScannerStopped &&
      other.scanner == scanner &&
      other.end == end &&
      other.at == at;

  @override
  int get hashCode => Object.hash(ScannerStopped, scanner, end, at);
}

/// One scan ended, for [end]: how its holder learns why, even when its
/// scanner's standing did not change.
final class ScanEnded extends ScanEvent {
  const ScanEnded(this.scan, this.end, this.at);

  final ScanId scan;
  final ScanEnd end;

  @override
  final DateTime at;

  @override
  bool operator ==(Object other) =>
      other is ScanEnded &&
      other.scan == scan &&
      other.end == end &&
      other.at == at;

  @override
  int get hashCode => Object.hash(ScanEnded, scan, end, at);
}

/// [result] reaches [scans], the ones the routing rules give it to.
final class ResultDelivered extends ScanEvent {
  ResultDelivered(this.result, Set<ScanId> scans, this.at)
    : scans = Set.unmodifiable(scans);

  final ScanResult result;
  final Set<ScanId> scans;

  @override
  final DateTime at;

  @override
  bool operator ==(Object other) =>
      other is ResultDelivered &&
      other.result == result &&
      other.scans.length == scans.length &&
      other.scans.containsAll(scans) &&
      other.at == at;

  @override
  int get hashCode =>
      Object.hash(ResultDelivered, result, Object.hashAllUnordered(scans), at);
}
