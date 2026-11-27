import 'dart:async';

import '../domain/scan_id.dart';
import '../domain/scan_phase.dart';
import '../domain/scan_result.dart';

/// The handle of one scan, so whoever opened it reads its results and its
/// end, and leaves it, without knowing the radio or the other scans.
///
/// It holds the scan's time limit: the radio is never handed a timeout, so
/// a scan's limit is kept here and makes the scan leave like any other end.
/// Where the scan stands is decided by the radio scan the session runs.
final class OpenScan {
  /// A handle on the scan [id], whose [results] and [ended] the session
  /// feeds, and which leaves through [leaveWith].
  OpenScan({
    required this.id,
    required Stream<ScanResult> results,
    required this.ended,
    required void Function(ScanEnd end) leaveWith,
    Duration? timeLimit,
  }) : _results = results,
       _leaveWith = leaveWith {
    if (timeLimit != null) {
      final timer = Timer(timeLimit, () => _leaveWith(const EndedByTimeout()));
      unawaited(ended.whenComplete(timer.cancel));
    }
  }

  final ScanId id;
  final Stream<ScanResult> _results;
  final void Function(ScanEnd end) _leaveWith;
  bool _left = false;

  /// What the scan receives, for one listener. Carries no errors: a scan
  /// that fails closes, and [ended] says why. Cancelling it leaves the scan.
  Stream<ScanResult> get results => _results;

  /// Why the scan ended, once it has.
  final Future<ScanEnd> ended;

  /// Leaves the scan on request; a second call asks nothing more.
  void leave() {
    if (_left) return;
    _left = true;
    _leaveWith(const EndedOnRequest());
  }
}
