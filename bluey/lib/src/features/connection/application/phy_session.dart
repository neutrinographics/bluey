import '../../../shared/application/log.dart';
import '../../../shared/domain/either.dart';
import '../domain/connection_failure.dart';
import '../domain/link_features.dart';
import '../domain/link_operation.dart';
import '../domain/value_objects/phy.dart';
import 'check_before_asking.dart';
import 'link_session.dart';
import 'ports/phy_control.dart';
import 'reported_value.dart';

/// One link's PHY pair, as the radio last reported it, and the request that
/// changes it.
///
/// On a platform that cannot set a PHY the port is never touched and the
/// pair stays LE 1M both ways. A request logs nothing and holds nothing: the
/// PHY it brings about arrives as a report, not as its answer.
final class PhySession {
  /// Follows the radio's reports and reads the pair once, at once, unless
  /// the platform cannot set a PHY.
  PhySession({
    required LinkSession session,
    required PhyControl phy,
    required LinkFeatures features,
    required Log log,
  }) : _session = session,
       _phy = phy,
       _supported = features.canRequestPhy,
       _pair =
           features.canRequestPhy
               ? ReportedValue(
                 session: session,
                 initial: _le1mBothWays,
                 reports: phy.changesOf(session.id),
                 readFirst: () => phy.pairOf(session.id),
                 log: log,
                 failedReadLine: 'phy read failed',
               )
               : ReportedValue.unreported(_le1mBothWays);

  static const PhyPair _le1mBothWays = (tx: Phy.le1m, rx: Phy.le1m);

  final LinkSession _session;
  final PhyControl _phy;
  final bool _supported;
  final ReportedValue<PhyPair> _pair;

  /// The PHY the link transmits on, as the radio last reported it.
  ///
  /// It is still answered after a plain disconnect; after a radio outage the
  /// outage is answered instead.
  Either<ConnectionFailure, Phy> get tx =>
      _check(LinkOperation.readTransmitPhy).map((_) => _pair.value.tx);

  /// The PHY the link receives on, as the radio last reported it, answered
  /// as [tx] is.
  Either<ConnectionFailure, Phy> get rx =>
      _check(LinkOperation.readReceivePhy).map((_) => _pair.value.rx);

  /// The pair as it is now, then every pair the radio reports, to each
  /// listener; it ends when the link ends. Carries no errors.
  Either<ConnectionFailure, Stream<PhyPair>> get changes =>
      _check(LinkOperation.followPhy).map((_) => _pair.follow());

  /// Asks the radio for a PHY in either direction, a direction left out
  /// keeping what it has; the link's end when it is not up.
  Future<Either<ConnectionFailure, void>> request({Phy? tx, Phy? rx}) =>
      _check(LinkOperation.requestPhy).flatMapAsync(
        (_) => _session.whileUp(
          () => _phy.request(_session.id, tx: tx, rx: rx),
          orEnd: LinkHadEnded.new,
        ),
      );

  Either<ConnectionFailure, void> _check(LinkOperation operation) =>
      checkBeforeAsking(
        _session.link,
        operation: operation,
        supported: _supported,
      );
}
