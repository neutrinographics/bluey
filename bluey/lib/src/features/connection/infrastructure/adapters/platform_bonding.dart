import 'package:bluey_platform_interface/bluey_platform_interface.dart';

import '../../../../shared/application/log.dart';
import '../../../../shared/application/log_level.dart';
import '../../../../shared/domain/either.dart';
import '../../application/connection_log_words.dart';
import '../../application/ports/bonding.dart';
import '../../domain/connection_failure.dart';
import '../../domain/link_id.dart';
import '../../domain/link_operation.dart';
import '../../domain/value_objects/bond_state.dart';
import 'platform_failures.dart';

/// Connection's [Bonding] over [BlueyPlatform].
///
/// A platform stream error is logged and passed over, never passed on: one
/// bad report must not end the reports that follow it, and the port
/// promises a stream with no errors.
final class PlatformBonding implements Bonding {
  PlatformBonding(BlueyPlatform platform, {required Log log})
    : _platform = platform,
      _log = log;

  final BlueyPlatform _platform;
  final Log _log;

  @override
  Future<Either<ConnectionFailure, BondState>> stateOf(LinkId link) async =>
      (await answering(
        LinkOperation.readBondState,
        () => _platform.getBondState(link.value),
      )).map(_bondStateOf);

  @override
  Stream<BondState> changesOf(LinkId link) => _platform
      .bondStateStream(link.value)
      .handleError((Object error) => _logFailedReport(link, error))
      .map(_bondStateOf);

  @override
  Future<Either<ConnectionFailure, void>> bond(LinkId link) =>
      answering(LinkOperation.bond, () => _platform.bond(link.value));

  @override
  Future<Either<ConnectionFailure, void>> removeBond(LinkId link) => answering(
    LinkOperation.removeBond,
    () => _platform.removeBond(link.value),
  );

  void _logFailedReport(LinkId link, Object error) => _log.log(
    BlueyLogLevel.warn,
    connectionLogContext,
    'bond state reports failed',
    data: {'link': link.value},
    errorCode: failureCodeOf(
      connectionFailureFrom(error, operation: LinkOperation.followBondState),
    ),
  );
}

BondState _bondStateOf(PlatformBondState state) => switch (state) {
  PlatformBondState.none => BondState.none,
  PlatformBondState.bonding => BondState.bonding,
  PlatformBondState.bonded => BondState.bonded,
};
