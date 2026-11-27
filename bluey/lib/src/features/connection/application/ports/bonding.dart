import '../../../../shared/domain/either.dart';
import '../../domain/connection_failure.dart';
import '../../domain/link_id.dart';
import '../../domain/value_objects/bond_state.dart';

/// How Connection reads, follows and changes the bond of one link's device,
/// so the bonding session runs over a double and over the platform alike.
abstract interface class Bonding {
  /// The link's bond state as the radio holds it now.
  Future<Either<ConnectionFailure, BondState>> stateOf(LinkId link);

  /// Every bond state the radio reports for the link, to one listener.
  /// Carries no errors.
  Stream<BondState> changesOf(LinkId link);

  /// Asks the radio to bond with the link's device. It answers once the
  /// request is taken; the bond itself arrives as a report.
  Future<Either<ConnectionFailure, void>> bond(LinkId link);

  /// Asks the radio to forget its bond with the link's device.
  Future<Either<ConnectionFailure, void>> removeBond(LinkId link);
}
