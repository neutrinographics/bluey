import 'package:bluey/src/features/connection/application/ports/signal_strength.dart';
import 'package:bluey/src/features/connection/domain/connection_failure.dart';
import 'package:bluey/src/features/connection/domain/link_id.dart';
import 'package:bluey/src/features/connection/domain/link_operation.dart';
import 'package:bluey/src/shared/domain/either.dart';

import 'signal_strength_contract.dart';

/// A peer in memory that is heard at a set strength, with time that
/// `fakeAsync` drives.
///
/// It is its own [SignalStrengthHarness], and adds what the units' tests
/// need: how long a read takes, failures told by hand, and what was read.
class InMemorySignalStrength implements SignalStrength, SignalStrengthHarness {
  @override
  int rssi = -60;

  /// How long each read takes.
  Duration delay = Duration.zero;

  final List<LinkId> _reads = [];
  ConnectionFailure? _nextFailure;

  @override
  SignalStrength get strength => this;

  @override
  LinkId get link => const LinkId('AA:BB:CC:DD:EE:01');

  /// Every link read, in order.
  List<LinkId> get reads => List.unmodifiable(_reads);

  @override
  Future<Either<ConnectionFailure, int>> read(LinkId link) async {
    _reads.add(link);
    final failure = _nextFailure;
    _nextFailure = null;
    await Future<void>.delayed(delay);
    if (failure != null) return Left(failure);
    return Right(rssi);
  }

  /// The next read answers [failure].
  void failNext(ConnectionFailure failure) => _nextFailure = failure;

  @override
  void rejectNext(int status) =>
      failNext(OperationRejected(LinkOperation.readSignalStrength, status));
}
