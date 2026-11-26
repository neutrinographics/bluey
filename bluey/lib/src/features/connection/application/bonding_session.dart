import 'dart:async';

import '../../../shared/application/log.dart';
import '../../../shared/application/log_level.dart';
import '../../../shared/domain/either.dart';
import '../domain/connection_failure.dart';
import '../domain/link_end.dart';
import '../domain/link_features.dart';
import '../domain/link_id.dart';
import '../domain/link_operation.dart';
import '../domain/value_objects/bond_state.dart';
import 'connection_log_words.dart';
import 'link_feature_check.dart';
import 'link_session.dart';
import 'ports/bonding.dart';

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
       _log = log {
    if (!_supported) return;
    _reports = bonding.changesOf(session.link.id).listen(_take);
    unawaited(_readFirst());
    session.onEnd(_release);
  }

  final LinkSession _session;
  final Bonding _bonding;
  final bool _supported;
  final Log _log;
  final StreamController<BondState> _changes =
      StreamController<BondState>.broadcast();
  StreamSubscription<BondState>? _reports;
  BondState _held = BondState.none;
  bool _reported = false;

  /// The bond state the radio last reported: none until it says otherwise.
  ///
  /// It is still answered after a plain disconnect; after a radio outage the
  /// outage is answered instead.
  Either<ConnectionFailure, BondState> get state =>
      _check(LinkOperation.readBondState).map((_) => _held);

  /// The state as it is now, then every state the radio reports, to each
  /// listener; it ends when the link ends. Carries no errors.
  Either<ConnectionFailure, Stream<BondState>> get changes =>
      _check(LinkOperation.followBondState).map((_) => _following());

  /// Asks the radio to bond with the link's device; the link's end when it
  /// is not up.
  Future<Either<ConnectionFailure, void>> bond() =>
      _request(LinkOperation.bond, _bonding.bond);

  /// Asks the radio to forget its bond with the link's device; the link's
  /// end when it is not up.
  Future<Either<ConnectionFailure, void>> removeBond() =>
      _request(LinkOperation.removeBond, _bonding.removeBond);

  Either<ConnectionFailure, void> _check(LinkOperation operation) =>
      checkLinkFeature(
        _session.link,
        operation: operation,
        supported: _supported,
      );

  Future<Either<ConnectionFailure, void>> _request(
    LinkOperation operation,
    Future<Either<ConnectionFailure, void>> Function(LinkId link) call,
  ) => _check(operation).flatMapAsync(
    (_) =>
        _session.whileUp(() => call(_session.link.id), orEnd: LinkHadEnded.new),
  );

  Stream<BondState> _following() => Stream.multi((listener) {
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

  void _take(BondState reported) {
    _reported = true;
    _held = reported;
    _changes.add(reported);
  }

  /// A report or the link's end outranks the first read, which may answer
  /// after either; a failed one leaves the default and is only logged, since
  /// nobody asked for it and so nobody could catch it.
  Future<void> _readFirst() async {
    final answer = await _bonding.stateOf(_session.link.id);
    answer.fold(
      (failure) => _log.log(
        BlueyLogLevel.warn,
        connectionLogContext,
        'bond state read failed',
        data: {
          'deviceId': '${_session.link.device}',
          'exception': failureCodeOf(failure),
        },
      ),
      (state) {
        if (!_reported && !_session.link.hasEnded) _held = state;
      },
    );
  }

  void _release(LinkEnd end) {
    unawaited(_reports?.cancel());
    _reports = null;
    unawaited(_changes.close());
  }
}
