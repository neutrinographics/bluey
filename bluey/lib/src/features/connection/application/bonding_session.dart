import '../../../shared/application/log.dart';
import '../../../shared/domain/either.dart';
import '../domain/connection_failure.dart';
import '../domain/link_features.dart';
import '../domain/link_id.dart';
import '../domain/link_operation.dart';
import '../domain/value_objects/bond_state.dart';
import 'check_before_asking.dart';
import 'link_session.dart';
import 'ports/bonding.dart';
import 'reported_value.dart';

/// One link's bond state, as the radio last reported it, and the requests
/// that change it.
///
/// On a platform that cannot bond the port is never touched and the state
/// stays none. Requests log nothing: the bond they bring about arrives as a
/// report, not as their answer.
final class BondingSession {
  /// Follows the radio's reports and reads the state once, at once, unless
  /// the platform cannot bond.
  BondingSession({
    required LinkSession session,
    required Bonding bonding,
    required LinkFeatures features,
    required Log log,
  }) : _session = session,
       _bonding = bonding,
       _supported = features.canBond,
       _state =
           features.canBond
               ? ReportedValue(
                 session: session,
                 initial: BondState.none,
                 reports: bonding.changesOf(session.id),
                 readFirst: () => bonding.stateOf(session.id),
                 log: log,
                 failedReadLine: 'bond state read failed',
               )
               : ReportedValue.unreported(BondState.none);

  final LinkSession _session;
  final Bonding _bonding;
  final bool _supported;
  final ReportedValue<BondState> _state;

  /// The bond state the radio last reported: none until it says otherwise.
  ///
  /// It is still answered after a plain disconnect; after a radio outage the
  /// outage is answered instead.
  Either<ConnectionFailure, BondState> get state =>
      _check(LinkOperation.readBondState).map((_) => _state.value);

  /// The state as it is now, then every state the radio reports, to each
  /// listener; it ends when the link ends. Carries no errors.
  Either<ConnectionFailure, Stream<BondState>> get changes =>
      _check(LinkOperation.followBondState).map((_) => _state.follow());

  /// Asks the radio to bond with the link's device; the link's end when it
  /// is not up.
  Future<Either<ConnectionFailure, void>> bond() =>
      _request(LinkOperation.bond, _bonding.bond);

  /// Asks the radio to forget its bond with the link's device; the link's
  /// end when it is not up.
  Future<Either<ConnectionFailure, void>> removeBond() =>
      _request(LinkOperation.removeBond, _bonding.removeBond);

  Either<ConnectionFailure, void> _check(LinkOperation operation) =>
      checkBeforeAsking(
        _session.link,
        operation: operation,
        supported: _supported,
      );

  Future<Either<ConnectionFailure, void>> _request(
    LinkOperation operation,
    Future<Either<ConnectionFailure, void>> Function(LinkId link) call,
  ) => _check(operation).flatMapAsync(
    (_) => _session.whileUp(() => call(_session.id), orEnd: LinkHadEnded.new),
  );
}
