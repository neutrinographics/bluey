import 'dart:async';

import 'package:bluey/src/features/connection/application/link_session.dart';
import 'package:bluey/src/features/connection/domain/connection_failure.dart';
import 'package:bluey/src/api/connection/connection_state.dart';
import 'package:bluey/src/features/connection/domain/link_end.dart';
import 'package:bluey/src/features/connection/domain/link_event.dart';
import 'package:bluey/src/features/connection/domain/link_id.dart';
import 'package:bluey/src/features/connection/domain/link_input.dart';
import 'package:bluey/src/features/connection/domain/link_phase.dart';
import 'package:bluey/src/shared/application/log_level.dart';
import 'package:bluey/src/shared/domain/device_address.dart';
import 'package:bluey/src/shared/domain/either.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../fixtures/features/connection/application/ports/in_memory_links.dart';
import '../../../fixtures/features/connection/recording_link_events.dart';
import '../../../fixtures/shared/application/recording_log.dart';
import 'package:bluey/src/shared/domain/radio_outage.dart';

const device = DeviceAddress('AA:BB:CC:DD:EE:01');

/// The device of a session built inside `fakeAsync`, so its timers are the
/// fake's and it does not share [device]'s reports with the session [setUp]
/// builds.
const timed = DeviceAddress('AA:BB:CC:DD:EE:02');
const success = Right<ConnectionFailure, void>(null);
final now = DateTime.utc(2026, 11, 26, 10);

/// Radio whose reports a test can end by hand while the link is up, which
/// [InMemoryLinks] only does after a disconnected report or a close.
class EndingReports extends InMemoryLinks {
  final StreamController<LinkReport> reports = StreamController<LinkReport>();

  @override
  Stream<LinkReport> reportsOf(LinkId link) => reports.stream;
}

