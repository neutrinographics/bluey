import 'dart:async';

import '../../../shared/application/log.dart';
import '../../../shared/application/log_level.dart';
import '../../../shared/domain/either.dart';
import '../domain/connection_failure.dart';
import '../domain/link_end.dart';
import '../domain/link_features.dart';
import '../domain/link_operation.dart';
import '../domain/value_objects/phy.dart';
import 'connection_log_words.dart';
import 'link_feature_check.dart';
import 'link_session.dart';
import 'ports/phy_control.dart';

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
       _log = log {
    if (!_supported) return;
    _reports = phy.changesOf(session.link.id).listen(_take);
    unawaited(_readFirst());
    session.onEnd(_release);
  }

  final LinkSession _session;
  final PhyControl _phy;
  final bool _supported;
  final Log _log;
  final StreamController<PhyPair> _changes =
      StreamController<PhyPair>.broadcast();
  StreamSubscription<PhyPair>? _reports;
  PhyPair _held = (tx: Phy.le1m, rx: Phy.le1m);
  bool _reported = false;

  /// The PHY the link transmits on, as the radio last reported it.
  ///
  /// It is still answered after a plain disconnect; after a radio outage the
  /// outage is answered instead.
  Either<ConnectionFailure, Phy> get tx =>
      _check(LinkOperation.readTransmitPhy).map((_) => _held.tx);

  /// The PHY the link receives on, as the radio last reported it, answered
  /// as [tx] is.
  Either<ConnectionFailure, Phy> get rx =>
      _check(LinkOperation.readReceivePhy).map((_) => _held.rx);

  /// The pair as it is now, then every pair the radio reports, to each
  /// listener; it ends when the link ends. Carries no errors.
  Either<ConnectionFailure, Stream<PhyPair>> get changes =>
      _check(LinkOperation.followPhy).map((_) => _following());

  /// Asks the radio for a PHY in either direction, a direction left out
  /// keeping what it has; the link's end when it is not up.
  Future<Either<ConnectionFailure, void>> request({Phy? tx, Phy? rx}) =>
      _check(LinkOperation.requestPhy).flatMapAsync(
        (_) => _session.whileUp(
          () => _phy.request(_session.link.id, tx: tx, rx: rx),
          orEnd: LinkHadEnded.new,
        ),
      );

  Either<ConnectionFailure, void> _check(LinkOperation operation) =>
      checkLinkFeature(
        _session.link,
        operation: operation,
        supported: _supported,
      );

  Stream<PhyPair> _following() => Stream.multi((listener) {
    listener.add(_held);
    if (_changes.isClosed) {
      unawaited(listener.close());
      return;
    }
    final followed = _changes.stream.listen(
      listener.add,
      onDone: listener.close,
    );
    listener.onCancel = followed.cancel;
  });

  void _take(PhyPair reported) {
    _reported = true;
    _held = reported;
    _changes.add(reported);
  }

  /// A report or the link's end outranks the first read, which may answer
  /// after either; a failed one leaves the default and is only logged, since
  /// nobody asked for it and so nobody could catch it.
  Future<void> _readFirst() async {
    final answer = await _phy.pairOf(_session.link.id);
    answer.fold(
      (failure) => _log.log(
        BlueyLogLevel.warn,
        connectionLogContext,
        'phy read failed',
        data: {
          'deviceId': '${_session.link.device}',
          'exception': failureCodeOf(failure),
        },
      ),
      (pair) {
        if (!_reported && !_session.link.hasEnded) _held = pair;
      },
    );
  }

  void _release(LinkEnd end) {
    unawaited(_reports?.cancel());
    _reports = null;
    unawaited(_changes.close());
  }
}
