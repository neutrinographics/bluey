import 'package:bluey/src/features/connection/application/ports/signal_strength.dart';
import 'package:bluey/src/features/connection/domain/connection_failure.dart';
import 'package:bluey/src/features/connection/domain/link_id.dart';
import 'package:bluey/src/features/connection/domain/link_operation.dart';
import 'package:bluey/src/shared/domain/either.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a run of [signalStrengthContract] needs from the [SignalStrength] it
/// holds to account: a link that is up, what its peer is heard at, and a way
/// to make a read fail.
abstract class SignalStrengthHarness {
  /// The port under contract.
  SignalStrength get strength;

  /// A link that is up.
  LinkId get link;

  /// The RSSI the link's peer is heard at, in dBm.
  int get rssi;

  /// The next read is rejected with [status].
  void rejectNext(int status);
}

/// The promises every [SignalStrength] keeps, so a unit tested over the
/// double behaves the same over the platform.
void signalStrengthContract(
  String name,
  Future<SignalStrengthHarness> Function() create,
) {
  group(name, () {
    late SignalStrengthHarness h;

    setUp(() async => h = await create());

    test('answers the RSSI', () async {
      // act
      final answer = await h.strength.read(h.link);

      // assert
      expect(answer, Right<ConnectionFailure, int>(h.rssi));
    });

    test('a failed read answers the failure', () async {
      // arrange
      h.rejectNext(8);

      // act
      final answer = await h.strength.read(h.link);

      // assert
      expect(
        answer,
        const Left<ConnectionFailure, int>(
          OperationRejected(LinkOperation.readSignalStrength, 8),
        ),
      );
    });
  });
}
