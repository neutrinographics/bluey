import 'dart:async';

import 'package:bluey/src/features/connection/application/link_session.dart';
import 'package:bluey/src/features/connection/domain/connection_event.dart';
import 'package:bluey/src/features/connection/domain/connection_failure.dart';
import 'package:bluey/src/features/connection/domain/connection_state.dart';
import 'package:bluey/src/features/connection/domain/link.dart';
import 'package:bluey/src/features/connection/domain/link_end.dart';
import 'package:bluey/src/features/connection/domain/link_id.dart';
import 'package:bluey/src/features/connection/domain/link_input.dart';
import 'package:bluey/src/shared/application/log_level.dart';
import 'package:bluey/src/shared/domain/device_address.dart';
import 'package:bluey/src/shared/domain/either.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../fixtures/features/connection/application/ports/in_memory_links.dart';
import '../../../fixtures/shared/application/recording_event_publisher.dart';
import '../../../fixtures/shared/application/recording_log.dart';

const device = DeviceAddress('AA:BB:CC:DD:EE:01');

/// The device of a session built inside `fakeAsync`, so its timers are the
/// fake's and it does not share [device]'s reports with the session [setUp]
/// builds.
const timed = DeviceAddress('AA:BB:CC:DD:EE:02');
const success = Right<ConnectionFailure, void>(null);

/// Radio whose reports a test can end by hand while the link is up, which
/// [InMemoryLinks] only does after a disconnected report or a close.
class EndingReports extends InMemoryLinks {
  final StreamController<LinkReport> reports = StreamController<LinkReport>();

  @override
  Stream<LinkReport> reportsOf(LinkId link) => reports.stream;
}

