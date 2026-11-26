import 'package:bluey/src/features/connection/domain/live_link.dart';
import 'package:bluey/src/features/connection/domain/live_links.dart';
import 'package:bluey/src/shared/domain/device_address.dart';
import 'package:flutter_test/flutter_test.dart';

const device = DeviceAddress('AA:BB:CC:DD:EE:01');
const other = DeviceAddress('AA:BB:CC:DD:EE:02');

final class TestLink implements LiveLink {
  @override
  bool isClosing = false;
}

LiveLinks<TestLink> heldBy(LinkUser user, TestLink link) {
  final links = LiveLinks<TestLink>()..admit(device, user);
  return links..opened(device, user, link);
}

/// Whether the app holds [link], read as a borrower joining and giving back
/// without closing it.
bool appHolds(LiveLinks<TestLink> links, TestLink link) {
  links.admit(device, LinkUser.borrower);
  return links.givenBack(device, link) == AfterGiveBack.leaveIt;
}

void main() {
  group('a device with no link', () {
    test('the app opens a link to a device that has none', () {
      // arrange
      final links = LiveLinks<TestLink>();

      // act
      final admission = links.admit(device, LinkUser.app);

      // assert
      expect(admission, isA<Open<TestLink>>());
    });

    test('a borrower opens a link with one borrower', () {
      // arrange
      final link = TestLink();
      final links = LiveLinks<TestLink>();

      // act
      final admission = links.admit(device, LinkUser.borrower);
      links.opened(device, LinkUser.borrower, link);

      // assert
      expect(admission, isA<Open<TestLink>>());
      expect(links.givenBack(device, link), AfterGiveBack.closeTheLink);
    });
  });

  group('an open in flight, or a link closing', () {
    test('a second caller waits while an open is in flight', () {
      // arrange
      final link = TestLink();
      final links = LiveLinks<TestLink>()..admit(device, LinkUser.borrower);

      // act
      final admission = links.admit(device, LinkUser.app);
      links.opened(device, LinkUser.borrower, link);

      // assert
      expect(admission, isA<Wait<TestLink>>());
      expect(links.givenBack(device, link), AfterGiveBack.closeTheLink);
    });

    test('a caller waits while the link is closing', () {
      // arrange
      final link = TestLink();
      final links = heldBy(LinkUser.app, link);
      link.isClosing = true;

      // act
      final admission = links.admit(device, LinkUser.borrower);

      // assert
      expect(admission, isA<Wait<TestLink>>());
    });

    test('a caller waits on a link that ended and is not yet forgotten', () {
      // arrange
      final ended = TestLink()..isClosing = true;
      final links = heldBy(LinkUser.app, ended);

      // act
      final admission = links.admit(device, LinkUser.app);

      // assert
      expect(admission, isA<Wait<TestLink>>());
    });

    test('the attempt that came up is reused by the next caller', () {
      // arrange
      final link = TestLink();
      final links = LiveLinks<TestLink>()..admit(device, LinkUser.app);

      // act
      links.opened(device, LinkUser.app, link);
      final admission = links.admit(device, LinkUser.borrower);

      // assert
      expect(admission, isA<Reuse<TestLink>>());
    });

    test('a borrower and the app both arriving while the link closes each '
        'wait, then one opens and the other reuses', () {
      // arrange
      final closing = TestLink();
      final links = heldBy(LinkUser.app, closing);
      closing.isClosing = true;
      final reopened = TestLink();

      // act
      final borrowerFirst = links.admit(device, LinkUser.borrower);
      final appFirst = links.admit(device, LinkUser.app);
      links.ended(device, closing);
      final borrowerAgain = links.admit(device, LinkUser.borrower);
      final appWhileOpening = links.admit(device, LinkUser.app);
      links.opened(device, LinkUser.borrower, reopened);
      final appAgain = links.admit(device, LinkUser.app);

      // assert
      expect(borrowerFirst, isA<Wait<TestLink>>());
      expect(appFirst, isA<Wait<TestLink>>());
      expect(borrowerAgain, isA<Open<TestLink>>());
      expect(appWhileOpening, isA<Wait<TestLink>>());
      expect(appAgain, isA<Reuse<TestLink>>());
      expect(identical((appAgain as Reuse<TestLink>).link, reopened), isTrue);
    });
  });

  group('a link that is up', () {
    test('the app reuses a link a borrower has, and now holds it', () {
      // arrange
      final link = TestLink();
      final links = heldBy(LinkUser.borrower, link);

      // act
      final admission = links.admit(device, LinkUser.app);

      // assert
      expect(identical((admission as Reuse<TestLink>).link, link), isTrue);
      expect(links.givenBack(device, link), AfterGiveBack.leaveIt);
      expect(appHolds(links, link), isTrue);
    });

    test('a borrower reuses the app\'s link as one more borrower', () {
      // arrange
      final link = TestLink();
      final links = heldBy(LinkUser.app, link);

      // act
      final admission = links.admit(device, LinkUser.borrower);

      // assert
      expect(identical((admission as Reuse<TestLink>).link, link), isTrue);
      expect(links.givenBack(device, link), AfterGiveBack.leaveIt);
      expect(appHolds(links, link), isTrue);
    });
  });

  group('giving back and keeping', () {
    test('a give-back by the only user closes the link', () {
      // arrange
      final link = TestLink();
      final links = heldBy(LinkUser.borrower, link);

      // act
      final answer = links.givenBack(device, link);

      // assert
      expect(answer, AfterGiveBack.closeTheLink);
    });

    test('a give-back leaves a link another borrower still uses', () {
      // arrange
      final link = TestLink();
      final links = heldBy(LinkUser.borrower, link)
        ..admit(device, LinkUser.borrower);

      // act
      final first = links.givenBack(device, link);
      final second = links.givenBack(device, link);

      // assert
      expect(first, AfterGiveBack.leaveIt);
      expect(second, AfterGiveBack.closeTheLink);
    });

    test('a give-back after the app took hold leaves the link', () {
      // arrange
      final link = TestLink();
      final links = heldBy(LinkUser.borrower, link)
        ..admit(device, LinkUser.app);

      // act
      final answer = links.givenBack(device, link);

      // assert
      expect(answer, AfterGiveBack.leaveIt);
      expect(() => links.givenBack(device, link), throwsStateError);
    });

    test('keep hands the link to the app', () {
      // arrange
      final link = TestLink();
      final links = heldBy(LinkUser.borrower, link);

      // act
      links.kept(device, link);

      // assert
      expect(() => links.givenBack(device, link), throwsStateError);
      expect(appHolds(links, link), isTrue);
    });

    test('giving back or keeping an unknown device changes nothing', () {
      // arrange
      final links = LiveLinks<TestLink>();

      // act
      final answer = links.givenBack(device, TestLink());
      links.kept(device, TestLink());

      // assert
      expect(answer, AfterGiveBack.leaveIt);
      expect(links.admit(device, LinkUser.app), isA<Open<TestLink>>());
    });

    test('an old link\'s give-back or keep leaves its successor alone', () {
      // arrange
      final old = TestLink();
      final successor = TestLink();
      final links =
          heldBy(LinkUser.borrower, old)
            ..ended(device, old)
            ..admit(device, LinkUser.borrower)
            ..opened(device, LinkUser.borrower, successor);

      // act
      final answer = links.givenBack(device, old);
      links.kept(device, old);

      // assert
      expect(answer, AfterGiveBack.leaveIt);
      expect(links.givenBack(device, successor), AfterGiveBack.closeTheLink);
    });
  });

  group('a give-back or keep with no borrower', () {
    test('giving back a link no borrower uses is a programming error', () {
      // arrange
      final link = TestLink();
      final links = heldBy(LinkUser.app, link);

      // act
      void giveBackUnborrowed() => links.givenBack(device, link);

      // assert
      expect(giveBackUnborrowed, throwsStateError);
    });

    test('keeping a link no borrower uses is a programming error', () {
      // arrange
      final link = TestLink();
      final links = heldBy(LinkUser.app, link);

      // act
      void keepUnborrowed() => links.kept(device, link);

      // assert
      expect(keepUnborrowed, throwsStateError);
    });
  });

  group('ending and other devices', () {
    test('an ended link is dropped, so the next caller opens', () {
      // arrange
      final link = TestLink();
      final links = heldBy(LinkUser.app, link);

      // act
      links.ended(device, link);

      // assert
      expect(links.admit(device, LinkUser.app), isA<Open<TestLink>>());
    });

    test('ended by an old holder leaves the new entry', () {
      // arrange
      final old = TestLink();
      final links = heldBy(LinkUser.app, old)..ended(device, old);
      final successor = TestLink();
      links
        ..admit(device, LinkUser.app)
        ..opened(device, LinkUser.app, successor);

      // act
      links.ended(device, old);

      // assert
      final admission = links.admit(device, LinkUser.borrower);
      expect(identical((admission as Reuse<TestLink>).link, successor), isTrue);
    });

    test('an old holder\'s end leaves an open in flight', () {
      // arrange
      final old = TestLink();
      final links =
          heldBy(LinkUser.app, old)
            ..ended(device, old)
            ..admit(device, LinkUser.app);

      // act
      links.ended(device, old);

      // assert
      expect(links.admit(device, LinkUser.borrower), isA<Wait<TestLink>>());
    });

    test('a failed open is dropped, so the next caller opens', () {
      // arrange
      final links = LiveLinks<TestLink>()..admit(device, LinkUser.app);

      // act
      links.notOpened(device);

      // assert
      expect(links.admit(device, LinkUser.app), isA<Open<TestLink>>());
    });

    test('devices do not affect each other', () {
      // arrange
      final links = heldBy(LinkUser.app, TestLink());

      // act
      final admission = links.admit(other, LinkUser.app);

      // assert
      expect(admission, isA<Open<TestLink>>());
      expect(links.admit(device, LinkUser.borrower), isA<Reuse<TestLink>>());
    });
  });
}
