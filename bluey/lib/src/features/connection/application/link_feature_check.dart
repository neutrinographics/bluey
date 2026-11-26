import '../../../shared/domain/either.dart';
import '../domain/connection_failure.dart';
import '../domain/link.dart';
import '../domain/link_end.dart';
import '../domain/link_operation.dart';

/// Why [operation] cannot be asked of [link] before the radio is involved,
/// in the order an app has always seen: the end a radio outage brought,
/// then a feature this platform lacks.
///
/// Any other end is left to the operation: a value read after a plain
/// disconnect is still answered, as it always has been.
Either<ConnectionFailure, void> checkLinkFeature(
  Link link, {
  required LinkOperation operation,
  bool supported = true,
}) {
  if (link.end case final EndedByRadioOutage outage) {
    return Left(LinkHadEnded(outage));
  }
  if (!supported) return Left(FeatureUnsupported(operation));
  return const Right(null);
}