void main() {
  late InMemoryLinks links;
  late RecordingEventPublisher events;
  late RecordingLog log;
  late LinkSession session;
  late List<LinkEnd> released;

  Future<LinkSession> openSession(DeviceAddress at) async {
    final id = (await links.open(
      at,
    )).fold((failure) => fail('the open failed: $failure'), (id) => id);
    final opened = LinkSession(
      link: Link.opened(id: id, device: at),
      links: links,
      events: events,
      log: log,
    );
    opened.onEnd(released.add);
    return opened;
  }

  setUp(() async {
    links =
        InMemoryLinks()
          ..reach(device)
          ..reach(timed);
    events = RecordingEventPublisher();
    log = RecordingLog();
    released = [];
    session = await openSession(device);
  });

  LinkSession openTimedSession(FakeAsync async) {
    LinkSession? opened;
    openSession(timed).then((value) => opened = value);
    async.elapse(Duration.zero);
    return opened!;
  }

  List<ConnectionState> statesOf(LinkSession session) {
    final states = <ConnectionState>[];
    session.states.listen(states.add);
    return states;
  }

  Iterable<DisconnectedEvent> disconnects() =>
      events.events.whereType<DisconnectedEvent>();

  group('a drop', () {
    test(
      'emits disconnected, closes the states and runs the releases',
      () async {
        // arrange
        final states = <ConnectionState>[];
        var closed = false;
        session.states.listen(states.add, onDone: () => closed = true);

        // act
        links.drop(device);
        await pumpEventQueue();

        // assert
        expect(session.link.end, const EndedByDrop());
        expect(states, [ConnectionState.disconnected]);
        expect(closed, isTrue);
        expect(released, [const EndedByDrop()]);
        expect(disconnects().single.reason, 'linkLoss');
        expect(disconnects().single.deviceAddress, device);
      },
    );

    test(
      'a second end report publishes nothing and releases nothing',
      () async {
        // arrange
        links.report(device, LinkReport.disconnected);
        await pumpEventQueue();

        // act
        links.drop(device);
        links.outage(RadioOutage.off);
        await pumpEventQueue();

        // assert
        expect(disconnects(), hasLength(1));
        expect(released, [const EndedByDrop()]);
        expect(session.link.end, const EndedByDrop());
      },
    );

    test('reports that end while the link is up end it as a drop', () async {
      // arrange
      final radio = EndingReports()..reach(device);
      final ended = LinkSession(
        link: const Link.opened(id: LinkId('L1'), device: device),
        links: radio,
        events: events,
        log: log,
      );

      // act
      await radio.reports.close();
      await pumpEventQueue();

      // assert
      expect(ended.link.end, const EndedByDrop());
      expect(disconnects().single.reason, 'linkLoss');
    });

    test('a late connected report does not revive the link', () async {
      // arrange
      links.report(device, LinkReport.disconnected);
      await pumpEventQueue();

      // act
      links.report(device, LinkReport.connected);
      await pumpEventQueue();

      // assert
      expect(session.link.state, ConnectionState.disconnected);
      expect(session.link.hasEnded, isTrue);
    });

    test(
      'disconnect() after a drop answers success without asking the platform',
      () async {
        // arrange
        links.drop(device);
        await pumpEventQueue();

        // act
        final answer = await session.disconnect();

        // assert
        expect(answer, success);
        expect(links.closesAsked(device), 0);
      },
    );
  });

  group('disconnect()', () {
    test(
      'closes the link, ends on request and completes after the releases',
      () async {
        // arrange
        final releasing = Completer<void>();
        session.onEnd((_) => releasing.future);
        var done = false;

        // act
        final answer = session.disconnect().whenComplete(() => done = true);
        await pumpEventQueue();

        // assert
        expect(links.closesAsked(device), 1);
        expect(session.link.end, const EndedOnRequest());
        expect(released, [const EndedOnRequest()]);
        expect(done, isFalse);
        releasing.complete();
        expect(await answer, success);
        expect(disconnects().single.reason, 'requested');
      },
    );

    test('a second disconnect joins the close in flight', () {
      fakeAsync((async) {
        // arrange
        links.closeDelay = const Duration(seconds: 1);
        final session = openTimedSession(async);
        Either<ConnectionFailure, void>? first;
        Either<ConnectionFailure, void>? second;

        // act
        session.disconnect().then((answer) => first = answer);
        session.disconnect().then((answer) => second = answer);
        async.elapse(const Duration(seconds: 1));

        // assert
        expect(links.closesAsked(timed), 1);
        expect((first, second), (success, success));
        expect(session.link.end, const EndedOnRequest());
      });
    });

    test(
      'disconnect during a drop\'s teardown completes after the releases',
      () async {
        // arrange
        final releasing = Completer<void>();
        session.onEnd((_) => releasing.future);
        links.drop(device);
        await pumpEventQueue();
        var done = false;

        // act
        final answer = session.disconnect().whenComplete(() => done = true);
        await pumpEventQueue();

        // assert
        expect(done, isFalse);
        releasing.complete();
        expect(await answer, success);
        expect(links.closesAsked(device), 0);
      },
    );

    test(
      'a failed close leaves the link usable and answers the failure',
      () async {
        // arrange
        session.servicesDiscovered();
        await pumpEventQueue();
        final states = statesOf(session);
        links.failNextClose(device);

        // act
        final answer = await session.disconnect();
        await pumpEventQueue();

        // assert
        expect(
          answer,
          const Left<ConnectionFailure, void>(
            UnexpectedPlatformFailure('the close was told to fail'),
          ),
        );
        expect(session.link.state, ConnectionState.ready);
        expect(states, [ConnectionState.disconnecting, ConnectionState.ready]);
        expect(released, isEmpty);
        expect(disconnects(), isEmpty);
      },
    );

    test('a failed close on a link that dropped meanwhile answers success', () {
      fakeAsync((async) {
        // arrange
        links.closeDelay = const Duration(seconds: 1);
        final session = openTimedSession(async);
        links.failNextClose(timed);
        Either<ConnectionFailure, void>? answer;

        // act
        session.disconnect().then((value) => answer = value);
        async.elapse(const Duration(milliseconds: 500));
        links.report(timed, LinkReport.disconnected);
        async.elapse(const Duration(milliseconds: 500));

        // assert
        expect(answer, success);
        expect(session.link.end, const EndedOnRequest());
        expect(released, [const EndedOnRequest()]);
        expect(links.closesAsked(timed), 1);
      });
    });

    test(
      'logs disconnect entered, the transitions and disconnect resolved',
      () async {
        // act
        await session.disconnect();

        // assert
        final lines = log.records.where((r) => r.context == 'bluey.connection');
        expect(lines.map((r) => r.level), everyElement(BlueyLogLevel.info));
        expect(lines.map((r) => r.message), [
          'disconnect entered',
          'state transition',
          'state transition',
          'disconnect resolved',
        ]);
        expect(lines.map((r) => r.data), [
          {'deviceId': '$device'},
          {'deviceId': '$device', 'state': '${ConnectionState.disconnecting}'},
          {'deviceId': '$device', 'state': '${ConnectionState.disconnected}'},
          {'deviceId': '$device'},
        ]);
      },
    );

    test(
      'on a link the radio is closing, whose close failed, asks the close again',
      () async {
        // arrange
        links.report(device, LinkReport.disconnecting);
        await pumpEventQueue();
        links.failNextClose(device);
        final failed = await session.disconnect();

        // act
        final answer = await session.disconnect();

        // assert
        expect(failed, isA<Left<ConnectionFailure, void>>());
        expect(answer, success);
        expect(links.closesAsked(device), 2);
        expect(session.link.end, const EndedOnRequest());
      },
    );
  });

  group('releases', () {
    test('run in the order they were registered, once', () async {
      // arrange
      final order = <String>[];
      session.onEnd((_) => order.add('first'));
      session.onEnd((_) async => order.add('second'));

      // act
      await session.disconnect();
      await session.disconnect();
      links.outage(RadioOutage.off);
      await pumpEventQueue();

      // assert
      expect(order, ['first', 'second']);
      expect(released, [const EndedOnRequest()]);
    });

    test('a failing release does not stop the others', () async {
      // arrange
      session.onEnd((_) => throw StateError('boom'));
      session.onEnd(released.add);

      // act
      final answer = await session.disconnect();

      // assert
      expect(answer, success);
      expect(released, [const EndedOnRequest(), const EndedOnRequest()]);
      final failure = log.records.singleWhere(
        (r) => r.message == 'release failed',
      );
      expect(
        (failure.level, failure.context),
        (BlueyLogLevel.warn, 'bluey.connection'),
      );
    });

    test('one registered after the end runs at once', () async {
      // arrange
      links.drop(device);
      await pumpEventQueue();
      final late = <LinkEnd>[];

      // act
      session.onEnd(late.add);

      // assert
      expect(late, [const EndedByDrop()]);
    });

    test('one registered after the end that fails is logged', () async {
      // arrange
      links.drop(device);
      await pumpEventQueue();

      // act
      session.onEnd((_) => throw StateError('boom'));
      await pumpEventQueue();

      // assert
      expect(log.records.map((r) => r.message), contains('release failed'));
    });
  });

  group('whileUp', () {
    Future<Either<ConnectionFailure, T>> whileUp<T>(
      Future<Either<ConnectionFailure, T>> Function() operation,
    ) => session.whileUp(operation, orEnd: LinkEnded.new);

    test('answers the operation\'s value while the link is up', () async {
      // act
      final answer = await whileUp(
        () async => const Right<ConnectionFailure, int>(7),
      );

      // assert
      expect(answer, const Right<ConnectionFailure, int>(7));
    });

    test(
      'answers the end when the link ends first, and ignores the late answer',
      () async {
        // arrange
        final operation = Completer<Either<ConnectionFailure, int>>();
        final answer = whileUp(() => operation.future);

        // act
        links.drop(device);
        await pumpEventQueue();

        // assert
        expect(
          await answer,
          const Left<ConnectionFailure, int>(LinkEnded(EndedByDrop())),
        );
        operation.complete(const Right(7));
        await pumpEventQueue();
      },
    );

    test('does not start the operation on a closing or ended link', () async {
      // arrange
      var started = 0;
      Future<Either<ConnectionFailure, int>> operation() async {
        started++;
        return const Right(7);
      }

      links.report(device, LinkReport.disconnecting);
      await pumpEventQueue();

      // act
      final whileClosing = await whileUp(operation);
      links.report(device, LinkReport.disconnected);
      await pumpEventQueue();
      final whileEnded = await whileUp(operation);

      // assert
      expect(started, 0);
      expect(
        (whileClosing, whileEnded),
        (
          const Left<ConnectionFailure, int>(LinkEnded(EndedByDrop())),
          const Left<ConnectionFailure, int>(LinkEnded(EndedByDrop())),
        ),
      );
    });

    test('hands on an error the operation raises', () async {
      // act
      final answer = whileUp<int>(() => throw StateError('boom'));

      // assert
      await expectLater(answer, throwsStateError);
    });
  });

  test('an outage invalidates the link and reports radioOutage', () async {
    // arrange
    final states = statesOf(session);

    // act
    links.outage(RadioOutage.off);
    await pumpEventQueue();

    // assert
    expect(session.link.end, const EndedByRadioOutage(RadioOutage.off));
    expect(states, [ConnectionState.invalidated]);
    expect(released, [const EndedByRadioOutage(RadioOutage.off)]);
    expect(disconnects().single.reason, 'radioOutage');
  });

  test('servicesDiscovered makes the link ready, once', () async {
    // arrange
    final states = statesOf(session);

    // act
    session.servicesDiscovered();
    session.servicesDiscovered();
    await pumpEventQueue();

    // assert
    expect(states, [ConnectionState.ready]);
    expect(session.link.state, ConnectionState.ready);
  });
}
