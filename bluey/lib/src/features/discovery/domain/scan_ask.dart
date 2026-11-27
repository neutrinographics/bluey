import 'package:meta/meta.dart';

import 'scan_filter.dart';
import 'scan_mode.dart';

/// What one scan asks of the radio.
@immutable
final class ScanAsk {
  const ScanAsk({required this.filter, this.mode, this.timeLimit});

  final ScanFilter filter;

  /// Absent when the app states no preference, so the radio's own choice
  /// stands and no scan is asked to restart for one that did not care.
  final ScanMode? mode;

  /// Carried only so events can name it; the aggregate never reads it,
  /// since the clock that ends a scan belongs to the application layer.
  final Duration? timeLimit;

  @override
  bool operator ==(Object other) =>
      other is ScanAsk &&
      other.filter == filter &&
      other.mode == mode &&
      other.timeLimit == timeLimit;

  @override
  int get hashCode => Object.hash(filter, mode, timeLimit);
}

/// What the radio must scan with so that every open scan is served.
///
/// A time limit belongs to one scan and does not widen what the radio does,
/// so it takes no part in coverage or in its equality.
@immutable
final class ScanCoverage {
  const ScanCoverage({required this.filter, this.mode});

  /// A [StateError] for no asks: coverage exists only while a scan is open.
  factory ScanCoverage.of(Iterable<ScanAsk> asks) {
    final iterator = asks.iterator;
    if (!iterator.moveNext()) {
      throw StateError('Coverage exists only while a scan is open.');
    }
    var coverage = ScanCoverage(
      filter: iterator.current.filter,
      mode: iterator.current.mode,
    );
    while (iterator.moveNext()) {
      coverage = coverage.widenedBy(iterator.current);
    }
    return coverage;
  }

  final ScanFilter filter;

  /// Null when no open scan stated one.
  final ScanMode? mode;

  /// Whether the radio, as it is, already serves [ask], so no restart is
  /// needed to start that scan.
  bool covers(ScanAsk ask) {
    if (!filter.covers(ask.filter)) return false;
    final wanted = ask.mode;
    if (wanted == null) return true;
    final current = mode;
    return current != null && _busyness(wanted) <= _busyness(current);
  }

  /// This coverage grown to serve [ask] as well; equal to this one when it
  /// already does.
  ScanCoverage widenedBy(ScanAsk ask) => ScanCoverage(
    filter: filter.union(ask.filter),
    mode: _busier(mode, ask.mode),
  );

  @override
  bool operator ==(Object other) =>
      other is ScanCoverage && other.filter == filter && other.mode == mode;

  @override
  int get hashCode => Object.hash(filter, mode);
}

/// The enum's declared order is not the rank, so the rank is stated here.
int _busyness(ScanMode mode) => switch (mode) {
  ScanMode.lowPower => 0,
  ScanMode.balanced => 1,
  ScanMode.lowLatency => 2,
};

ScanMode? _busier(ScanMode? a, ScanMode? b) {
  if (a == null) return b;
  if (b == null) return a;
  return _busyness(a) >= _busyness(b) ? a : b;
}
