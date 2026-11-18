import 'package:bluey/src/features/connection/application/ports/links.dart';
import 'package:bluey/src/features/connection/domain/connection_failure.dart';
import 'package:bluey/src/features/connection/domain/link_end.dart';
import 'package:bluey/src/features/connection/domain/link_id.dart';
import 'package:bluey/src/features/connection/domain/link_input.dart';
import 'package:bluey/src/shared/domain/device_address.dart';
import 'package:bluey/src/shared/domain/either.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a run of [linksContract] needs from the [Links] it holds to account:
/// a way to put the radio into each situation the contract describes.
///
/// The in-memory double is its own harness; the platform adapter's harness
/// drives `FakeBlueyPlatform`, so both are held to the same promises.
abstract class LinksHarness {
  /// The port under contract.
  Links get links;

  /// Makes [device] one a link can be opened to.
  void reach(DeviceAddress device);

  /// Makes the next open to [device] fail for [reason].
  void failNextOpen(DeviceAddress device, ConnectFailureReason reason);

  /// Makes the next close of [device]'s link fail.
  void failNextClose(DeviceAddress device);

  /// The peer drops [device]'s link.
  void drop(DeviceAddress device);

  /// The adapter leaves `on` for [outage].
  void outage(RadioOutage outage);
}

const _device = DeviceAddress('AA:BB:CC:DD:EE:01');

/// The promises every [Links] keeps, which the application layer's units are
/// written against, so a unit tested over the double behaves the same over
/// the platform.
void linksContract(String name, LinksHarness Function() create) {
  group(name, () {
    late LinksHarness h;

    setUp(() => h = create());

    Future<LinkId> openLink() async {
      h.reach(_device);
      return (await h.links.open(
        _device,
      )).fold((failure) => fail('the open failed: $failure'), (id) => id);
    }

    test('open answers a link id for a reachable device', () async {
      // arrange
      h.reach(_device);

      // act
      final answer = await h.links.open(_device);

      // assert
      expect(answer, isA<Right<ConnectionFailure, LinkId>>());
    });

    test(
      'open answers why an unreachable device could not be linked',
      () async {
        // arrange
        h.failNextOpen(_device, ConnectFailureReason.deviceNotFound);

        // act
        final answer = await h.links.open(_device);

        // assert
        expect(
          answer,
          const Left<ConnectionFailure, LinkId>(
            ConnectFailed(ConnectFailureReason.deviceNotFound),
          ),
        );
      },
    );

    // A platform reports the close it was asked for, the in-memory radio
    // says nothing: either way nothing but that close may come before the end.
    test('a closed link\'s reports end', () async {
      // arrange
      final id = await openLink();

      // act
      final answer = await h.links.close(id);

      // assert
      expect(answer, const Right<ConnectionFailure, void>(null));
      await expectLater(
        h.links.reportsOf(id),
        emitsInOrder([mayEmit(LinkReport.disconnected), emitsDone]),
      );
    });

    test(
      'a drop is reported as disconnected, and then the reports end',
      () async {
        // arrange
        final id = await openLink();
        final reports = h.links.reportsOf(id);

        // act
        h.drop(_device);

        // assert
        await expectLater(
          reports,
          emitsInOrder([LinkReport.disconnected, emitsDone]),
        );
      },
    );

    test('a report that arrives before the listener is kept', () async {
      // arrange
      final id = await openLink();
      h.drop(_device);
      await pumpEventQueue();

      // act
      final reports = h.links.reportsOf(id);

      // assert
      await expectLater(
        reports,
        emitsInOrder([LinkReport.disconnected, emitsDone]),
      );
    });

    test('a second open for a linked device answers the same id and leaves the '
        'first reports attached', () async {
      // arrange
      final first = await openLink();
      final reports = h.links.reportsOf(first);

      // act
      final second = await h.links.open(_device);
      h.drop(_device);

      // assert
      expect(second, Right<ConnectionFailure, LinkId>(first));
      await expectLater(
        reports,
        emitsInOrder([LinkReport.disconnected, emitsDone]),
      );
    });

    test(
      'a failed close answers a failure and leaves the reports going',
      () async {
        // arrange
        final id = await openLink();
        final reports = h.links.reportsOf(id);
        h.failNextClose(_device);

        // act
        final answer = await h.links.close(id);
        h.drop(_device);

        // assert
        expect(answer, isA<Left<ConnectionFailure, void>>());
        await expectLater(
          reports,
          emitsInOrder([LinkReport.disconnected, emitsDone]),
        );
      },
    );

    test('an outage reaches every listener in Connection\'s words', () async {
      // arrange
      final first = <RadioOutage>[];
      final second = <RadioOutage>[];
      final subscriptions = [
        h.links.outages.listen(first.add),
        h.links.outages.listen(second.add),
      ];

      // act
      h.outage(RadioOutage.off);
      await pumpEventQueue();

      // assert
      expect(
        [first, second],
        [
          [RadioOutage.off],
          [RadioOutage.off],
        ],
      );
      for (final subscription in subscriptions) {
        subscription.cancel().ignore();
      }
    });
  });
}
