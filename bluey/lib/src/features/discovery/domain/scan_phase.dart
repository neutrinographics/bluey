import 'package:meta/meta.dart';

import '../../../shared/domain/radio_outage.dart';
import 'scan_failure.dart';

/// Why a scan ended, so an app can tell a scan it stopped, or that ran its
/// time out, from one that failed or lost the radio.
@immutable
sealed class ScanEnd {
  const ScanEnd();
}

/// The app asked for the scan to stop.
final class EndedOnRequest extends ScanEnd {
  const EndedOnRequest();

  @override
  bool operator ==(Object other) => other is EndedOnRequest;

  @override
  int get hashCode => (EndedOnRequest).hashCode;
}

/// The scan's time limit ran out.
final class EndedByTimeout extends ScanEnd {
  const EndedByTimeout();

  @override
  bool operator ==(Object other) => other is EndedByTimeout;

  @override
  int get hashCode => (EndedByTimeout).hashCode;
}

/// The platform failed the scan, or refused to start it.
final class EndedByFailure extends ScanEnd {
  const EndedByFailure(this.failure);

  final ScanFailure failure;

  @override
  bool operator ==(Object other) =>
      other is EndedByFailure && other.failure == failure;

  @override
  int get hashCode => Object.hash(EndedByFailure, failure);
}

/// The radio became unusable, which ends every scan at once.
final class EndedByRadioOutage extends ScanEnd {
  const EndedByRadioOutage(this.outage);

  final RadioOutage outage;

  @override
  bool operator ==(Object other) =>
      other is EndedByRadioOutage && other.outage == outage;

  @override
  int get hashCode => Object.hash(EndedByRadioOutage, outage);
}

/// Where one scan stands, in Discovery's own words; the edge translates it
/// for apps.
@immutable
sealed class ScanPhase {
  const ScanPhase();
}

/// The scan is asked for but the radio is not scanning for it yet.
final class Waiting extends ScanPhase {
  const Waiting();

  @override
  bool operator ==(Object other) => other is Waiting;

  @override
  int get hashCode => (Waiting).hashCode;
}

/// The radio is scanning and the scan receives what it shows.
final class Served extends ScanPhase {
  const Served();

  @override
  bool operator ==(Object other) => other is Served;

  @override
  int get hashCode => (Served).hashCode;
}

/// The scan has been told to end and the radio has not yet confirmed it;
/// it carries why, so the end it reaches is the one it was given.
final class Leaving extends ScanPhase {
  const Leaving(this.end);

  final ScanEnd end;

  @override
  bool operator ==(Object other) => other is Leaving && other.end == end;

  @override
  int get hashCode => Object.hash(Leaving, end);
}

/// The scan is over, for the reason it carries; final.
final class Ended extends ScanPhase {
  const Ended(this.end);

  final ScanEnd end;

  @override
  bool operator ==(Object other) => other is Ended && other.end == end;

  @override
  int get hashCode => Object.hash(Ended, end);
}
