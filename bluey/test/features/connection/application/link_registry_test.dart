import 'package:bluey/src/features/connection/application/link_registry.dart';
import 'package:bluey/src/features/connection/application/link_session.dart';
import 'package:bluey/src/features/connection/domain/connection_event.dart';
import 'package:bluey/src/features/connection/domain/connection_failure.dart';
import 'package:bluey/src/features/connection/domain/live_links.dart';
import 'package:bluey/src/shared/application/log_level.dart';
import 'package:bluey/src/shared/domain/device_address.dart';
import 'package:bluey/src/shared/domain/either.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../fixtures/either_results.dart';
import '../../../fixtures/features/connection/application/ports/in_memory_links.dart';
import '../../../fixtures/shared/application/recording_event_publisher.dart';
import '../../../fixtures/shared/application/recording_log.dart';

const device = DeviceAddress('AA:BB:CC:DD:EE:01');
const timedOut = Left<ConnectionFailure, LinkSession>(
  ConnectFailed(ConnectFailureReason.timeout),
);

void main() {
  late InMemoryLinks links;
  late RecordingEventPublisher events;
  late RecordingLog log;
  late LinkRegistry registry;

  void build() {
    links = InMemoryLinks()..reach(device);
    events = RecordingEventPublisher();
    log = RecordingLog();
    registry = LinkRegistry(links: links, events: events, log: log);
  }

  setUp(build);

  Future<LinkSession> acquired(LinkUser by) async =>
      rightOf(await registry.acquire(device, by: by));

  List<String> messages() => [for (final line in log.records) line.message];

  bool? isUp(Either<ConnectionFailure, LinkSession> answer) =>
      answer.fold((_) => null, (session) => session.link.isUp);

  group('opening', () {
    test('an open is announced: connecting, then connected', () async {
      // act
      await acquired(LinkUser.app);

      // assert
      expect(events.events, [isA<ConnectingEvent>(), isA<ConnectedEvent>()]);
      expect(
        events.events.whereType<ConnectedEvent>().single.deviceAddress,
        device,
      );
      expect(messages(), ['connect started', 'connect succeeded']);
      for (final line in log.records) {
        expect(line.context, 'bluey.connection');
        expect(line.level, BlueyLogLevel.info);
        expect(line.data, {'address': device.value});
      }
    });

    test('a second acquire reuses the session and announces nothing', () async {
      // arrange
      final first = await acquired(LinkUser.app);

      // act
      final second = await acquired(LinkUser.borrower);

      // assert
      expect(identical(first, second), isTrue);
      expect(links.opensAsked(device), 1);
      expect(events.events, hasLength(2));
    });

    test('two acquires at once start one open and answer the same session', () {
      fakeAsync((async) {
        // arrange
        build();
        links.openDelay = const Duration(seconds: 1);

        // act
        final app = registry.acquire(device, by: LinkUser.app);
        final borrower = registry.acquire(device, by: LinkUser.borrower);
        async.elapse(const Duration(seconds: 1));

        // assert
        expect(
          identical(rightOf(resultOf(app)), rightOf(resultOf(borrower))),
          isTrue,
        );
        expect(links.opensAsked(device), 1);
      });
    });

    test('a failed open answers the failure and forgets the device', () async {
      // arrange
      links.failNextOpen(device, ConnectFailureReason.deviceNotConnectable);

      // act
      final answer = await registry.acquire(device, by: LinkUser.app);

      // assert
      expect(
        answer,
        const Left<ConnectionFailure, LinkSession>(
          ConnectFailed(ConnectFailureReason.deviceNotConnectable),
        ),
      );
      expect(events.events.whereType<ConnectedEvent>(), isEmpty);
      final failed = log.records.last;
      expect(failed.message, 'connect failed');
      expect(failed.level, BlueyLogLevel.error);
      expect(failed.context, 'bluey.connection');
      expect(failed.data, {
        'address': device.value,
        'exception': 'ConnectFailed',
      });
      expect(failed.errorCode, 'ConnectFailed');
      await acquired(LinkUser.app);
      expect(links.opensAsked(device), 2);
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
          final borrower = registry.acquire(
            device,
            by: LinkUser.borrower,
            timeout: const Duration(seconds: 3),
          );
          final app = registry.acquire(device, by: LinkUser.app);
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
        final app = registry.acquire(device, by: LinkUser.app);
        final borrower = registry.acquire(
          device,
          by: LinkUser.borrower,
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
        registry.acquire(device, by: LinkUser.app);
        final borrower = registry.acquire(
          device,
          by: LinkUser.borrower,
          timeout: const Duration(seconds: 3),
        );
        async.elapse(const Duration(seconds: 2));

        // assert
        expect(links.openTimeouts, [null, const Duration(seconds: 2)]);
        expect(isUp(resultOf(borrower)), isTrue);
      });
    });

    test('a caller that meets a closing link waits, then opens a new one', () {
      fakeAsync((async) {
        // arrange
        build();
        links.closeDelay = const Duration(seconds: 1);
        final borrower = registry.acquire(device, by: LinkUser.borrower);
        async.elapse(Duration.zero);
        final closing = rightOf(resultOf(borrower));
        registry.giveBack(closing);

        // act
        final app = registry.acquire(device, by: LinkUser.app);
        async.elapse(const Duration(seconds: 1));

        // assert
        final reopened = rightOf(resultOf(app));
        expect(identical(reopened, closing), isFalse);
        expect(closing.link.hasEnded, isTrue);
        expect(reopened.link.isUp, isTrue);
        expect(links.opensAsked(device), 2);
      });
    });
  });

  group('ending', () {
    test('a link that ends is forgotten', () async {
      // arrange
      final first = await acquired(LinkUser.app);

      // act
      links.drop(device);
      await pumpEventQueue();
      final second = await acquired(LinkUser.app);

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
      final session = await acquired(LinkUser.borrower);

      // act
      final answer = await registry.giveBack(session);

      // assert
      expect(answer, const Right<ConnectionFailure, void>(null));
      expect(links.closesAsked(device), 1);
      expect(session.link.hasEnded, isTrue);
      await acquired(LinkUser.app);
      expect(links.opensAsked(device), 2);
    });

    test(
      'a give-back whose close fails answers the failure, and the next caller reuses the link',
      () async {
        // arrange
        final session = await acquired(LinkUser.borrower);
        links.failNextClose(device);

        // act
        final answer = await registry.giveBack(session);

        // assert
        expect(
          answer,
          const Left<ConnectionFailure, void>(
            UnexpectedPlatformFailure('the close was told to fail'),
          ),
        );
        expect(session.link.isUp, isTrue);
        final next = await acquired(LinkUser.app);
        expect(identical(next, session), isTrue);
        expect(links.opensAsked(device), 1);
      },
    );

    test(
      'a give-back or a keep of a session that is no longer live changes nothing',
      () async {
        // arrange
        final ended = await acquired(LinkUser.borrower);
        links.drop(device);
        await pumpEventQueue();
        final live = await acquired(LinkUser.borrower);

        // act
        registry.keep(ended);
        final answer = await registry.giveBack(ended);

        // assert
        expect(answer, const Right<ConnectionFailure, void>(null));
        expect(live.link.isUp, isTrue);
        await registry.giveBack(live);
        expect(links.closesAsked(device), 1);
        expect(live.link.hasEnded, isTrue);
      },
    );
  });
}
