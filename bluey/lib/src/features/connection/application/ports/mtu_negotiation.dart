import '../../../../shared/domain/either.dart';
import '../../domain/connection_failure.dart';
import '../../domain/link_id.dart';
import '../../domain/value_objects/mtu.dart';
import '../../domain/value_objects/write_payload_limit.dart';

/// How Connection agrees with a peer on the size of what one link carries,
/// so the MTU session and the payload reading run over a double and over the
/// platform alike.
abstract interface class MtuNegotiation {
  /// Asks the peer for [desired] and answers what the two sides settled on,
  /// which may be lower.
  Future<Either<ConnectionFailure, Mtu>> request(LinkId link, Mtu desired);

  /// The most one write on the link can carry.
  Future<Either<ConnectionFailure, WritePayloadLimit>> writePayloadLimit(
    LinkId link, {
    required bool withResponse,
  });
}
