import 'package:bluey/src/features/connection/domain/live_link.dart';
import 'package:bluey/src/features/connection/domain/live_links.dart';
import 'package:bluey/src/shared/domain/device_address.dart';
import 'package:flutter_test/flutter_test.dart';

const device = DeviceAddress('AA:BB:CC:DD:EE:01');
const other = DeviceAddress('AA:BB:CC:DD:EE:02');

/// A link the table holds; it begins opening, so it is not up.
final class TestLink implements LiveLink {
  @override
  bool isUp = false;
}

extension on LiveLinks<TestLink> {
  /// Admits [user] to [device]'s link, beginning [begun] (a new link when
  /// null) only if the table says to open.
  Admission<TestLink> ask(
    LinkUser user, {
    DeviceAddress at = device,
    TestLink? begun,
  }) => admit(at, user, begin: () => begun ?? TestLink());
}

/// A table whose device's link [link] was opened by [user] and is up.
LiveLinks<TestLink> heldBy(LinkUser user, TestLink link) {
  final links = LiveLinks<TestLink>()..ask(user, begun: link);
  link.isUp = true;
  return links;
}

/// Whether the app holds [link], read as a borrower joining and giving back
/// without closing it.
bool appHolds(LiveLinks<TestLink> links, TestLink link) {
  links.ask(LinkUser.borrower);
  return links.givenBack(device, link) == AfterGiveBack.leaveIt;
}

void main() {
  group('a device with no link', () {
    test('the first caller is handed the link it must open', () {
      // arrange
      final link = TestLink();
      final links = LiveLinks<TestLink>();

      // act
      final admission = links.ask(LinkUser.app, begun: link);

      // assert
      expect(identical((admission as Open<TestLink>).link, link), isTrue);
    });

    test('the opener uses the link from its beginning', () {
      // arrange
      final link = TestLink();
      final links = LiveLinks<TestLink>()..ask(LinkUser.borrower, begun: link);

      // act
      link.isUp = true;
      final answer = links.givenBack(device, link);

      // assert
      expect(answer, AfterGiveBack.closeTheLink);
    });
  });

  group('an open in flight, or a link closing', () {
    test('a link that is opening makes the next caller wait, and begins '
        'nothing', () {
      // arrange
      final link = TestLink();
      final links = LiveLinks<TestLink>()..ask(LinkUser.borrower, begun: link);
      var begun = 0;

      // act
      final admission = links.admit(
        device,
        LinkUser.app,
        begin: () {
          begun++;
          return TestLink();
        },
      );
      link.isUp = true;

      // assert
      expect(admission, isA<Wait<TestLink>>());
      expect(begun, 0);
      expect(links.givenBack(device, link), AfterGiveBack.closeTheLink);
    });

    test('a caller waits while the link is closing', () {
      // arrange
      final link = TestLink();
      final links = heldBy(LinkUser.app, link);
      link.isUp = false;

      // act
      final admission = links.ask(LinkUser.borrower);

      // assert
      expect(admission, isA<Wait<TestLink>>());
    });

    test('a caller waits on a link that ended and is not yet forgotten', () {
      // arrange
      final ended = TestLink();
      final links = heldBy(LinkUser.app, ended);
      ended.isUp = false;

      // act
      final admission = links.ask(LinkUser.app);

      // assert
      expect(admission, isA<Wait<TestLink>>());
    });

    test('the attempt that came up is reused by the next caller, which '
        'begins nothing', () {
      // arrange
      final link = TestLink();
      final links = LiveLinks<TestLink>()..ask(LinkUser.app, begun: link);
      var begun = 0;

      // act
      link.isUp = true;
      final admission = links.admit(
        device,
        LinkUser.borrower,
        begin: () {
          begun++;
          return TestLink();
        },
      );

      // assert
      expect(identical((admission as Reuse<TestLink>).link, link), isTrue);
      expect(begun, 0);
    });

    test('a borrower and the app both arriving while the link closes each '
        'wait, then one opens and the other reuses', () {
      // arrange
      final closing = TestLink();
      final links = heldBy(LinkUser.app, closing);
      closing.isUp = false;
      final reopened = TestLink();

      // act
      final borrowerFirst = links.ask(LinkUser.borrower);
      final appFirst = links.ask(LinkUser.app);
      links.ended(device, closing);
      final borrowerAgain = links.ask(LinkUser.borrower, begun: reopened);
      final appWhileOpening = links.ask(LinkUser.app);
      reopened.isUp = true;
      final appAgain = links.ask(LinkUser.app);

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
      final admission = links.ask(LinkUser.app);

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
      final admission = links.ask(LinkUser.borrower);

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
      final links = heldBy(LinkUser.borrower, link)..ask(LinkUser.borrower);

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
      final links = heldBy(LinkUser.borrower, link)..ask(LinkUser.app);

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
      expect(links.ask(LinkUser.app), isA<Open<TestLink>>());
    });

    test('an old link\'s give-back or keep leaves its successor alone', () {
      // arrange
      final old = TestLink();
      final successor = TestLink()..isUp = true;
      final links =
          heldBy(LinkUser.borrower, old)
            ..ended(device, old)
            ..ask(LinkUser.borrower, begun: successor);

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
      expect(links.ask(LinkUser.app), isA<Open<TestLink>>());
    });

    test('ended by an old holder leaves the new entry', () {
      // arrange
      final old = TestLink();
      final links = heldBy(LinkUser.app, old)..ended(device, old);
      final successor = TestLink()..isUp = true;
      links.ask(LinkUser.app, begun: successor);

      // act
      links.ended(device, old);

      // assert
      final admission = links.ask(LinkUser.borrower);
      expect(identical((admission as Reuse<TestLink>).link, successor), isTrue);
    });

    test('an old holder\'s end leaves an open in flight', () {
      // arrange
      final old = TestLink();
      final links =
          heldBy(LinkUser.app, old)
            ..ended(device, old)
            ..ask(LinkUser.app);

      // act
      links.ended(device, old);

      // assert
      expect(links.ask(LinkUser.borrower), isA<Wait<TestLink>>());
    });

    test('a failed open drops only the link that failed', () {
      // arrange
      final failed = TestLink();
      final links = LiveLinks<TestLink>()..ask(LinkUser.app, begun: failed);

      // act
      links.notOpened(device, TestLink());
      final whileTheOtherFails = links.ask(LinkUser.app);
      links.notOpened(device, failed);

      // assert
      expect(whileTheOtherFails, isA<Wait<TestLink>>());
      expect(links.ask(LinkUser.app), isA<Open<TestLink>>());
    });

    test('devices do not affect each other', () {
      // arrange
      final links = heldBy(LinkUser.app, TestLink());

      // act
      final admission = links.ask(LinkUser.app, at: other);

      // assert
      expect(admission, isA<Open<TestLink>>());
      expect(links.ask(LinkUser.borrower), isA<Reuse<TestLink>>());
    });
  });
}
