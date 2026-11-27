import 'package:bluey/src/features/connection/application/link_session.dart';
import 'package:bluey/src/features/connection/application/phy_session.dart';
import 'package:bluey/src/features/connection/domain/connection_failure.dart';
import 'package:bluey/src/features/connection/domain/link_end.dart';
import 'package:bluey/src/features/connection/domain/link_features.dart';
import 'package:bluey/src/features/connection/domain/link_operation.dart';
import 'package:bluey/src/features/connection/domain/value_objects/phy.dart';
import 'package:bluey/src/shared/application/log_level.dart';
import 'package:bluey/src/shared/domain/device_address.dart';
import 'package:bluey/src/shared/domain/either.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../fixtures/features/connection/application/ports/in_memory_connection_ports.dart';
import '../../../fixtures/features/connection/application/ports/in_memory_links.dart';
import '../../../fixtures/features/connection/application/ports/in_memory_phy_control.dart';
import '../../../fixtures/features/connection/application/up_session.dart';
import '../../../fixtures/shared/application/recording_log.dart';

const device = DeviceAddress('AA:BB:CC:DD:EE:01');

const noPhy = LinkFeatures(
  canBond: true,
  canRequestPhy: false,
  canRequestParameters: true,
  canRequestMtu: true,
  maxMtu: 517,
);

const le1mBothWays = (tx: Phy.le1m, rx: Phy.le1m);
const reported = (tx: Phy.le2m, rx: Phy.leCoded);

Stream<PhyPair> rightOf(Either<ConnectionFailure, Stream<PhyPair>> it) =>
    it.fold((failure) => fail('the changes failed: $failure'), (s) => s);

