import 'package:bluey_platform_interface/bluey_platform_interface.dart';

import '../../../../shared/application/log.dart';
import '../../../../shared/application/log_level.dart';
import '../../../../shared/domain/either.dart';
import '../../application/connection_log_words.dart';
import '../../application/ports/phy_control.dart';
import '../../domain/connection_failure.dart';
import '../../domain/link_id.dart';
import '../../domain/link_operation.dart';
import '../../domain/value_objects/phy.dart';
import 'platform_failures.dart';

/// Connection's [PhyControl] over [BlueyPlatform].
///
/// A platform stream error is logged and passed over, never passed on: one
/// bad report must not end the reports that follow it, and the port
/// promises a stream with no errors.
final class PlatformPhyControl implements PhyControl {
  PlatformPhyControl(BlueyPlatform platform, {required Log log})
    : _platform = platform,
      _log = log;

  final BlueyPlatform _platform;
  final Log _log;

  @override
  Future<Either<ConnectionFailure, PhyPair>> pairOf(LinkId link) async =>
      (await answering(
        LinkOperation.readPhy,
        () => _platform.getPhy(link.value),
      )).map(_pairOf);

  @override
  Stream<PhyPair> changesOf(LinkId link) => _platform
      .phyStream(link.value)
      .handleError((Object error) => _logFailedReport(link, error))
      .map(_pairOf);

  @override
  Future<Either<ConnectionFailure, void>> request(
    LinkId link, {
    Phy? tx,
    Phy? rx,
  }) => answering(
    LinkOperation.requestPhy,
    () => _platform.requestPhy(
      link.value,
      tx == null ? null : _platformPhyOf(tx),
      rx == null ? null : _platformPhyOf(rx),
    ),
  );

  void _logFailedReport(LinkId link, Object error) => _log.log(
    BlueyLogLevel.warn,
    connectionLogContext,
    'phy reports failed',
    data: {'link': link.value},
    errorCode: failureCodeOf(
      connectionFailureFrom(error, operation: LinkOperation.followPhy),
    ),
  );
}

PhyPair _pairOf(({PlatformPhy tx, PlatformPhy rx}) pair) => (
  tx: _phyOf(pair.tx),
  rx: _phyOf(pair.rx),
);

Phy _phyOf(PlatformPhy phy) => switch (phy) {
  PlatformPhy.le1m => Phy.le1m,
  PlatformPhy.le2m => Phy.le2m,
  PlatformPhy.leCoded => Phy.leCoded,
};

PlatformPhy _platformPhyOf(Phy phy) => switch (phy) {
  Phy.le1m => PlatformPhy.le1m,
  Phy.le2m => PlatformPhy.le2m,
  Phy.leCoded => PlatformPhy.leCoded,
};
