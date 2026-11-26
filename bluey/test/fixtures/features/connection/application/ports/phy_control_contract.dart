import 'package:bluey/src/features/connection/application/ports/phy_control.dart';
import 'package:bluey/src/features/connection/domain/connection_failure.dart';
import 'package:bluey/src/features/connection/domain/link_id.dart';
import 'package:bluey/src/features/connection/domain/link_operation.dart';
import 'package:bluey/src/features/connection/domain/value_objects/phy.dart';
import 'package:bluey/src/shared/domain/either.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a run of [phyControlContract] needs from the [PhyControl] it holds
/// to account: a link that is up, and the ways to make its radio answer each
/// way the contract describes.
abstract class PhyControlHarness {
  /// The port under contract.
  PhyControl get phy;

  /// A link that is up.
  LinkId get link;

  /// A read of the link's PHY pair answers [pair].
  void answerReads(PhyPair pair);

  /// The radio reports that the link's PHY pair is now [pair].
  void radioReports(PhyPair pair);

  /// The next read of the PHY pair is not answered in time.
  void timeOutNextRead();

  /// The next request is rejected with [status].
  void rejectNextRequest(int status);
}

/// The promises every [PhyControl] keeps, so a unit tested over the double
/// behaves the same over the platform.
void phyControlContract(
  String name,
  Future<PhyControlHarness> Function() create,
) {
  group(name, () {
    late PhyControlHarness h;

    setUp(() async => h = await create());

    test('answers the pair', () async {
      // arrange
      h.answerReads((tx: Phy.le2m, rx: Phy.leCoded));

      // act
      final answer = await h.phy.pairOf(h.link);

      // assert
      expect(
        answer,
        const Right<ConnectionFailure, PhyPair>((
          tx: Phy.le2m,
          rx: Phy.leCoded,
        )),
      );
    });

    test('reports each change in order', () async {
      // arrange
      final seen = <PhyPair>[];
      h.phy.changesOf(h.link).listen(seen.add);

      // act
      h.radioReports((tx: Phy.le2m, rx: Phy.le2m));
      h.radioReports((tx: Phy.leCoded, rx: Phy.le1m));
      h.radioReports((tx: Phy.le1m, rx: Phy.le1m));
      await pumpEventQueue();

      // assert
      expect(seen, [
        (tx: Phy.le2m, rx: Phy.le2m),
        (tx: Phy.leCoded, rx: Phy.le1m),
        (tx: Phy.le1m, rx: Phy.le1m),
      ]);
    });

    test('a failed read answers the failure', () async {
      // arrange
      h.timeOutNextRead();

      // act
      final answer = await h.phy.pairOf(h.link);

      // assert
      expect(
        answer,
        const Left<ConnectionFailure, PhyPair>(
          OperationTimedOut(LinkOperation.readPhy),
        ),
      );
    });

    test('a request answers success', () async {
      // act
      final answer = await h.phy.request(h.link, tx: Phy.le2m, rx: Phy.le2m);

      // assert
      expect(answer, const Right<ConnectionFailure, void>(null));
    });

    test('a rejected request answers OperationRejected with its '
        'status', () async {
      // arrange
      h.rejectNextRequest(137);

      // act
      final answer = await h.phy.request(h.link, tx: Phy.leCoded);

      // assert
      expect(
        answer,
        const Left<ConnectionFailure, void>(
          OperationRejected(LinkOperation.requestPhy, 137),
        ),
      );
    });
  });
}
