import 'package:meta/meta.dart';

/// Names one scan, so its events and its end are told apart from those of
/// another scan open on the same radio.
@immutable
final class ScanId {
  const ScanId(this.value);

  /// Minted in order by whoever opens scans; opaque to everything but
  /// equality.
  final int value;

  @override
  bool operator ==(Object other) => other is ScanId && other.value == value;

  @override
  int get hashCode => Object.hash(ScanId, value);
}

/// Names one scanner, the app's handle on scanning, so the scans it opened
/// can be found and closed with it.
@immutable
final class ScannerId {
  const ScannerId(this.value);

  /// Minted in order by whoever hands out scanners; opaque to everything but
  /// equality.
  final int value;

  @override
  bool operator ==(Object other) => other is ScannerId && other.value == value;

  @override
  int get hashCode => Object.hash(ScannerId, value);
}
