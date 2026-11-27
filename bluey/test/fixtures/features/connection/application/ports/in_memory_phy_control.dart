import 'dart:async';

import 'package:bluey/src/features/connection/application/ports/phy_control.dart';
import 'package:bluey/src/features/connection/domain/connection_failure.dart';
import 'package:bluey/src/features/connection/domain/link_id.dart';
import 'package:bluey/src/features/connection/domain/link_operation.dart';
import 'package:bluey/src/features/connection/domain/value_objects/phy.dart';
import 'package:bluey/src/shared/domain/either.dart';

import 'phy_control_contract.dart';

/// A radio in memory that sets links' PHYs, so the PHY session can be tested
/// without a platform.
///
/// It is its own [PhyControlHarness], and adds what the session's tests
/// need: reads held back until told to answer, failures told by hand,
/// reports told per link, and what was asked of it.
class InMemoryPhyControl implements PhyControl, PhyControlHarness {
  final Map<LinkId, PhyPair> _pairs = {};
  final Map<LinkId, StreamController<PhyPair>> _changes = {};
  final List<(LinkOperation, LinkId)> _asked = [];
  final List<({Phy? tx, Phy? rx})> _requests = [];
  final Map<LinkOperation, ConnectionFailure> _nextFailures = {};
  Completer<void>? _heldReads;

  @override
  PhyControl get phy => this;

  @override
  LinkId get link => const LinkId('AA:BB:CC:DD:EE:01');

  /// Everything asked of the port, with its link, in order.
  List<(LinkOperation, LinkId)> get asked => List.unmodifiable(_asked);

  /// The directions every request asked for, in order.
  List<({Phy? tx, Phy? rx})> get requests => List.unmodifiable(_requests);

  @override
  Future<Either<ConnectionFailure, PhyPair>> pairOf(LinkId link) async {
    _asked.add((LinkOperation.readPhy, link));
    final failure = _nextFailures.remove(LinkOperation.readPhy);
    final held = _heldReads;
    if (held != null) await held.future;
    if (failure != null) return Left(failure);
    return Right(_pairs[link] ?? (tx: Phy.le1m, rx: Phy.le1m));
  }

  @override
  Stream<PhyPair> changesOf(LinkId link) {
    _asked.add((LinkOperation.followPhy, link));
    return _changesOn(link).stream;
  }

  @override
  Future<Either<ConnectionFailure, void>> request(
    LinkId link, {
    Phy? tx,
    Phy? rx,
  }) async {
    _asked.add((LinkOperation.requestPhy, link));
    _requests.add((tx: tx, rx: rx));
    final failure = _nextFailures.remove(LinkOperation.requestPhy);
    if (failure != null) return Left(failure);
    return const Right(null);
  }

  /// A read of [link]'s PHY pair answers [pair].
  void answer(LinkId link, PhyPair pair) => _pairs[link] = pair;

  /// The radio reports that [link]'s PHY pair is now [pair].
  void report(LinkId link, PhyPair pair) => _changesOn(link).add(pair);

  /// The next [operation] answers [failure].
  void failNext(LinkOperation operation, ConnectionFailure failure) =>
      _nextFailures[operation] = failure;

  /// Reads wait until [answerHeldReads], so a test can let a report or the
  /// link's end come first.
  void holdReads() => _heldReads = Completer<void>();

  /// Lets every held read answer.
  void answerHeldReads() {
    _heldReads?.complete();
    _heldReads = null;
  }

  @override
  void answerReads(PhyPair pair) => answer(link, pair);

  @override
  void radioReports(PhyPair pair) => report(link, pair);

  @override
  void timeOutNextRead() => failNext(
    LinkOperation.readPhy,
    const OperationTimedOut(LinkOperation.readPhy),
  );

  @override
  void rejectNextRequest(int status) => failNext(
    LinkOperation.requestPhy,
    OperationRejected(LinkOperation.requestPhy, status),
  );

  StreamController<PhyPair> _changesOn(LinkId link) =>
      _changes.putIfAbsent(link, StreamController<PhyPair>.broadcast);
}
