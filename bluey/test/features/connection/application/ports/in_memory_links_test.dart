import 'package:bluey/src/features/connection/domain/connection_failure.dart';
import 'package:bluey/src/features/connection/domain/link_id.dart';
import 'package:bluey/src/features/connection/domain/link_input.dart';
import 'package:bluey/src/shared/domain/device_address.dart';
import 'package:bluey/src/shared/domain/either.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../fixtures/features/connection/application/ports/in_memory_links.dart';
import '../../../../fixtures/features/connection/application/ports/links_contract.dart';

const device = DeviceAddress('AA:BB:CC:DD:EE:01');
const other = DeviceAddress('AA:BB:CC:DD:EE:02');

void main() {
  linksContract('InMemoryLinks', InMemoryLinks.new);

  group('opening', () {
    test('a link is named by its device\'s address, as the platforms name '
        'it', () async {
      // arrange
      final links =
          InMemoryLinks()
            ..reach(device)
            ..reach(other);

      // act
      final first = await links.open(device);
      final second = await links.open(other);

      // assert
      expect(
        [first, second],
        [
          Right<ConnectionFailure, LinkId>(LinkId(device.value)),
          Right<ConnectionFailure, LinkId>(LinkId(other.value)),
        ],
      );
    });

    test('a device nobody made reachable is not found', () async {
      // arrange
      final links = InMemoryLinks();

      // act
      final answer = await links.open(device);

      // assert
      expect(
        answer,
        const Left<ConnectionFailure, LinkId>(
          ConnectFailed(ConnectFailureReason.deviceNotFound),
        ),
      );
    });

    test('a failure told to a reachable device is answered once', () async {
      // arrange
      final links =
          InMemoryLinks()
            ..reach(device)
            ..failNextOpen(device, ConnectFailureReason.pairingFailed);

      // act
      final failed = await links.open(device);
      final retried = await links.open(device);

      // assert
      expect(
        failed,
        const Left<ConnectionFailure, LinkId>(
          ConnectFailed(ConnectFailureReason.pairingFailed),
        ),
      );
      expect(retried, isA<Right<ConnectionFailure, LinkId>>());
    });

    test('an open with no delay still answers asynchronously', () {
      fakeAsync((async) {
        // arrange
        final links = InMemoryLinks()..reach(device);
        Either<ConnectionFailure, LinkId>? answer;

        // act
        links.open(device).then((value) => answer = value);
        async.flushMicrotasks();
        final beforeTimers = answer;
        async.elapse(Duration.zero);

        // assert
        expect(beforeTimers, isNull);
        expect(answer, isA<Right<ConnectionFailure, LinkId>>());
      });
    });
  });

  group('openDelay', () {
    test('an open stays in flight for openDelay', () {
      fakeAsync((async) {
        // arrange
        final links =
            InMemoryLinks()
              ..reach(device)
              ..openDelay = const Duration(seconds: 1);
        Either<ConnectionFailure, LinkId>? answer;

        // act
        links.open(device).then((value) => answer = value);
        async.elapse(const Duration(milliseconds: 999));
        final early = answer;
        async.elapse(const Duration(milliseconds: 1));

        // assert
        expect(early, isNull);
        expect(answer, isA<Right<ConnectionFailure, LinkId>>());
      });
    });

    test('an open told to fail answers its failure after openDelay', () {
      fakeAsync((async) {
        // arrange
        final links =
            InMemoryLinks()
              ..reach(device)
              ..openDelay = const Duration(seconds: 1)
              ..failNextOpen(device, ConnectFailureReason.deviceNotConnectable);
        Either<ConnectionFailure, LinkId>? answer;

        // act
        links.open(device).then((value) => answer = value);
        async.elapse(const Duration(milliseconds: 999));
        final early = answer;
        async.elapse(const Duration(milliseconds: 1));

        // assert
        expect(early, isNull);
        expect(
          answer,
          const Left<ConnectionFailure, LinkId>(
            ConnectFailed(ConnectFailureReason.deviceNotConnectable),
          ),
        );
      });
    });

    test(
      'an open whose delay outlasts its timeout times out at the timeout',
      () {
        fakeAsync((async) {
          // arrange
          final links =
              InMemoryLinks()
                ..reach(device)
                ..openDelay = const Duration(seconds: 2);
          Either<ConnectionFailure, LinkId>? answer;

          // act
          links
              .open(device, timeout: const Duration(seconds: 1))
              .then((value) => answer = value);
          async.elapse(const Duration(seconds: 1));

          // assert
          expect(
            answer,
            const Left<ConnectionFailure, LinkId>(
              ConnectFailed(ConnectFailureReason.timeout),
            ),
          );
        });
      },
    );

    test('an open whose delay equals its timeout links', () {
      fakeAsync((async) {
        // arrange
        final links =
            InMemoryLinks()
              ..reach(device)
              ..openDelay = const Duration(seconds: 1);
        Either<ConnectionFailure, LinkId>? answer;

        // act
        links
            .open(device, timeout: const Duration(seconds: 1))
            .then((value) => answer = value);
        async.elapse(const Duration(seconds: 1));

        // assert
        expect(answer, isA<Right<ConnectionFailure, LinkId>>());
      });
    });

    test('an open that timed out leaves no link behind', () {
      fakeAsync((async) {
        // arrange
        final links =
            InMemoryLinks()
              ..reach(device)
              ..openDelay = const Duration(seconds: 2);
        links.open(device, timeout: const Duration(seconds: 1));
        async.elapse(const Duration(seconds: 2));
        links.openDelay = Duration.zero;
        Either<ConnectionFailure, LinkId>? answer;

        // act
        links.open(device).then((value) => answer = value);
        async.elapse(Duration.zero);

        // assert
        expect(answer, Right<ConnectionFailure, LinkId>(LinkId(device.value)));
      });
    });
  });

  group('closeDelay', () {
    test('a close stays in flight for closeDelay', () {
      fakeAsync((async) {
        // arrange
        final links =
            InMemoryLinks()
              ..reach(device)
              ..closeDelay = const Duration(seconds: 1);
        late LinkId id;
        links.open(device).then((value) => id = (value as Right).value);
        async.elapse(Duration.zero);
        Either<ConnectionFailure, void>? answer;

        // act
        links.close(id).then((value) => answer = value);
        async.elapse(const Duration(milliseconds: 999));
        final early = answer;
        async.elapse(const Duration(milliseconds: 1));

        // assert
        expect(early, isNull);
        expect(answer, const Right<ConnectionFailure, void>(null));
      });
    });

    test('a close told to fail answers its failure after closeDelay', () {
      fakeAsync((async) {
        // arrange
        final links =
            InMemoryLinks()
              ..reach(device)
              ..closeDelay = const Duration(seconds: 1);
        late LinkId id;
        links.open(device).then((value) => id = (value as Right).value);
        async.elapse(Duration.zero);
        links.failNextClose(device);
        Either<ConnectionFailure, void>? answer;

        // act
        links.close(id).then((value) => answer = value);
        async.elapse(const Duration(milliseconds: 999));
        final early = answer;
        async.elapse(const Duration(milliseconds: 1));

        // assert
        expect(early, isNull);
        expect(answer, isA<Left<ConnectionFailure, void>>());
      });
    });

    test('a close in flight when its link drops leaves the device\'s newer '
        'link open', () {
      fakeAsync((async) {
        // arrange
        final links =
            InMemoryLinks()
              ..reach(device)
              ..closeDelay = const Duration(seconds: 1);
        late LinkId old;
        links.open(device).then((value) => old = (value as Right).value);
        async.elapse(Duration.zero);
        links.close(old).ignore();
        links.drop(device);
        late LinkId newer;
        links.open(device).then((value) => newer = (value as Right).value);
        async.elapse(Duration.zero);
        final reports = <LinkReport>[];
        var done = false;
        links.reportsOf(newer).listen(reports.add, onDone: () => done = true);

        // act
        async.elapse(const Duration(seconds: 1));
        links.report(device, LinkReport.disconnecting);
        async.flushMicrotasks();

        // assert
        expect(reports, [LinkReport.disconnecting]);
        expect(done, isFalse);
      });
    });

    test('a close of a link that already dropped answers success', () async {
      // arrange
      final links = InMemoryLinks()..reach(device);
      final id =
          (await links.open(device) as Right<ConnectionFailure, LinkId>).value;
      links
        ..drop(device)
        ..failNextClose(device);

      // act
      final answer = await links.close(id);

      // assert
      expect(answer, const Right<ConnectionFailure, void>(null));
    });
  });

  group('reports', () {
    test('a report told to a linked device reaches its link', () async {
      // arrange
      final links = InMemoryLinks()..reach(device);
      final id =
          (await links.open(device) as Right<ConnectionFailure, LinkId>).value;
      final reports = links.reportsOf(id);

      // act
      links
        ..report(device, LinkReport.disconnecting)
        ..drop(device);

      // assert
      await expectLater(
        reports,
        emitsInOrder([
          LinkReport.disconnecting,
          LinkReport.disconnected,
          emitsDone,
        ]),
      );
    });

    test('a closed link ends its reports with nothing more said', () async {
      // arrange
      final links = InMemoryLinks()..reach(device);
      final id =
          (await links.open(device) as Right<ConnectionFailure, LinkId>).value;

      // act
      await links.close(id);

      // assert
      await expectLater(links.reportsOf(id), emitsDone);
    });

    test('after a drop, the next open answers the same id, since the '
        'platforms name a link by its device', () async {
      // arrange
      final links = InMemoryLinks()..reach(device);
      final first = await links.open(device);
      links.drop(device);

      // act
      final answer = await links.open(device);

      // assert
      expect(answer, first);
    });

    test('a late close of an ended link\'s id reaches its successor, which '
        'is why the port forbids using an ended link\'s id', () async {
      // arrange
      final links = InMemoryLinks()..reach(device);
      final id =
          (await links.open(device) as Right<ConnectionFailure, LinkId>).value;
      links.drop(device);
      await links.open(device);
      final successorReports = links.reportsOf(id);

      // act
      await links.close(id);

      // assert
      await expectLater(successorReports, emitsDone);
      expect(links.closesAsked(device), 1);
    });
  });

  group('counters', () {
    test('opens and closes are counted per device', () async {
      // arrange
      final links =
          InMemoryLinks()
            ..reach(device)
            ..reach(other);

      // act
      final id =
          (await links.open(device) as Right<ConnectionFailure, LinkId>).value;
      await links.open(device);
      await links.open(other);
      await links.close(id);

      // assert
      expect(
        [
          links.opensAsked(device),
          links.opensAsked(other),
          links.closesAsked(device),
          links.closesAsked(other),
        ],
        [2, 1, 1, 0],
      );
    });

    test('each open\'s timeout is kept, in order', () async {
      // arrange
      final links = InMemoryLinks()..reach(device);

      // act
      await links.open(device, timeout: const Duration(seconds: 3));
      await links.open(device);

      // assert
      expect(links.openTimeouts, [const Duration(seconds: 3), null]);
    });
  });
}