void main() {
  late InMemoryLinks links;
  late RecordingLinkEvents events;
  late RecordingLog log;
  late LinkSession session;
  late List<LinkEnd> released;

  Future<LinkSession> openSession(DeviceAddress at) async {
    final id = (await links.open(
      at,
    )).fold((failure) => fail('the open failed: $failure'), (id) => id);
    final opened = LinkSession.begin(
      device: at,
      links: links,
      events: events,
      log: log,
      now: () => now,
    )..opened(id);
    opened.onEnd(released.add);
    return opened;
  }

  setUp(() async {
    links =
        InMemoryLinks()
          ..reach(device)
          ..reach(timed);
    events = RecordingLinkEvents();
    log = RecordingLog();
    released = [];
    session = await openSession(device);
    events.raised.clear();
  });

  LinkSession openTimedSession(FakeAsync async) {
    LinkSession? opened;
    openSession(timed).then((value) => opened = value);
    async.elapse(Duration.zero);
    return opened!;
  }

  List<LinkPhase> phasesOf(LinkSession session) {
    final phases = <LinkPhase>[];
    session.phases.listen(phases.add);
    return phases;
  }

  Iterable<LinkEnded> ends() => events.raised.whereType<LinkEnded>();

  group('beginning', () {
    const opening = DeviceAddress('AA:BB:CC:DD:EE:03');

    LinkSession begin() => LinkSession.begin(
      device: opening,
      links: links,
      events: events,
      log: log,
      now: () => now,
    );

    test('a session begins by raising that the open began, and listens to '
        'nothing', () {
      // act
      final began = begin();

      // assert
      expect(events.raised, [LinkOpenBegan(device: opening, at: now)]);
      expect(began.phase, const Opening());
      expect(began.isUp, isFalse);
      expect(log.records, isEmpty);
      expect(links.outagesHeard, isTrue, reason: 'the setUp session listens');
    });

    test('reading the id before the link opened is a StateError naming the '
        'device', () {
      // arrange
      final began = begin();

      // act
      LinkId read() => began.id;

      // assert
      expect(
        read,
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains(opening.value),
          ),
        ),
      );
    });

    test('opened links the session, raises that it opened and logs no state '
        'transition', () async {
      // arrange
      links.reach(opening);
      final openedId = (await links.open(
        opening,
      )).fold((failure) => fail('the open failed: $failure'), (id) => id);
      final began = begin();
      final seen = <LinkPhase>[];
      began.phases.listen(seen.add);

      // act
      began.opened(openedId);
      await pumpEventQueue();

      // assert
      expect(began.phase, const Linked());
      expect(began.id, openedId);
      expect(began.isUp, isTrue);
      expect(events.raised.last, LinkOpened(device: opening, at: now));
      expect(log.records, isEmpty);
      expect(seen, [const Linked()]);
    });

    test('notOpened raises nothing more, logs nothing and ends the '
        'phases', () async {
      // arrange
      final began = begin();
      final seen = <LinkPhase>[];
      var done = false;
      began.phases.listen(seen.add, onDone: () => done = true);
      final releases = <LinkEnd>[];
      began.onEnd(releases.add);

      // act
      began.notOpened();
      await pumpEventQueue();

      // assert
      expect(began.phase, const NeverOpened());
      expect(events.raised, [LinkOpenBegan(device: opening, at: now)]);
      expect(log.records, isEmpty);
      expect(seen, [const NeverOpened()]);
      expect(done, isTrue);
      expect(releases, isEmpty);
    });

    test('a disconnect on an opening session starts no close and answers '
        'once the open fails', () async {
      // arrange
      final began = begin();

      // act
      final answer = began.disconnect();
      began.notOpened();

      // assert
      expect(await answer, success);
      expect(links.closesAsked(opening), 0);
    });
  });

  group('following', () {
    Future<LinkId> openedOn(InMemoryLinks quiet) async {
      quiet.reach(device);
      return (await quiet.open(
        device,
      )).fold((failure) => fail('the open failed: $failure'), (id) => id);
    }

    test('a session hears no outage until its link opens', () async {
      // arrange
      final quiet = InMemoryLinks();
      final id = await openedOn(quiet);
      final began = LinkSession.begin(
        device: device,
        links: quiet,
        events: events,
        log: log,
        now: () => now,
      );

      // act
      final heardWhileOpening = quiet.outagesHeard;
      began.opened(id);

      // assert
      expect((heardWhileOpening, quiet.outagesHeard), (false, true));
    });

    test('an outage while opening is not heard, and the next one ends the '
        'opened link', () async {
      // arrange
      final quiet = InMemoryLinks();
      final id = await openedOn(quiet);
      final began = LinkSession.begin(
        device: device,
        links: quiet,
        events: events,
        log: log,
        now: () => now,
      );
      quiet.outage(RadioOutage.off);
      await pumpEventQueue();
      began.opened(id);
      final linkedAfterOutage = began.phase;

      // act
      quiet.outage(RadioOutage.unknown);
      await pumpEventQueue();

      // assert
      expect(linkedAfterOutage, const Linked());
      expect(began.link.end, const EndedByRadioOutage(RadioOutage.unknown));
    });

    test('an opened session hears its link\'s reports', () async {
      // arrange
      final id = (await links.open(
        timed,
      )).fold((failure) => fail('the open failed: $failure'), (id) => id);
      final began = LinkSession.begin(
        device: timed,
        links: links,
        events: events,
        log: log,
        now: () => now,
      )..opened(id);

      // act
      links.drop(timed);
      await pumpEventQueue();

      // assert
      expect(began.link.end, const EndedByDrop());
    });
  });

  group('its id', () {
    test('is the id the platform answered for the link', () async {
      // arrange
      final id = (await links.open(
        timed,
      )).fold((failure) => fail('the open failed: $failure'), (id) => id);

      // act
      final opened = LinkSession.begin(
        device: timed,
        links: links,
        events: events,
        log: log,
        now: () => now,
      )..opened(id);

      // assert
      expect(opened.id, id);
    });
  });

  group('as a live link', () {
    test('is no longer up from the moment a close is asked until it is let '
        'go of', () async {
      // arrange
      final before = session.isUp;

      // act
      final closed = session.disconnect();
      final whileClosing = session.isUp;
      await closed;

      // assert
      expect((before, whileClosing, session.isUp), (true, false, false));
    });

    test('is no longer up once its link has dropped', () async {
      // act
      links.drop(device);
      await pumpEventQueue();

      // assert
      expect((session.link.hasEnded, session.isUp), (true, false));
    });
  });

  group('a drop', () {
    test(
      'enters the ended phase, closes the phases and runs the releases',
      () async {
        // arrange
        final phases = <LinkPhase>[];
        var closed = false;
        session.phases.listen(phases.add, onDone: () => closed = true);

        // act
        links.drop(device);
        await pumpEventQueue();

        // assert
        expect(session.link.end, const EndedByDrop());
        expect(phases, [const Ended(EndedByDrop())]);
        expect(closed, isTrue);
        expect(released, [const EndedByDrop()]);
        expect(events.raised, [
          LinkEnded(device: device, at: now, end: const EndedByDrop()),
        ]);
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
        expect(ends(), hasLength(1));
        expect(released, [const EndedByDrop()]);
        expect(session.link.end, const EndedByDrop());
      },
    );

    test('reports that end while the link is up end it as a drop', () async {
      // arrange
      final radio = EndingReports()..reach(device);
      final ended = LinkSession.begin(
        device: device,
        links: radio,
        events: events,
        log: log,
        now: () => now,
      )..opened(const LinkId('L1'));

      // act
      await radio.reports.close();
      await pumpEventQueue();

      // assert
      expect(ended.link.end, const EndedByDrop());
      expect(ends().single.end, const EndedByDrop());
    });

    test('a late connected report does not revive the link', () async {
      // arrange
      links.report(device, LinkReport.disconnected);
      await pumpEventQueue();

      // act
      links.report(device, LinkReport.connected);
      await pumpEventQueue();

      // assert
      expect(session.phase, const Ended(EndedByDrop()));
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
        expect(ends().single.end, const EndedOnRequest());
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
        final phases = phasesOf(session);
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
        expect(session.phase, const Ready());
        expect(phases, [
          const Closing(returnTo: Ready(), by: ClosingBy.request),
          const Ready(),
        ]);
        expect(released, isEmpty);
        expect(ends(), isEmpty);
      },
    );

    test('a closing report while the close is in flight, then a failed close, '
        'leaves the link ready and usable', () {
      fakeAsync((async) {
        // arrange
        links.closeDelay = const Duration(seconds: 1);
        final session = openTimedSession(async);
        session.servicesDiscovered();
        links.failNextClose(timed);
        Either<ConnectionFailure, void>? answer;
        session.disconnect().then((value) => answer = value);
        async.elapse(const Duration(milliseconds: 500));
        links.report(timed, LinkReport.disconnecting);
        async.elapse(const Duration(milliseconds: 500));

        // act
        Either<ConnectionFailure, int>? operation;
        session
            .whileUp(
              () async => const Right<ConnectionFailure, int>(7),
              orEnd: LinkHadEnded.new,
            )
            .then((value) => operation = value);
        async.flushMicrotasks();

        // assert
        expect(answer, isA<Left<ConnectionFailure, void>>());
        expect(session.phase, const Ready());
        expect(operation, const Right<ConnectionFailure, int>(7));
      });
    });

    test('a failed close on a link that ended meanwhile answers success', () {
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
      'a disconnect after the link ended with a close in flight joins that close',
      () {
        fakeAsync((async) {
          // arrange
          links.closeDelay = const Duration(seconds: 1);
          final session = openTimedSession(async);
          Either<ConnectionFailure, void>? first;
          Either<ConnectionFailure, void>? second;
          session.disconnect().then((answer) => first = answer);
          async.elapse(const Duration(milliseconds: 500));
          links.outage(RadioOutage.off);
          async.flushMicrotasks();

          // act
          session.disconnect().then((answer) => second = answer);
          async.elapse(const Duration(milliseconds: 400));

          // assert
          expect(session.link.end, const EndedByRadioOutage(RadioOutage.off));
          expect((first, second), (null, null));
          async.elapse(const Duration(milliseconds: 100));
          expect((first, second), (success, success));
          expect(links.closesAsked(timed), 1);
        });
      },
    );

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
    test(
      'one registered during the teardown runs before disconnect answers',
      () async {
        // arrange
        final releasing = Completer<void>();
        final lateGate = Completer<void>();
        final order = <String>[];
        session.onEnd((_) => releasing.future);
        links.drop(device);
        await pumpEventQueue();
        session.onEnd((_) async {
          await lateGate.future;
          order.add('late release');
        });
        final answer = session.disconnect().whenComplete(
          () => order.add('answered'),
        );

        // act
        releasing.complete();
        await pumpEventQueue();
        lateGate.complete();
        await answer;

        // assert
        expect(order, ['late release', 'answered']);
      },
    );

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
    ) => session.whileUp(operation, orEnd: LinkHadEnded.new);

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
          const Left<ConnectionFailure, int>(LinkHadEnded(EndedByDrop())),
        );
        operation.complete(const Right(7));
        await pumpEventQueue();
        expect(
          log.records.where((r) => r.level == BlueyLogLevel.warn),
          isEmpty,
        );
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
          const Left<ConnectionFailure, int>(LinkHadEnded(EndedByDrop())),
          const Left<ConnectionFailure, int>(LinkHadEnded(EndedByDrop())),
        ),
      );
    });

    test('an orEnd that throws does not stop the teardown', () async {
      // arrange
      final operation = Completer<Either<ConnectionFailure, int>>();
      final answer = session.whileUp<ConnectionFailure, int>(
        () => operation.future,
        orEnd: (_) => throw StateError('boom'),
      );
      final phases = <LinkPhase>[];
      session.phases.listen(phases.add);

      // act
      links.drop(device);
      await pumpEventQueue();

      // assert
      expect(ends().single.end, const EndedByDrop());
      expect(released, [const EndedByDrop()]);
      expect(await session.disconnect(), success);
      final failure = log.records.singleWhere(
        (r) => r.level == BlueyLogLevel.warn,
      );
      expect(
        (failure.context, failure.message),
        ('bluey.connection', 'end answer failed'),
      );
      operation.complete(const Right(7));
      expect(await answer, const Right<ConnectionFailure, int>(7));
    });

    test('hands on an error the operation raises', () async {
      // act
      final answer = whileUp<int>(() => throw StateError('boom'));

      // assert
      await expectLater(answer, throwsStateError);
    });
  });

  group('state transition lines', () {
    List<String?> loggedStates() => [
      for (final r in log.records)
        if (r.context == 'bluey.connection' && r.message == 'state transition')
          r.data['state'] as String?,
    ];

    test('name each phase entered as logs named it before', () async {
      // arrange
      links.failNextClose(device);
      await session.disconnect();
      session.servicesDiscovered();
      await pumpEventQueue();
      links.failNextClose(device);
      await session.disconnect();

      // act
      links.outage(RadioOutage.off);
      await pumpEventQueue();

      // assert
      expect(loggedStates(), [
        'ConnectionState.disconnecting',
        'ConnectionState.linked',
        'ConnectionState.ready',
        'ConnectionState.disconnecting',
        'ConnectionState.ready',
        'ConnectionState.invalidated',
      ]);
    });

    test('name a drop as disconnected', () async {
      // act
      links.drop(device);
      await pumpEventQueue();

      // assert
      expect(loggedStates(), ['ConnectionState.disconnected']);
    });

    test('log no second closing when a request joins the radio closing the '
        'link', () async {
      // arrange
      links.report(device, LinkReport.disconnecting);
      await pumpEventQueue();

      // act
      await session.disconnect();

      // assert
      expect(loggedStates(), [
        'ConnectionState.disconnecting',
        'ConnectionState.disconnected',
      ]);
    });
  });

  test('an outage invalidates the link and reports radioOutage', () async {
    // arrange
    final phases = phasesOf(session);

    // act
    links.outage(RadioOutage.off);
    await pumpEventQueue();

    // assert
    expect(session.link.end, const EndedByRadioOutage(RadioOutage.off));
    expect(phases, [const Ended(EndedByRadioOutage(RadioOutage.off))]);
    expect(released, [const EndedByRadioOutage(RadioOutage.off)]);
    expect(ends().single.end, const EndedByRadioOutage(RadioOutage.off));
  });

  test('servicesDiscovered makes the link ready, once', () async {
    // arrange
    final phases = phasesOf(session);

    // act
    session.servicesDiscovered();
    session.servicesDiscovered();
    await pumpEventQueue();

    // assert
    expect(phases, [const Ready()]);
    expect(session.phase, const Ready());
  });
}
