import 'package:meta/meta.dart';

import '../../../shared/domain/either.dart';
import 'connection_failure.dart';
import 'link_operation.dart';
import 'value_objects/mtu.dart';

/// What links can do on this platform.
///
/// It never changes while the app runs, so it is handed in at construction
/// and never asked for.
@immutable
final class LinkFeatures {
  const LinkFeatures({
    required this.canBond,
    required this.canRequestPhy,
    required this.canRequestParameters,
    required this.canRequestMtu,
    required this.maxMtu,
  });

  /// Whether a link can be bonded, and its bond state read and followed.
  final bool canBond;

  /// Whether a link's PHY can be read, followed and asked for.
  final bool canRequestPhy;

  /// Whether a link's connection parameters can be read and asked for.
  final bool canRequestParameters;

  /// Whether a link can be asked for a larger MTU; where it cannot, the
  /// platform negotiates the MTU by itself.
  final bool canRequestMtu;

  /// The largest MTU this platform will ask a link for.
  final int maxMtu;

  /// [desired] if this platform can ask for it, or why it cannot, so a
  /// request beyond the platform's limits never reaches the radio.
  Either<ConnectionFailure, Mtu> admit(Mtu desired) {
    if (!canRequestMtu) {
      return const Left(FeatureUnsupported(LinkOperation.negotiateMtu));
    }
    if (desired.value > maxMtu) {
      return Left(MtuAboveMaximum(requested: desired, maximum: maxMtu));
    }
    return Right(desired);
  }

  @override
  bool operator ==(Object other) =>
      other is LinkFeatures &&
      other.canBond == canBond &&
      other.canRequestPhy == canRequestPhy &&
      other.canRequestParameters == canRequestParameters &&
      other.canRequestMtu == canRequestMtu &&
      other.maxMtu == maxMtu;

  @override
  int get hashCode => Object.hash(
    LinkFeatures,
    canBond,
    canRequestPhy,
    canRequestParameters,
    canRequestMtu,
    maxMtu,
  );
}
