import '../../../../shared/domain/either.dart';
import '../../domain/connection_failure.dart';
import '../../domain/link_id.dart';
import '../../domain/value_objects/phy.dart';

/// How Connection reads, follows and asks for the PHY of one link, so the
/// PHY session runs over a double and over the platform alike.
abstract interface class PhyControl {
  /// The link's PHY in each direction as the radio holds it now.
  Future<Either<ConnectionFailure, PhyPair>> pairOf(LinkId link);

  /// Every PHY pair the radio reports for the link, to one listener.
  /// Carries no errors.
  Stream<PhyPair> changesOf(LinkId link);

  /// Asks for a PHY in either direction; a direction left out keeps what it
  /// has. It answers once the request is taken; the PHY itself arrives as a
  /// report.
  Future<Either<ConnectionFailure, void>> request(
    LinkId link, {
    Phy? tx,
    Phy? rx,
  });
}