void main() {
  late InMemoryLinks links;
  late InMemoryPhyControl port;
  late RecordingLog log;
  late LinkSession session;

  PhySession phyOver({LinkFeatures features = unlimitedLinkFeatures}) =>
      PhySession(session: session, phy: port, features: features, log: log);

  void expectPair(PhySession phy, PhyPair pair) {
    expect(phy.tx, Right<ConnectionFailure, Phy>(pair.tx));
    expect(phy.rx, Right<ConnectionFailure, Phy>(pair.rx));
  }

  setUp(() async {
    links = InMemoryLinks();
    port = InMemoryPhyControl();
    log = RecordingLog();
    session = await upSession(links, device);
  });

  test('holds le1m both ways until the radio says otherwise', () {
    // act
    final phy = phyOver();

    // assert
    expectPair(phy, le1mBothWays);
  });

  test('the first read sets the pair', () async {
    // arrange
    port.answer(session.id, reported);

    // act
    final phy = phyOver();
    await pumpEventQueue();

    // assert
    expectPair(phy, reported);
    expect(port.asked.where((asked) => asked.$1 == LinkOperation.readPhy), [
      (LinkOperation.readPhy, session.id),
    ]);
  });

  test('a report replaces the pair and reaches each listener after the '
      'pair it had', () async {
    // arrange
    final phy = phyOver();
    final seen = <PhyPair>[];
    rightOf(phy.changes).listen(seen.add);

    // act
    port.report(session.id, (tx: Phy.le2m, rx: Phy.le2m));
    port.report(session.id, reported);
    await pumpEventQueue();

    // assert
    expect(seen, [le1mBothWays, (tx: Phy.le2m, rx: Phy.le2m), reported]);
    expectPair(phy, reported);
  });

  test(
    'a first read that answers after a report does not replace it',
    () async {
      // arrange
      port
        ..holdReads()
        ..answer(session.id, (tx: Phy.leCoded, rx: Phy.leCoded));
      final phy = phyOver();
      port.report(session.id, reported);
      await pumpEventQueue();

      // act
      port.answerHeldReads();
      await pumpEventQueue();

      // assert
      expectPair(phy, reported);
    },
  );

  test('a first read that answers after the link ended is ignored', () async {
    // arrange
    port
      ..holdReads()
      ..answer(session.id, reported);
    final phy = phyOver();
    links.drop(device);
    await pumpEventQueue();

    // act
    port.answerHeldReads();
    await pumpEventQueue();

    // assert
    expectPair(phy, le1mBothWays);
  });

  test('a failed first read is logged once and the default stays', () async {
    // arrange
    port.failNext(
      LinkOperation.readPhy,
      const OperationTimedOut(LinkOperation.readPhy),
    );

    // act
    final phy = phyOver();
    await pumpEventQueue();

    // assert
    expectPair(phy, le1mBothWays);
    expect(
      log.records.map((r) => (r.level, r.context, r.message, r.errorCode)),
      [(BlueyLogLevel.warn, 'bluey.connection', 'phy read failed', null)],
    );
    expect(log.records.single.data, {
      'deviceId': 'AA:BB:CC:DD:EE:01',
      'exception': 'OperationTimedOut',
    });
  });

  test(
    'a first read that fails after the link ended is still logged',
    () async {
      // arrange
      port
        ..holdReads()
        ..failNext(
          LinkOperation.readPhy,
          const OperationRejected(LinkOperation.readPhy, 133),
        );
      phyOver();
      links.drop(device);
      await pumpEventQueue();

      // act
      port.answerHeldReads();
      await pumpEventQueue();

      // assert
      expect(log.records.map((r) => r.message), ['phy read failed']);
      expect(log.records.single.data, {
        'deviceId': 'AA:BB:CC:DD:EE:01',
        'exception': 'OperationRejected',
      });
    },
  );

  test('a platform that cannot set a PHY is never asked', () async {
    // arrange
    final phy = phyOver(features: noPhy);
    await pumpEventQueue();

    // act
    final tx = phy.tx;
    final rx = phy.rx;
    final changes = phy.changes;
    final requested = await phy.request(tx: Phy.le2m);

    // assert
    expect(port.asked, isEmpty);
    expect(log.records, isEmpty);
    expect(
      [tx, rx],
      const [
        Left<ConnectionFailure, Phy>(
          FeatureUnsupported(LinkOperation.readTransmitPhy),
        ),
        Left<ConnectionFailure, Phy>(
          FeatureUnsupported(LinkOperation.readReceivePhy),
        ),
      ],
    );
    expect(
      changes,
      const Left<ConnectionFailure, Stream<PhyPair>>(
        FeatureUnsupported(LinkOperation.followPhy),
      ),
    );
    expect(
      requested,
      const Left<ConnectionFailure, void>(
        FeatureUnsupported(LinkOperation.requestPhy),
      ),
    );
  });

  test('after a plain disconnect the last pair is still answered, and a '
      'request answers the end', () async {
    // arrange
    final phy = phyOver();
    port.report(session.id, reported);
    await pumpEventQueue();
    await session.disconnect();

    // act
    final requested = await phy.request(tx: Phy.le2m);

    // assert
    expectPair(phy, reported);
    expect(
      requested,
      const Left<ConnectionFailure, void>(LinkHadEnded(EndedOnRequest())),
    );
    expect(port.requests, isEmpty);
  });

  test('after a radio outage the pair and the request answer the '
      'outage', () async {
    // arrange
    final phy = phyOver();
    links.outage(RadioOutage.off);
    await pumpEventQueue();

    // act
    final tx = phy.tx;
    final rx = phy.rx;
    final changes = phy.changes;
    final requested = await phy.request(rx: Phy.leCoded);

    // assert
    const outage = LinkHadEnded(EndedByRadioOutage(RadioOutage.off));
    expect(
      [tx, rx],
      const [
        Left<ConnectionFailure, Phy>(outage),
        Left<ConnectionFailure, Phy>(outage),
      ],
    );
    expect(changes, const Left<ConnectionFailure, Stream<PhyPair>>(outage));
    expect(requested, const Left<ConnectionFailure, void>(outage));
  });

  test('the changes end when the link ends, and a later listener gets the '
      'last pair and then the end', () async {
    // arrange
    final phy = phyOver();
    final early = <PhyPair>[];
    var earlyEnded = false;
    rightOf(phy.changes).listen(early.add, onDone: () => earlyEnded = true);
    port.report(session.id, reported);
    await pumpEventQueue();

    // act
    links.drop(device);
    await pumpEventQueue();
    final late = <PhyPair>[];
    var lateEnded = false;
    rightOf(phy.changes).listen(late.add, onDone: () => lateEnded = true);
    await pumpEventQueue();

    // assert
    expect(early, [le1mBothWays, reported]);
    expect(earlyEnded, isTrue);
    expect(late, [reported]);
    expect(lateEnded, isTrue);
  });

  test('a request asks the port for the directions it was given', () async {
    // arrange
    final phy = phyOver();

    // act
    final requested = await phy.request(tx: Phy.le2m);

    // assert
    expect(requested, const Right<ConnectionFailure, void>(null));
    expect(port.requests, [(tx: Phy.le2m, rx: null)]);
    expect(port.asked.where((asked) => asked.$1 == LinkOperation.requestPhy), [
      (LinkOperation.requestPhy, session.id),
    ]);
    expect(log.records, isEmpty);
  });

  test('a request that succeeds leaves the pair until the radio '
      'reports', () async {
    // arrange
    final phy = phyOver();
    await pumpEventQueue();

    // act
    await phy.request(tx: Phy.le2m, rx: Phy.leCoded);
    final before = (phy.tx, phy.rx);
    port.report(session.id, reported);
    await pumpEventQueue();

    // assert
    expect(before, (
      const Right<ConnectionFailure, Phy>(Phy.le1m),
      const Right<ConnectionFailure, Phy>(Phy.le1m),
    ));
    expectPair(phy, reported);
  });

  test('a rejected request answers the rejection and keeps the pair', () async {
    // arrange
    final phy = phyOver();
    port.failNext(
      LinkOperation.requestPhy,
      const OperationRejected(LinkOperation.requestPhy, 137),
    );

    // act
    final requested = await phy.request(tx: Phy.leCoded);

    // assert
    expect(
      requested,
      const Left<ConnectionFailure, void>(
        OperationRejected(LinkOperation.requestPhy, 137),
      ),
    );
    expectPair(phy, le1mBothWays);
  });

  test('a report after the link ended changes nothing', () async {
    // arrange
    final phy = phyOver();
    final link = session.id;
    links.drop(device);
    await pumpEventQueue();

    // act
    port.report(link, reported);
    await pumpEventQueue();

    // assert
    expectPair(phy, le1mBothWays);
  });
}
