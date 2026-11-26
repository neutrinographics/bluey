import 'package:bluey/src/features/connection/application/borrow_link.dart';
import 'package:bluey/src/features/connection/application/connect_device.dart';
import 'package:bluey/src/features/connection/application/link_registry.dart';
import 'package:bluey/src/features/connection/domain/connection_event.dart';
import 'package:bluey/src/features/connection/domain/connection_failure.dart';
import 'package:bluey/src/shared/domain/device_address.dart';
import 'package:bluey/src/shared/domain/either.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../fixtures/either_results.dart';
import '../../../fixtures/features/connection/application/ports/in_memory_links.dart';
import '../../../fixtures/shared/application/recording_event_publisher.dart';
import '../../../fixtures/shared/application/recording_log.dart';

const device = DeviceAddress('AA:BB:CC:DD:EE:01');
const success = Right<ConnectionFailure, void>(null);

void main() {
  late InMemoryLinks links;
  late RecordingEventPublisher events;
  late BorrowLink borrow;
  late ConnectDevice connect;

  setUp(() {
    links = InMemoryLinks()..reach(device);
    events = RecordingEventPublisher();
    final registry = LinkRegistry(
      links: links,
      events: events,
      log: RecordingLog(),
    );
    borrow = BorrowLink(registry);
    connect = ConnectDevice(registry);
  });

  Future<BorrowedLink> borrowed() async =>
      rightOf(await borrow.run(const BorrowLinkRequest(device: device)));

  group('giving back', () {
    test('giving back a link only the borrower uses closes it', () async {
      // arrange
      final borrowedLink = await borrowed();

      // act
      final answer = await borrowedLink.giveBack();

      // assert
      expect(answer, success);
      expect(links.closesAsked(device), 1);
      expect(borrowedLink.session.link.hasEnded, isTrue);
    });

    test('a give-back after the app connected leaves the link', () async {
      // arrange
      final borrowedLink = await borrowed();
      final app = rightOf(
        await connect.run(const ConnectDeviceRequest(device: device)),
      );

      // act
      await borrowedLink.giveBack();

      // assert
      expect(identical(app, borrowedLink.session), isTrue);
      expect(links.closesAsked(device), 0);
      expect(app.link.isUp, isTrue);
    });

    test('borrowing the app\'s link and giving it back leaves it', () async {
      // arrange
      final app = rightOf(
        await connect.run(const ConnectDeviceRequest(device: device)),
      );
      final borrowedLink = await borrowed();

      // act
      final answer = await borrowedLink.giveBack();

      // assert
      expect(answer, success);
      expect(identical(app, borrowedLink.session), isTrue);
      expect(links.opensAsked(device), 1);
      expect(links.closesAsked(device), 0);
      expect(app.link.isUp, isTrue);
    });

    test('only the first give-back takes effect', () async {
      // arrange
      final borrowedLink = await borrowed();

      // act
      final first = borrowedLink.giveBack();
      final second = borrowedLink.giveBack();
      final answers = await Future.wait([first, second]);

      // assert
      expect(answers, [success, success]);
      expect(links.closesAsked(device), 1);
      expect(borrowedLink.session.link.hasEnded, isTrue);
    });
  });

  group('keeping', () {
    test(
      'keep hands the link to the app, and a later give-back does nothing',
      () async {
        // arrange
        final borrowedLink = await borrowed();

        // act
        borrowedLink.keep();
        final answer = await borrowedLink.giveBack();

        // assert
        expect(answer, success);
        expect(links.closesAsked(device), 0);
        expect(borrowedLink.session.link.isUp, isTrue);
        final other = await borrowed();
        await other.giveBack();
        expect(links.closesAsked(device), 0);
        expect(borrowedLink.session.link.isUp, isTrue);
      },
    );
  });

  group('announcing', () {
    test('a borrower\'s open is announced like any other', () async {
      // act
      await borrowed();

      // assert
      expect(events.events, [isA<ConnectingEvent>(), isA<ConnectedEvent>()]);
    });
  });
}
