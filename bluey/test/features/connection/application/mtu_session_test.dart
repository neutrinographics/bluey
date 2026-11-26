import 'package:bluey/src/features/connection/application/link_session.dart';
import 'package:bluey/src/features/connection/application/mtu_session.dart';
import 'package:bluey/src/features/connection/domain/connection_failure.dart';
import 'package:bluey/src/features/connection/domain/link_end.dart';
import 'package:bluey/src/features/connection/domain/link_features.dart';
import 'package:bluey/src/features/connection/domain/link_operation.dart';
import 'package:bluey/src/features/connection/domain/value_objects/mtu.dart';
import 'package:bluey/src/shared/application/log_level.dart';
import 'package:bluey/src/shared/domain/device_address.dart';
import 'package:bluey/src/shared/domain/either.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../fixtures/features/connection/application/ports/in_memory_connection_ports.dart';
import '../../../fixtures/features/connection/application/ports/in_memory_links.dart';
import '../../../fixtures/features/connection/application/ports/in_memory_mtu_negotiation.dart';
import '../../../fixtures/features/connection/application/up_session.dart';
import '../../../fixtures/shared/application/recording_log.dart';

const device = DeviceAddress('AA:BB:CC:DD:EE:01');

const noMtuRequests = LinkFeatures(
  canBond: true,
  canRequestPhy: true,
  canRequestParameters: true,
  canRequestMtu: false,
  maxMtu: 23,
);

const upTo247 = LinkFeatures(
  canBond: true,
  canRequestPhy: true,
  canRequestParameters: true,
  canRequestMtu: true,
  maxMtu: 247,
);

