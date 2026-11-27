import 'package:bluey/src/features/connection/application/bonding_session.dart';
import 'package:bluey/src/features/connection/application/link_session.dart';
import 'package:bluey/src/features/connection/domain/connection_failure.dart';
import 'package:bluey/src/features/connection/domain/link_end.dart';
import 'package:bluey/src/features/connection/domain/link_features.dart';
import 'package:bluey/src/features/connection/domain/link_operation.dart';
import 'package:bluey/src/features/connection/domain/value_objects/bond_state.dart';
import 'package:bluey/src/shared/application/log_level.dart';
import 'package:bluey/src/shared/domain/device_address.dart';
import 'package:bluey/src/shared/domain/either.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../fixtures/features/connection/application/ports/in_memory_bonding.dart';
import '../../../fixtures/features/connection/application/ports/in_memory_connection_ports.dart';
import '../../../fixtures/features/connection/application/ports/in_memory_links.dart';
import '../../../fixtures/features/connection/application/up_session.dart';
import '../../../fixtures/shared/application/recording_log.dart';

const device = DeviceAddress('AA:BB:CC:DD:EE:01');

const noBonding = LinkFeatures(
  canBond: false,
  canRequestPhy: true,
  canRequestParameters: true,
  canRequestMtu: true,
  maxMtu: 517,
);

Stream<BondState> rightOf(Either<ConnectionFailure, Stream<BondState>> it) =>
    it.fold((failure) => fail('the changes failed: $failure'), (s) => s);

