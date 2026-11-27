import '../../../shared/application/log.dart';
import '../../../shared/application/now.dart';
import '../../../shared/domain/either.dart';
import '../domain/connection_failure.dart';
import '../domain/link_operation.dart';
import '../domain/value_objects/write_payload_limit.dart';
import 'link_operation_log.dart';
import 'link_session.dart';
import 'ports/mtu_negotiation.dart';

/// Reads the most one write on a link can carry. It leaves nothing behind,
/// so it is a unit of its own rather than part of a session.
final class ReadWritePayloadLimit {
  const ReadWritePayloadLimit({
    required MtuNegotiation negotiation,
    required Log log,
    required Now now,
  }) : _negotiation = negotiation,
       _log = log,
       _now = now;

  final MtuNegotiation _negotiation;
  final Log _log;
  final Now _now;

  /// The limit for writes with a response, or without one, on [session]'s
  /// link; the link's end when it is not up.
  Future<Either<ConnectionFailure, WritePayloadLimit>> run(
    LinkSession session, {
    required bool withResponse,
  }) => loggedWhileUp(
    _log,
    now: _now,
    session: session,
    operation: LinkOperation.readWritePayloadLimit,
    startDetail: 'withResponse=$withResponse',
    completeDetail:
        (limit) => 'withResponse=$withResponse, limit=${limit.value}',
    run:
        () => _negotiation.writePayloadLimit(
          session.id,
          withResponse: withResponse,
        ),
  );
}
