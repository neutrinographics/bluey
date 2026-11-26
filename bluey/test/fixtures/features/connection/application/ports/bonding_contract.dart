import 'package:bluey/src/features/connection/application/ports/bonding.dart';
import 'package:bluey/src/features/connection/domain/connection_failure.dart';
import 'package:bluey/src/features/connection/domain/link_id.dart';
import 'package:bluey/src/features/connection/domain/link_operation.dart';
import 'package:bluey/src/features/connection/domain/value_objects/bond_state.dart';
import 'package:bluey/src/shared/domain/either.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a run of [bondingContract] needs from the [Bonding] it holds to
/// account: a link that is up, and the ways to make its radio answer each
/// way the contract describes.
abstract class BondingHarness {
  /// The port under contract.
  Bonding get bonding;

  /// A link that is up.
  LinkId get link;

  /// A read of the link's bond state answers [state].
  void answerReads(BondState state);

  /// The radio reports that the link's bond state is now [state].
  void radioReports(BondState state);

  /// The next read of the bond state is not answered in time.
  void timeOutNextRead();

  /// The next bond is rejected with [status].
  void rejectNextBond(int status);
}

/// The promises every [Bonding] keeps, so a unit tested over the double
/// behaves the same over the platform.
void bondingContract(String name, Future<BondingHarness> Function() create) {
  group(name, () {
    late BondingHarness h;

    setUp(() async => h = await create());

    test('answers the bond state', () async {
      // arrange
      h.answerReads(BondState.bonded);

      // act
      final answer = await h.bonding.stateOf(h.link);

      // assert
      expect(
        answer,
        const Right<ConnectionFailure, BondState>(BondState.bonded),
      );
    });

    test('reports each change in order', () async {
      // arrange
      final seen = <BondState>[];
      h.bonding.changesOf(h.link).listen(seen.add);

      // act
      h.radioReports(BondState.bonding);
      h.radioReports(BondState.bonded);
      h.radioReports(BondState.none);
      await pumpEventQueue();

      // assert
      expect(seen, [BondState.bonding, BondState.bonded, BondState.none]);
    });

    test('a failed read answers the failure', () async {
      // arrange
      h.timeOutNextRead();

      // act
      final answer = await h.bonding.stateOf(h.link);

      // assert
      expect(
        answer,
        const Left<ConnectionFailure, BondState>(
          OperationTimedOut(LinkOperation.readBondState),
        ),
      );
    });

    test('bond and removeBond answer success', () async {
      // act
      final bonded = await h.bonding.bond(h.link);
      final removed = await h.bonding.removeBond(h.link);

      // assert
      expect(
        [bonded, removed],
        const [
          Right<ConnectionFailure, void>(null),
          Right<ConnectionFailure, void>(null),
        ],
      );
    });

    test('a rejected bond answers OperationRejected with its status', () async {
      // arrange
      h.rejectNextBond(137);

      // act
      final answer = await h.bonding.bond(h.link);

      // assert
      expect(
        answer,
        const Left<ConnectionFailure, void>(
          OperationRejected(LinkOperation.bond, 137),
        ),
      );
    });
  });
}
