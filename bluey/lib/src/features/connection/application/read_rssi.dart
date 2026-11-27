import '../../../shared/application/log.dart';
import '../../../shared/application/now.dart';
import '../../../shared/domain/either.dart';
import '../domain/connection_failure.dart';
import '../domain/link_operation.dart';
import 'link_operation_log.dart';
import 'link_session.dart';
import 'ports/signal_strength.dart';

/// Reads how well a link's peer is heard now. It leaves nothing behind, so
/// it is a unit of its own rather than part of a session.
final class ReadRssi {
  const ReadRssi({
    required SignalStrength strength,
    required Log log,
    required Now now,
  }) : _strength = strength,
       _log = log,
       _now = now;

  final SignalStrength _strength;
  final Log _log;
  final Now _now;

  /// The RSSI of [session]'s link in dBm; the link's end when it is not up.
  Future<Either<ConnectionFailure, int>> run(LinkSession session) =>
      loggedWhileUp(
        _log,
        now: _now,
        session: session,
        operation: LinkOperation.readSignalStrength,
        completeDetail: (rssi) => 'rssi=${rssi}dBm',
        run: () => _strength.read(session.id),
      );
}
