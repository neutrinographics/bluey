import '../../../../shared/domain/either.dart';
import '../../domain/connection_failure.dart';
import '../../domain/link_id.dart';

/// How Connection reads how well a link is heard, so the reading runs over a
/// double and over the platform alike.
abstract interface class SignalStrength {
  /// The link's RSSI in dBm, read now.
  Future<Either<ConnectionFailure, int>> read(LinkId link);
}
