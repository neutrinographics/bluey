import 'package:bluey/src/features/connection/domain/link.dart';
import 'package:bluey/src/features/connection/domain/link_id.dart';
import 'package:bluey/src/features/connection/domain/link_input.dart';
import 'package:bluey/src/features/connection/domain/live_links.dart';
import 'package:bluey/src/shared/domain/device_address.dart';
import 'package:flutter_test/flutter_test.dart';

const device = DeviceAddress('AA:BB:CC:DD:EE:01');
const other = DeviceAddress('AA:BB:CC:DD:EE:02');
final at = DateTime.utc(2026, 11, 26, 10);
final up = Link.open(id: const LinkId('L1'), device: device, at: at).link;
final closing = up.on(const DisconnectRequested(), at: at).link;
final ended = up.on(const RadioReported(LinkReport.disconnected), at: at).link;

LiveLinks heldBy(LinkUser user) =>
    const LiveLinks.empty().admit(device, user, link: null).$1.opened(device);

void main() {
  group('a device with no link', () {
    test('the app opens a link to a device that has none', () {
      // arrange
      const links = LiveLinks.empty();

      // act
      final (after, admission) = links.admit(device, LinkUser.app, link: null);

      // assert
      expect(admission, Admission.open);
      expect(
        (
          after.isOpening(device),
          after.appHolds(device),
          after.borrowersOf(device),
        ),
        (true, true, 0),
      );
    });

    test('a borrower opens a link with one borrower', () {
      // arrange
      const links = LiveLinks.empty();

      // act
      final (after, admission) = links.admit(
        device,
        LinkUser.borrower,
        link: null,
      );

      // assert
      expect(admission, Admission.open);
      expect(
        (
          after.isOpening(device),
          after.appHolds(device),
          after.borrowersOf(device),
        ),
        (true, false, 1),
      );
    });
  });

  group('an open in flight, or a link closing', () {
    test('a second caller waits while an open is in flight', () {
      // arrange
      final (links, _) = const LiveLinks.empty().admit(
        device,
        LinkUser.borrower,
        link: null,
      );

      // act
      final (after, admission) = links.admit(device, LinkUser.app, link: null);

      // assert
      expect(admission, Admission.wait);
      expect(after.appHolds(device), isFalse);
    });

    test('a caller waits while the link is closing', () {
      // arrange
      final links = heldBy(LinkUser.app);

      // act
      final (_, admission) = links.admit(
        device,
        LinkUser.borrower,
        link: closing,
      );

      // assert
      expect(admission, Admission.wait);
    });

    test('a caller waits on a link that ended and is not yet forgotten', () {
      // arrange
      final links = heldBy(LinkUser.app);

      // act
      final (_, admission) = links.admit(device, LinkUser.app, link: ended);

      // assert
      expect(admission, Admission.wait);
    });

    test('the attempt that came up is no longer opening', () {
      // arrange
      final (links, _) = const LiveLinks.empty().admit(
        device,
        LinkUser.app,
        link: null,
      );

      // act
      final after = links.opened(device);

      // assert
      expect(after.isOpening(device), isFalse);
    });
  });

  group('a link that is up', () {
    test('the app reuses a link a borrower has, and now holds it', () {
      // arrange
      final links = heldBy(LinkUser.borrower);

      // act
      final (after, admission) = links.admit(device, LinkUser.app, link: up);

      // assert
      expect(admission, Admission.reuse);
      expect((after.appHolds(device), after.borrowersOf(device)), (true, 1));
    });

    test('a borrower reuses the app\'s link as one more borrower', () {
      // arrange
      final links = heldBy(LinkUser.app);

      // act
      final (after, admission) = links.admit(
        device,
        LinkUser.borrower,
        link: up,
      );

      // assert
      expect(admission, Admission.reuse);
      expect((after.appHolds(device), after.borrowersOf(device)), (true, 1));
    });

    test('a device whose link came up must be asked about with its link', () {
      // arrange
      final links = heldBy(LinkUser.app);

      // act
      void askWithoutTheLink() => links.admit(device, LinkUser.app, link: null);

      // assert
      expect(askWithoutTheLink, throwsStateError);
    });
  });

  group('giving back and keeping', () {
    test('a give-back by the only user closes the link', () {
      // arrange
      final links = heldBy(LinkUser.borrower);

      // act
      final (_, answer) = links.giveBack(device);

      // assert
      expect(answer, AfterGiveBack.closeTheLink);
    });

    test('a give-back leaves a link another borrower still uses', () {
      // arrange
      final (links, _) = heldBy(
        LinkUser.borrower,
      ).admit(device, LinkUser.borrower, link: up);

      // act
      final (afterFirst, first) = links.giveBack(device);
      final (afterSecond, second) = afterFirst.giveBack(device);

      // assert
      expect(
        (first, afterFirst.borrowersOf(device)),
        (AfterGiveBack.leaveIt, 1),
      );
      expect(
        (second, afterSecond.borrowersOf(device)),
        (AfterGiveBack.closeTheLink, 0),
      );
    });

    test('a give-back after the app took hold leaves the link', () {
      // arrange
      final (links, _) = heldBy(
        LinkUser.borrower,
      ).admit(device, LinkUser.app, link: up);

      // act
      final (after, answer) = links.giveBack(device);

      // assert
      expect(answer, AfterGiveBack.leaveIt);
      expect((after.appHolds(device), after.borrowersOf(device)), (true, 0));
    });

    test('keep hands the link to the app', () {
      // arrange
      final links = heldBy(LinkUser.borrower);

      // act
      final after = links.keep(device);

      // assert
      expect((after.appHolds(device), after.borrowersOf(device)), (true, 0));
    });

    test('giving back or keeping an unknown device changes nothing', () {
      // arrange
      const links = LiveLinks.empty();

      // act
      final (afterGiveBack, answer) = links.giveBack(device);
      final afterKeep = links.keep(device);

      // assert
      expect(answer, AfterGiveBack.leaveIt);
      expect(afterGiveBack.borrowersOf(device), 0);
      expect(afterKeep.appHolds(device), isFalse);
    });
  });

  group('a give-back or keep with no borrower', () {
    test('giving back a link no borrower uses is a programming error', () {
      // arrange
      final links = heldBy(LinkUser.app);

      // act
      void giveBackUnborrowed() => links.giveBack(device);

      // assert
      expect(giveBackUnborrowed, throwsStateError);
    });

    test('keeping a link no borrower uses is a programming error', () {
      // arrange
      final links = heldBy(LinkUser.app);

      // act
      void keepUnborrowed() => links.keep(device);

      // assert
      expect(keepUnborrowed, throwsStateError);
    });
  });

  group('forgetting and other devices', () {
    test('forget removes the device, so the next caller opens', () {
      // arrange
      final links = heldBy(LinkUser.app).forget(device);

      // act
      final (_, admission) = links.admit(device, LinkUser.app, link: null);

      // assert
      expect(admission, Admission.open);
    });

    test('devices do not affect each other', () {
      // arrange
      final links = heldBy(LinkUser.app);

      // act
      final (after, admission) = links.admit(other, LinkUser.app, link: null);

      // assert
      expect(admission, Admission.open);
      expect((after.isOpening(device), after.appHolds(device)), (false, true));
    });

    test('an unknown device is not opening, held or borrowed', () {
      // arrange
      const links = LiveLinks.empty();

      // act
      final answers = (
        links.isOpening(device),
        links.appHolds(device),
        links.borrowersOf(device),
      );

      // assert
      expect(answers, (false, false, 0));
    });
  });
}
