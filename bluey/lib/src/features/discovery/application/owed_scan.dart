import 'dart:async';

import '../domain/scan_id.dart';
import '../domain/scan_phase.dart';
import '../domain/scan_result.dart';

/// One scan the session still owes an end, kept apart from its handle so
/// only the session can feed its results and end it.
final class OwedScan {
  /// A scan of [scanner] whose results, cancelled by their listener, call
  /// [onCancel].
  OwedScan(this.scanner, void Function() onCancel)
    : results = StreamController<ScanResult>(onCancel: onCancel);

  final ScannerId scanner;
  final StreamController<ScanResult> results;
  final Completer<ScanEnd> ended = Completer<ScanEnd>();

  /// Closes the results and tells why the scan ended.
  void end(ScanEnd end) {
    unawaited(results.close());
    ended.complete(end);
  }
}
