import '../../../shared/application/log.dart';
import '../../../shared/application/now.dart';
import '../../../shared/domain/either.dart';
import '../domain/connection_failure.dart';
import '../domain/link_features.dart';
import '../domain/link_operation.dart';
import '../domain/value_objects/mtu.dart';
import 'check_before_asking.dart';
import 'link_operation_log.dart';
import 'link_session.dart';
import 'ports/mtu_negotiation.dart';

/// One link's MTU: what the two sides last settled on, and the requests
/// that change it, which are one conversation with the peer.
///
/// The radio reports no MTU by itself, so the session asks nothing until a
/// request is made, and logs nothing either.
final class MtuSession {
  MtuSession({
    required LinkSession session,
    required MtuNegotiation negotiation,
    required LinkFeatures features,
    required Log log,
    required Now now,
  }) : _session = session,
       _negotiation = negotiation,
       _features = features,
       _log = log,
       _now = now;

  final LinkSession _session;
  final MtuNegotiation _negotiation;
  final LinkFeatures _features;
  final Log _log;
  final Now _now;
  Mtu _held = Mtu.minimum;

  /// What the two sides last settled on: 23 until a request answers, since
  /// the radio reports no MTU by itself.
  ///
  /// It is still answered after a plain disconnect; after a radio outage the
  /// outage is answered instead.
  Either<ConnectionFailure, Mtu> get mtu => _check().map((_) => _held);

  /// Asks the peer for [desired] and holds what the two sides settle on.
  ///
  /// A request this platform cannot make never reaches the radio, and a
  /// failed one leaves the MTU as it was.
  Future<Either<ConnectionFailure, Mtu>> request(Mtu desired) async {
    final answer = await _check()
        .flatMap((_) => _features.admit(desired))
        .flatMapAsync(_negotiate);
    if (answer case Right(:final value)) _held = value;
    return answer;
  }

  Either<ConnectionFailure, void> _check() =>
      checkBeforeAsking(_session.link, operation: LinkOperation.negotiateMtu);

  Future<Either<ConnectionFailure, Mtu>> _negotiate(Mtu desired) =>
      loggedWhileUp(
        _log,
        now: _now,
        session: _session,
        operation: LinkOperation.negotiateMtu,
        startDetail: 'requested=${desired.value}',
        completeDetail:
            (negotiated) =>
                'requested=${desired.value}, negotiated=${negotiated.value}',
        run: () => _negotiation.request(_session.link.id, desired),
      );
}
