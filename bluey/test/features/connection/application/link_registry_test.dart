import 'package:clock/clock.dart';
import 'package:bluey/src/features/connection/application/borrowed_link.dart';
import 'package:bluey/src/features/connection/application/link_registry.dart';
import 'package:bluey/src/features/connection/application/link_session.dart';
import 'package:bluey/src/features/connection/domain/connection_failure.dart';
import 'package:bluey/src/features/connection/domain/link_end.dart';
import 'package:bluey/src/features/connection/domain/link_event.dart';
import 'package:bluey/src/shared/application/log_level.dart';
import 'package:bluey/src/shared/domain/device_address.dart';
import 'package:bluey/src/shared/domain/either.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../fixtures/either_results.dart';
import '../../../fixtures/features/connection/application/ports/in_memory_links.dart';
import '../../../fixtures/features/connection/recording_link_events.dart';
import '../../../fixtures/shared/application/recording_log.dart';

const device = DeviceAddress('AA:BB:CC:DD:EE:01');
final at = DateTime.utc(2026, 11, 26, 10);
const timedOut = Left<ConnectionFailure, BorrowedLink>(
  ConnectFailed(ConnectFailureReason.timeout),
);

void main() {
  late InMemoryLinks links;
  late RecordingLinkEvents events;
  late RecordingLog log;
  late LinkRegistry registry;
  DateTime? handedNow;

  void build() {
    handedNow = null;
    links = InMemoryLinks()..reach(device);
    events = RecordingLinkEvents();
    log = RecordingLog();
    registry = LinkRegistry(
      links: links,
      events: events,
      log: log,
      now: () => handedNow ?? clock.now(),
    );
  }

  setUp(build);

  Future<LinkSession> held() async => rightOf(await registry.hold(device));

  Future<BorrowedLink> borrowed() async =>
      rightOf(await registry.borrow(device));

  List<String> messages() => [for (final line in log.records) line.message];

  bool? isUp(Either<ConnectionFailure, LinkSession> answer) =>
      answer.fold((_) => null, (session) => session.link.isUp);

  bool? borrowedIsUp(Either<ConnectionFailure, BorrowedLink> answer) =>
      answer.fold((_) => null, (borrowed) => borrowed.session.link.isUp);

  group('ending', () {
    test('a link that ends raises one end at the handed time, also when a '
        'late outage follows', () async {
      // arrange
      await held();
      handedNow = at;

      // act
      links.drop(device);
      await pumpEventQueue();
      links.outage(RadioOutage.off);
      await pumpEventQueue();

      // assert
      expect(events.raised.whereType<LinkEnded>(), [
        LinkEnded(device: device, at: at, end: const EndedByDrop()),
      ]);
    });
  });

  group('opening', () {
    test('an open raises that it began, then that the link opened', () async {
      // arrange
      handedNow = at;

      // act
      await held();

      // assert
      expect(events.raised, [
        LinkOpenBegan(device: device, at: at),
        LinkOpened(device: device, at: at),
      ]);
      expect(messages(), ['connect started', 'connect succeeded']);
      for (final line in log.records) {
        expect(line.context, 'bluey.connection');
        expect(line.level, BlueyLogLevel.info);
        expect(line.data, {'address': device.value});
      }
    });

    test('a second acquire reuses the session and announces nothing', () async {
      // arrange
      final first = await held();

      // act
      final second = await borrowed();

      // assert
      expect(identical(first, second.session), isTrue);
      expect(links.opensAsked(device), 1);
      expect(events.raised, hasLength(2));
    });

    test('two acquires at once start one open and answer the same session', () {
      fakeAsync((async) {
        // arrange
        build();
        links.openDelay = const Duration(seconds: 1);

        // act
        final app = registry.hold(device);
        final borrower = registry.borrow(device);
        async.elapse(const Duration(seconds: 1));

        // assert
        expect(
          identical(
            rightOf(resultOf(app)),
            rightOf(resultOf(borrower)).session,
          ),
          isTrue,
        );
        expect(links.opensAsked(device), 1);
      });
    });

    test('a failed open answers the failure and forgets the device', () async {
      // arrange
      handedNow = at;
      links.failNextOpen(device, ConnectFailureReason.deviceNotConnectable);

      // act
      final answer = await registry.hold(device);

      // assert
      expect(
        answer,
        const Left<ConnectionFailure, LinkSession>(
          ConnectFailed(ConnectFailureReason.deviceNotConnectable),
        ),
      );
      expect(events.raised, [LinkOpenBegan(device: device, at: at)]);
      final failed = log.records.last;
      expect(failed.message, 'connect failed');
      expect(failed.level, BlueyLogLevel.error);
      expect(failed.context, 'bluey.connection');
      expect(failed.data, {
        'address': device.value,
        'exception': 'ConnectFailed',
      });
      expect(failed.errorCode, 'ConnectFailed');
      await held();
      expect(links.opensAsked(device), 2);
    });

    test(
      'a borrower\'s failed open logs at error, as the app\'s does',
      () async {
        // arrange
        links.failNextOpen(device, ConnectFailureReason.deviceNotConnectable);

        // act
        await registry.borrow(device);

        // assert
        expect(log.records.last.level, BlueyLogLevel.error);
      },
    );

    test('a borrower whose failures are routine logs its failed open at '
        'debug, the same line otherwise, and its start at info', () async {
      // arrange
      links.failNextOpen(device, ConnectFailureReason.deviceNotConnectable);

      // act
      await registry.borrow(device, failureIsRoutine: true);

      // assert
      final [started, failed] = log.records;
      expect(
        (started.message, started.level),
        ('connect started', BlueyLogLevel.info),
      );
      expect(failed.message, 'connect failed');
      expect(failed.level, BlueyLogLevel.debug);
      expect(failed.context, 'bluey.connection');
      expect(failed.data, {
        'address': device.value,
        'exception': 'ConnectFailed',
      });
      expect(failed.errorCode, 'ConnectFailed');
    });
  });

  group('waiting', () {
    test(
      'a waiter makes its own attempt when the attempt it waited on fails',
      () {
        fakeAsync((async) {
          // arrange
          build();
          links.openDelay = const Duration(seconds: 1);
          links.failNextOpen(device, ConnectFailureReason.timeout);

          // act
          final borrower = registry.borrow(
            device,
            timeout: const Duration(seconds: 3),
          );
          final app = registry.hold(device);
          async.elapse(const Duration(seconds: 5));

          // assert
          expect(resultOf(borrower), timedOut);
          expect(isUp(resultOf(app)), isTrue);
          expect(links.opensAsked(device), 2);
        });
      },
    );

    test('a waiter\'s timeout does not cancel the attempt in flight', () {
      fakeAsync((async) {
        // arrange
        build();
        links.openDelay = const Duration(seconds: 10);

        // act
        final app = registry.hold(device);
        final borrower = registry.borrow(
          device,
          timeout: const Duration(seconds: 3),
        );
        async.elapse(const Duration(seconds: 3));

        // assert
        expect(resultOf(borrower), timedOut);
        async.elapse(const Duration(seconds: 7));
        expect(isUp(resultOf(app)), isTrue);
        expect(links.opensAsked(device), 1);
      });
    });

    test('a waiter\'s own attempt gets only the time it has left', () {
      fakeAsync((async) {
        // arrange
        build();
        links.openDelay = const Duration(seconds: 1);
        links.failNextOpen(device, ConnectFailureReason.deviceNotFound);

        // act
        registry.hold(device);
        final borrower = registry.borrow(
          device,
          timeout: const Duration(seconds: 3),
        );
        async.elapse(const Duration(seconds: 2));

        // assert
        expect(links.openTimeouts, [null, const Duration(seconds: 2)]);
        expect(borrowedIsUp(resultOf(borrower)), isTrue);
      });
    });

    test('a caller that meets a closing link waits, then opens a new one', () {
      fakeAsync((async) {
        // arrange
        build();
        links.closeDelay = const Duration(seconds: 1);
        final borrower = registry.borrow(device);
        async.elapse(Duration.zero);
        final closing = rightOf(resultOf(borrower)).session;
        rightOf(resultOf(borrower)).giveBack();

        // act
        final app = registry.hold(device);
        async.elapse(const Duration(seconds: 1));

        // assert
        final reopened = rightOf(resultOf(app));
        expect(identical(reopened, closing), isFalse);
        expect(closing.link.hasEnded, isTrue);
        expect(reopened.link.isUp, isTrue);
        expect(links.opensAsked(device), 2);
      });
    });

    test('a borrower and the app arriving while the link closes get one new '
        'link between them', () {
      fakeAsync((async) {
        // arrange
        build();
        links.closeDelay = const Duration(seconds: 1);
        final app = registry.hold(device);
        async.elapse(Duration.zero);
        final closing = rightOf(resultOf(app));
        closing.disconnect();

        // act
        final borrower = registry.borrow(device);
        final appAgain = registry.hold(device);
        async.elapse(const Duration(seconds: 1));

        // assert
        final reopened = rightOf(resultOf(appAgain));
        expect(
          identical(rightOf(resultOf(borrower)).session, reopened),
          isTrue,
        );
        expect(identical(reopened, closing), isFalse);
        expect(reopened.link.isUp, isTrue);
        expect(links.opensAsked(device), 2);
      });
    });

    test('a waiter whose wait ends as its budget does answers the timeout', () {
      fakeAsync((async) {
        // arrange
        build();
        links.openDelay = const Duration(seconds: 3);
        links.failNextOpen(device, ConnectFailureReason.deviceNotFound);

        // act
        registry.hold(device);
        final borrower = registry.borrow(
          device,
          timeout: const Duration(seconds: 3),
        );
        async.elapse(const Duration(seconds: 3));

        // assert
        expect(resultOf(borrower), timedOut);
        expect(links.opensAsked(device), 1);
      });
    });

    test('a waiter times out when the clock it was handed passes its '
        'deadline, whatever the timers say', () {
      fakeAsync((async) {
        // arrange
        build();
        links.openDelay = const Duration(seconds: 1);
        links.failNextOpen(device, ConnectFailureReason.deviceNotFound);
        registry.hold(device);
        final borrower = registry.borrow(
          device,
          timeout: const Duration(seconds: 3),
        );

        // act
        handedNow = clock.now().add(const Duration(seconds: 5));
        async.elapse(const Duration(seconds: 1));

        // assert
        expect(resultOf(borrower), timedOut);
        expect(links.opensAsked(device), 1);
      });
    });

    test('a waiter wakes when a close the app started fails, and reuses the '
        'link', () {
      fakeAsync((async) {
        // arrange
        build();
        final app = registry.hold(device);
        async.elapse(Duration.zero);
        final session = rightOf(resultOf(app));
        links.closeDelay = const Duration(seconds: 1);
        links.failNextClose(device);
        session.disconnect();

        // act
        final borrower = registry.borrow(device);
        async.elapse(const Duration(seconds: 1));

        // assert
        expect(identical(rightOf(resultOf(borrower)).session, session), isTrue);
        expect(session.link.isUp, isTrue);
        expect(links.opensAsked(device), 1);
      });
    });

    test('a waiter wakes when a give-back\'s close fails, and reuses the '
        'link', () {
      fakeAsync((async) {
        // arrange
        build();
        final borrower = registry.borrow(device);
        async.elapse(Duration.zero);
        final session = rightOf(resultOf(borrower)).session;
        links.closeDelay = const Duration(seconds: 1);
        links.failNextClose(device);
        rightOf(resultOf(borrower)).giveBack();

        // act
        final app = registry.hold(device);
        async.elapse(const Duration(seconds: 1));

        // assert
        expect(identical(rightOf(resultOf(app)), session), isTrue);
        expect(session.link.isUp, isTrue);
        expect(links.opensAsked(device), 1);
      });
    });
  });

  group('ending', () {
    test('a link that ends is forgotten', () async {
      // arrange
      final first = await held();

      // act
      links.drop(device);
      await pumpEventQueue();
      final second = await held();

      // assert
      expect(first.link.hasEnded, isTrue);
      expect(identical(first, second), isFalse);
      expect(second.link.isUp, isTrue);
      expect(links.opensAsked(device), 2);
    });
  });

  group('giving back', () {
    test('a give-back by the only user closes the link', () async {
      // arrange
      final borrowedLink = await borrowed();
      final session = borrowedLink.session;

      // act
      final answer = await borrowedLink.giveBack();

      // assert
      expect(answer, const Right<ConnectionFailure, void>(null));
      expect(links.closesAsked(device), 1);
      expect(session.link.hasEnded, isTrue);
      await held();
      expect(links.opensAsked(device), 2);
    });

    test(
      'a give-back whose close fails answers the failure, and the next caller reuses the link',
      () async {
        // arrange
        final borrowedLink = await borrowed();
        final session = borrowedLink.session;
        links.failNextClose(device);

        // act
        final answer = await borrowedLink.giveBack();

        // assert
        expect(
          answer,
          const Left<ConnectionFailure, void>(
            UnexpectedPlatformFailure('the close was told to fail'),
          ),
        );
        expect(session.link.isUp, isTrue);
        final next = await held();
        expect(identical(next, session), isTrue);
        expect(links.opensAsked(device), 1);
      },
    );

    test(
      'a give-back or a keep of a session that is no longer live changes nothing',
      () async {
        // arrange
        final kept = await borrowed();
        final givenBack = await borrowed();
        links.drop(device);
        await pumpEventQueue();
        final live = await borrowed();

        // act
        kept.keep();
        final answer = await givenBack.giveBack();

        // assert
        expect(answer, const Right<ConnectionFailure, void>(null));
        expect(live.session.link.isUp, isTrue);
        await live.giveBack();
        expect(links.closesAsked(device), 1);
        expect(live.session.link.hasEnded, isTrue);
      },
    );
  });
}