void main() {
  late InMemoryLinks links;
  late InMemoryMtuNegotiation negotiation;
  late RecordingLog log;
  late LinkSession session;

  MtuSession sessionOver({LinkFeatures features = unlimitedLinkFeatures}) =>
      MtuSession(
        session: session,
        negotiation: negotiation,
        features: features,
        log: log,
        now: DateTime.now,
      );

  setUp(() async {
    links = InMemoryLinks();
    negotiation = InMemoryMtuNegotiation();
    log = RecordingLog();
    session = await upSession(links, device);
  });

  test('holds 23 until a request answers', () {
    // act
    final mtu = sessionOver();

    // assert
    expect(mtu.mtu, Right<ConnectionFailure, Mtu>(Mtu.minimum));
  });

  test('asks nothing and logs nothing until a request is made, since the '
      'radio reports no MTU by itself', () async {
    // act
    sessionOver();
    await pumpEventQueue();

    // assert
    expect(negotiation.requests, isEmpty);
    expect(log.records, isEmpty);
  });

  test('a request holds what the two sides settled on', () async {
    // arrange
    final mtu = sessionOver();
    negotiation.peerSettlesAt = 185;

    // act
    final answer = await mtu.request(Mtu(247));

    // assert
    expect(answer, Right<ConnectionFailure, Mtu>(Mtu.fromPlatform(185)));
    expect(mtu.mtu, Right<ConnectionFailure, Mtu>(Mtu.fromPlatform(185)));
    expect(negotiation.requests, [(session.link.id, Mtu(247))]);
  });

  test('a platform that cannot ask for an MTU answers FeatureUnsupported and '
      'asks nothing', () async {
    // arrange
    final mtu = sessionOver(features: noMtuRequests);

    // act
    final answer = await mtu.request(Mtu(247));

    // assert
    expect(
      answer,
      const Left<ConnectionFailure, Mtu>(
        FeatureUnsupported(LinkOperation.negotiateMtu),
      ),
    );
    expect(negotiation.requests, isEmpty);
  });

  test('a request above the maximum answers MtuAboveMaximum and asks '
      'nothing', () async {
    // arrange
    final mtu = sessionOver(features: upTo247);

    // act
    final answer = await mtu.request(Mtu(248));

    // assert
    expect(
      answer,
      Left<ConnectionFailure, Mtu>(
        MtuAboveMaximum(requested: Mtu(248), maximum: 247),
      ),
    );
    expect(negotiation.requests, isEmpty);
  });

  test(
    'a request on a dropped link answers its end and asks nothing',
    () async {
      // arrange
      final mtu = sessionOver();
      links.drop(device);
      await pumpEventQueue();

      // act
      final answer = await mtu.request(Mtu(247));

      // assert
      expect(
        answer,
        const Left<ConnectionFailure, Mtu>(LinkHadEnded(EndedByDrop())),
      );
      expect(negotiation.requests, isEmpty);
      expect(log.records, isEmpty);
    },
  );

  test('after a plain disconnect the MTU it had is still answered', () async {
    // arrange
    final mtu = sessionOver();
    await mtu.request(Mtu(185));

    // act
    await session.disconnect();

    // assert
    expect(mtu.mtu, Right<ConnectionFailure, Mtu>(Mtu.fromPlatform(185)));
  });

  test('after a radio outage the outage is answered before a missing '
      'feature', () async {
    // arrange
    final mtu = sessionOver(features: noMtuRequests);
    links.outage(RadioOutage.off);
    await pumpEventQueue();

    // act
    final requested = await mtu.request(Mtu(247));
    final held = mtu.mtu;

    // assert
    const outage = LinkHadEnded(EndedByRadioOutage(RadioOutage.off));
    expect(requested, const Left<ConnectionFailure, Mtu>(outage));
    expect(held, const Left<ConnectionFailure, Mtu>(outage));
    expect(negotiation.requests, isEmpty);
  });

  test('a link that ends during a request answers the end, and logs the '
      'failure at once', () {
    fakeAsync((async) {
      // arrange
      const timed = DeviceAddress('AA:BB:CC:DD:EE:02');
      late LinkSession timedSession;
      upSession(links, timed).then((value) => timedSession = value);
      async.elapse(Duration.zero);
      negotiation.delay = const Duration(seconds: 1);
      final mtu = MtuSession(
        session: timedSession,
        negotiation: negotiation,
        features: unlimitedLinkFeatures,
        log: log,
        now: DateTime.now,
      );
      Either<ConnectionFailure, Mtu>? answer;

      // act
      mtu.request(Mtu(247)).then((value) => answer = value);
      async.elapse(const Duration(milliseconds: 500));
      links.drop(timed);
      async.elapse(Duration.zero);
      final atDrop = answer;
      final logged = [...log.records];
      async.elapse(const Duration(seconds: 1));

      // assert

      expect(
        logged.map(
          (r) => (r.level, r.message, r.errorCode, r.data['exception']),
        ),
        [
          (BlueyLogLevel.debug, 'requestMtu start', null, null),
          (BlueyLogLevel.error, 'requestMtu failed', 'LinkEnded', 'LinkEnded'),
        ],
      );
      expect(log.records.length, 2);
      expect(
        atDrop,
        const Left<ConnectionFailure, Mtu>(LinkHadEnded(EndedByDrop())),
      );
      expect(mtu.mtu, Right<ConnectionFailure, Mtu>(Mtu.minimum));
    });
  });

  test('a failed request keeps the MTU it had', () async {
    // arrange
    final mtu = sessionOver();
    await mtu.request(Mtu(185));
    negotiation.rejectNext(133);

    // act
    final answer = await mtu.request(Mtu(247));

    // assert
    expect(answer, isA<Left<ConnectionFailure, Mtu>>());
    expect(mtu.mtu, Right<ConnectionFailure, Mtu>(Mtu.fromPlatform(185)));
  });

  test(
    'logs start and complete with what was requested and negotiated',
    () async {
      // arrange
      final mtu = sessionOver();
      negotiation.peerSettlesAt = 185;

      // act
      await mtu.request(Mtu(247));

      // assert
      expect(
        log.records.map(
          (r) => (r.level, r.context, r.message, r.data['detail']),
        ),
        [
          (
            BlueyLogLevel.debug,
            'bluey.gatt',
            'requestMtu start',
            'requested=247',
          ),
          (
            BlueyLogLevel.debug,
            'bluey.gatt',
            'requestMtu complete',
            'requested=247, negotiated=185',
          ),
        ],
      );
      expect(log.records.last.data['deviceId'], 'AA:BB:CC:DD:EE:01');
      expect(log.records.last.data['op'], 'requestMtu');
      expect(log.records.last.data['durationMs'], isA<int>());
    },
  );

  test(
    'a failed request logs the type of the failure, and its status',
    () async {
      // arrange
      final mtu = sessionOver();
      negotiation.rejectNext(133);

      // act
      await mtu.request(Mtu(247));

      // assert
      final failed = log.records.last;
      expect(failed.level, BlueyLogLevel.error);
      expect(failed.context, 'bluey.gatt');
      expect(failed.message, 'requestMtu failed');
      expect(failed.errorCode, 'OperationRejected');
      expect(failed.data['exception'], 'OperationRejected');
      expect(failed.data['status'], 133);
      expect(failed.data['detail'], 'requested=247');
    },
  );
}
