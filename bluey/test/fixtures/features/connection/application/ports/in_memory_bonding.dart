import 'dart:async';

import 'package:bluey/src/features/connection/application/ports/bonding.dart';
import 'package:bluey/src/features/connection/domain/connection_failure.dart';
import 'package:bluey/src/features/connection/domain/link_id.dart';
import 'package:bluey/src/features/connection/domain/link_operation.dart';
import 'package:bluey/src/features/connection/domain/value_objects/bond_state.dart';
import 'package:bluey/src/shared/domain/either.dart';

import 'bonding_contract.dart';

/// A radio in memory that bonds links, so the bonding session can be tested
/// without a platform.
///
/// It is its own [BondingHarness], and adds what the session's tests need:
/// reads held back until told to answer, failures told by hand, reports told
/// per link, and what was asked of it.
class InMemoryBonding implements Bonding, BondingHarness {
  final Map<LinkId, BondState> _states = {};
  final Map<LinkId, StreamController<BondState>> _changes = {};
  final List<(LinkOperation, LinkId)> _asked = [];
  final Map<LinkOperation, ConnectionFailure> _nextFailures = {};
  Completer<void>? _heldReads;

  @override
  Bonding get bonding => this;

  @override
  LinkId get link => const LinkId('AA:BB:CC:DD:EE:01');

  /// Everything asked of the port, with its link, in order.
  List<(LinkOperation, LinkId)> get asked => List.unmodifiable(_asked);

  @override
  Future<Either<ConnectionFailure, BondState>> stateOf(LinkId link) async {
    _asked.add((LinkOperation.readBondState, link));
    final failure = _nextFailures.remove(LinkOperation.readBondState);
    final held = _heldReads;
    if (held != null) await held.future;
    if (failure != null) return Left(failure);
    return Right(_states[link] ?? BondState.none);
  }

  @override
  Stream<BondState> changesOf(LinkId link) {
    _asked.add((LinkOperation.followBondState, link));
    return _changesOn(link).stream;
  }

  @override
  Future<Either<ConnectionFailure, void>> bond(LinkId link) =>
      _request(LinkOperation.bond, link);

  @override
  Future<Either<ConnectionFailure, void>> removeBond(LinkId link) =>
      _request(LinkOperation.removeBond, link);

  /// A read of [link]'s bond state answers [state].
  void answer(LinkId link, BondState state) => _states[link] = state;

  /// The radio reports that [link]'s bond state is now [state].
  void report(LinkId link, BondState state) => _changesOn(link).add(state);

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
  void answerReads(BondState state) => answer(link, state);

  @override
  void radioReports(BondState state) => report(link, state);

  @override
  void timeOutNextRead() => failNext(
    LinkOperation.readBondState,
    const OperationTimedOut(LinkOperation.readBondState),
  );

  @override
  void rejectNextBond(int status) => failNext(
    LinkOperation.bond,
    OperationRejected(LinkOperation.bond, status),
  );

  Future<Either<ConnectionFailure, void>> _request(
    LinkOperation operation,
    LinkId link,
  ) async {
    _asked.add((operation, link));
    final failure = _nextFailures.remove(operation);
    if (failure != null) return Left(failure);
    return const Right(null);
  }

  StreamController<BondState> _changesOn(LinkId link) =>
      _changes.putIfAbsent(link, StreamController<BondState>.broadcast);
}
