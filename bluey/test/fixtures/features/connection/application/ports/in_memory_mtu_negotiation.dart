import 'package:bluey/src/features/connection/application/ports/mtu_negotiation.dart';
import 'package:bluey/src/features/connection/domain/connection_failure.dart';
import 'package:bluey/src/features/connection/domain/link_id.dart';
import 'package:bluey/src/features/connection/domain/link_operation.dart';
import 'package:bluey/src/features/connection/domain/value_objects/mtu.dart';
import 'package:bluey/src/features/connection/domain/value_objects/write_payload_limit.dart';
import 'package:bluey/src/shared/domain/either.dart';

import 'mtu_negotiation_contract.dart';

/// A peer in memory that agrees an MTU, with time that `fakeAsync` drives.
///
/// It is its own [MtuNegotiationHarness], and adds what the units' tests
/// need: how long an answer takes, failures told by hand, and what was asked
/// of it.
class InMemoryMtuNegotiation implements MtuNegotiation, MtuNegotiationHarness {
  /// The most the peer settles on; null settles on whatever is asked for.
  int? peerSettlesAt;

  /// How long each answer takes.
  Duration delay = Duration.zero;

  /// What one write with a response carries.
  int withResponseLimit = 20;

  /// What one write without a response carries.
  int withoutResponseLimit = 20;

  final List<(LinkId, Mtu)> _requests = [];
  final List<(LinkId, bool)> _limitReads = [];
  ConnectionFailure? _nextRequestFailure;
  ConnectionFailure? _nextLimitFailure;

  @override
  MtuNegotiation get negotiation => this;

  @override
  LinkId get link => const LinkId('AA:BB:CC:DD:EE:01');

  /// Every request asked, with its link, in order.
  List<(LinkId, Mtu)> get requests => List.unmodifiable(_requests);

  /// Every payload limit read, with its link and whether it was for writes
  /// with a response, in order.
  List<(LinkId, bool)> get limitReads => List.unmodifiable(_limitReads);

  @override
  Future<Either<ConnectionFailure, Mtu>> request(
    LinkId link,
    Mtu desired,
  ) async {
    _requests.add((link, desired));
    final failure = _nextRequestFailure;
    _nextRequestFailure = null;
    await Future<void>.delayed(delay);
    if (failure != null) return Left(failure);
    final cap = peerSettlesAt;
    return Right(
      Mtu.fromPlatform(
        cap != null && cap < desired.value ? cap : desired.value,
      ),
    );
  }

  @override
  Future<Either<ConnectionFailure, WritePayloadLimit>> writePayloadLimit(
    LinkId link, {
    required bool withResponse,
  }) async {
    _limitReads.add((link, withResponse));
    final failure = _nextLimitFailure;
    _nextLimitFailure = null;
    await Future<void>.delayed(delay);
    if (failure != null) return Left(failure);
    return Right(
      WritePayloadLimit.fromPlatform(
        withResponse ? withResponseLimit : withoutResponseLimit,
      ),
    );
  }

  /// The next request answers [failure].
  void failNextRequest(ConnectionFailure failure) =>
      _nextRequestFailure = failure;

  /// The next payload limit read answers [failure].
  void failNextLimitRead(ConnectionFailure failure) =>
      _nextLimitFailure = failure;

  @override
  void settleAt(int mtu) => peerSettlesAt = mtu;

  @override
  void rejectNext(int status) =>
      failNextRequest(OperationRejected(LinkOperation.negotiateMtu, status));

  @override
  void timeOutNext() =>
      failNextRequest(const OperationTimedOut(LinkOperation.negotiateMtu));

  @override
  void rejectNextLimitRead(int status) => failNextLimitRead(
    OperationRejected(LinkOperation.readWritePayloadLimit, status),
  );

  @override
  void limitWrites({required int withResponse, required int withoutResponse}) {
    withResponseLimit = withResponse;
    withoutResponseLimit = withoutResponse;
  }
}