void main() {
  late InMemoryLinks links;
  late InMemoryBonding port;
  late RecordingLog log;
  late LinkSession session;

  BondingSession bondingOver({LinkFeatures features = unlimitedLinkFeatures}) =>
      BondingSession(
        session: session,
        bonding: port,
        features: features,
        log: log,
      );

  setUp(() async {
    links = InMemoryLinks();
    port = InMemoryBonding();
    log = RecordingLog();
    session = await upSession(links, device);
  });

  test('holds none until the radio says otherwise', () {
    // act
    final bonding = bondingOver();

    // assert
    expect(
      bonding.state,
      const Right<ConnectionFailure, BondState>(BondState.none),
    );
  });

  test('the first read sets the state', () async {
    // arrange
    port.answer(session.id, BondState.bonded);

    // act
    final bonding = bondingOver();
    await pumpEventQueue();

    // assert
    expect(
      bonding.state,
      const Right<ConnectionFailure, BondState>(BondState.bonded),
    );
    expect(
      port.asked.where((asked) => asked.$1 == LinkOperation.readBondState),
      [(LinkOperation.readBondState, session.id)],
    );
  });

  test('a report replaces the state and reaches each listener after the '
      'state it had', () async {
    // arrange
    final bonding = bondingOver();
    final link = session.id;
    final seen = <BondState>[];
    rightOf(bonding.changes).listen(seen.add);

    // act
    port.report(link, BondState.bonding);
    port.report(link, BondState.bonded);
    await pumpEventQueue();

    // assert
    expect(seen, [BondState.none, BondState.bonding, BondState.bonded]);
    expect(
      bonding.state,
      const Right<ConnectionFailure, BondState>(BondState.bonded),
    );
  });

  test(
    'a first read that answers after a report does not replace it',
    () async {
      // arrange
      port
        ..holdReads()
        ..answer(session.id, BondState.bonded);
      final bonding = bondingOver();
      port.report(session.id, BondState.bonding);
      await pumpEventQueue();

      // act
      port.answerHeldReads();
      await pumpEventQueue();

      // assert
      expect(
        bonding.state,
        const Right<ConnectionFailure, BondState>(BondState.bonding),
      );
    },
  );

  test('a first read that answers after the link ended is ignored', () async {
    // arrange
    port
      ..holdReads()
      ..answer(session.id, BondState.bonded);
    final bonding = bondingOver();
    links.drop(device);
    await pumpEventQueue();

    // act
    port.answerHeldReads();
    await pumpEventQueue();

    // assert
    expect(
      bonding.state,
      const Right<ConnectionFailure, BondState>(BondState.none),
    );
  });

  test('a failed first read is logged once and the default stays', () async {
    // arrange
    port.failNext(
      LinkOperation.readBondState,
      const OperationTimedOut(LinkOperation.readBondState),
    );

    // act
    final bonding = bondingOver();
    await pumpEventQueue();

    // assert
    expect(
      bonding.state,
      const Right<ConnectionFailure, BondState>(BondState.none),
    );
    expect(
      log.records.map((r) => (r.level, r.context, r.message, r.errorCode)),
      [
        (
          BlueyLogLevel.warn,
          'bluey.connection',
          'bond state read failed',
          null,
        ),
      ],
    );
    expect(log.records.single.data, {
      'deviceId': 'AA:BB:CC:DD:EE:01',
      'exception': 'OperationTimedOut',
    });
  });

  test('a platform that cannot bond is never asked', () async {
    // arrange
    final bonding = bondingOver(features: noBonding);
    await pumpEventQueue();

    // act
    final state = bonding.state;
    final changes = bonding.changes;
    final bonded = await bonding.bond();
    final removed = await bonding.removeBond();

    // assert
    expect(port.asked, isEmpty);
    expect(log.records, isEmpty);
    expect(
      state,
      const Left<ConnectionFailure, BondState>(
        FeatureUnsupported(LinkOperation.readBondState),
      ),
    );
    expect(
      changes,
      const Left<ConnectionFailure, Stream<BondState>>(
        FeatureUnsupported(LinkOperation.followBondState),
      ),
    );
    expect(
      [bonded, removed],
      const [
        Left<ConnectionFailure, void>(FeatureUnsupported(LinkOperation.bond)),
        Left<ConnectionFailure, void>(
          FeatureUnsupported(LinkOperation.removeBond),
        ),
      ],
    );
  });

  test('after a plain disconnect the last state is still answered, and a '
      'request answers the end', () async {
    // arrange
    final bonding = bondingOver();
    port.report(session.id, BondState.bonded);
    await pumpEventQueue();
    await session.disconnect();

    // act
    final state = bonding.state;
    final bonded = await bonding.bond();
    final removed = await bonding.removeBond();

    // assert
    expect(state, const Right<ConnectionFailure, BondState>(BondState.bonded));
    const end = Left<ConnectionFailure, void>(LinkHadEnded(EndedOnRequest()));
    expect([bonded, removed], [end, end]);
    expect(
      port.asked.map((asked) => asked.$1),
      isNot(contains(anyOf(LinkOperation.bond, LinkOperation.removeBond))),
    );
  });

  test('after a radio outage the state and the requests answer the '
      'outage', () async {
    // arrange
    final bonding = bondingOver();
    links.outage(RadioOutage.off);
    await pumpEventQueue();

    // act
    final state = bonding.state;
    final changes = bonding.changes;
    final bonded = await bonding.bond();
    final removed = await bonding.removeBond();

    // assert
    const outage = LinkHadEnded(EndedByRadioOutage(RadioOutage.off));
    expect(state, const Left<ConnectionFailure, BondState>(outage));
    expect(changes, const Left<ConnectionFailure, Stream<BondState>>(outage));
    expect(
      [bonded, removed],
      const [
        Left<ConnectionFailure, void>(outage),
        Left<ConnectionFailure, void>(outage),
      ],
    );
  });

  test('the changes end when the link ends, and a later listener gets the '
      'last state and then the end', () async {
    // arrange
    final bonding = bondingOver();
    final early = <BondState>[];
    var earlyEnded = false;
    rightOf(bonding.changes).listen(early.add, onDone: () => earlyEnded = true);
    port.report(session.id, BondState.bonded);
    await pumpEventQueue();

    // act
    links.drop(device);
    await pumpEventQueue();
    final late = <BondState>[];
    var lateEnded = false;
    rightOf(bonding.changes).listen(late.add, onDone: () => lateEnded = true);
    await pumpEventQueue();

    // assert
    expect(early, [BondState.none, BondState.bonded]);
    expect(earlyEnded, isTrue);
    expect(late, [BondState.bonded]);
    expect(lateEnded, isTrue);
  });

  test('bond and removeBond ask the port while the link is up', () async {
    // arrange
    final bonding = bondingOver();

    // act
    final bonded = await bonding.bond();
    final removed = await bonding.removeBond();

    // assert
    expect(
      [bonded, removed],
      const [
        Right<ConnectionFailure, void>(null),
        Right<ConnectionFailure, void>(null),
      ],
    );
    expect(port.asked.skip(2), [
      (LinkOperation.bond, session.id),
      (LinkOperation.removeBond, session.id),
    ]);
    expect(log.records, isEmpty);
  });

  test('a rejected bond answers the rejection and keeps the state', () async {
    // arrange
    final bonding = bondingOver();
    port.failNext(
      LinkOperation.bond,
      const OperationRejected(LinkOperation.bond, 137),
    );

    // act
    final bonded = await bonding.bond();

    // assert
    expect(
      bonded,
      const Left<ConnectionFailure, void>(
        OperationRejected(LinkOperation.bond, 137),
      ),
    );
    expect(
      bonding.state,
      const Right<ConnectionFailure, BondState>(BondState.none),
    );
  });

  test('a report after the link ended changes nothing', () async {
    // arrange
    final bonding = bondingOver();
    final link = session.id;
    links.drop(device);
    await pumpEventQueue();

    // act
    port.report(link, BondState.bonded);
    await pumpEventQueue();

    // assert
    expect(
      bonding.state,
      const Right<ConnectionFailure, BondState>(BondState.none),
    );
  });
}
