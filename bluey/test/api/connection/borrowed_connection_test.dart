import 'package:clock/clock.dart';
import 'package:bluey/src/api/connection/borrowed_connection.dart';
import 'package:bluey/src/api/connection/connections.dart';
import 'package:bluey/src/features/connection/application/borrow_link.dart';
import 'package:bluey/src/features/connection/application/connect_device.dart';
import 'package:bluey/src/features/connection/application/link_registry.dart';
import 'package:bluey/src/features/connection/domain/connection_failure.dart';
import 'package:bluey/src/shared/domain/device_address.dart';
import 'package:bluey/src/shared/exceptions.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/api/connection/stub_connection.dart';
import '../../fixtures/either_results.dart';
import '../../fixtures/features/connection/application/ports/in_memory_links.dart';
import '../../fixtures/shared/application/recording_event_publisher.dart';
import '../../fixtures/shared/application/recording_log.dart';

const device = DeviceAddress('AA:BB:CC:DD:EE:01');

void main() {
  late InMemoryLinks links;
  late ConnectDevice connect;
  late Connections connections;
  late BorrowConnection borrow;

  setUp(() {
    links = InMemoryLinks()..reach(device);
    final registry = LinkRegistry(
      links: links,
      events: RecordingEventPublisher(),
      log: RecordingLog(),
      now: clock.now,
    );
    connect = ConnectDevice(registry);
    connections = Connections(present: StubConnection.new);
    borrow = borrowingThrough(
      borrowLink: BorrowLink(registry),
      connections: connections,
    );
  });

  group('borrowing', () {
    test('a borrow presents the session\'s Connection', () async {
      // arrange
      final borrowed = await borrow(device);

      // act
      final app = rightOf(
        await connect.run(const ConnectDeviceRequest(device: device)),
      );

      // assert
      expect(identical(borrowed.connection, connections.of(app)), isTrue);
    });

    test(
      'a borrow that cannot open the link throws the translated exception',
      () async {
        // arrange
        links.failNextOpen(device, ConnectFailureReason.deviceNotFound);

        // act
        final borrowing = borrow(device);

        // assert
        await expectLater(
          borrowing,
          throwsA(
            isA<ConnectionException>()
                .having((e) => e.deviceAddress, 'deviceAddress', device)
                .having(
                  (e) => e.reason,
                  'reason',
                  ConnectionFailureReason.deviceNotFound,
                ),
          ),
        );
      },
    );
  });

  group('giving back', () {
    test(
      'giving a borrowed Connection back closes a link only the borrower used',
      () async {
        // arrange
        final borrowed = await borrow(device);

        // act
        await borrowed.giveBack();

        // assert
        expect(links.closesAsked(device), 1);
        final session = (borrowed.connection as StubConnection).session;
        expect(session.link.hasEnded, isTrue);
      },
    );

    test('a give-back whose close fails throws', () async {
      // arrange
      final borrowed = await borrow(device);
      links.failNextClose(device);

      // act
      final givingBack = borrowed.giveBack();

      // assert
      await expectLater(givingBack, throwsA(isA<BlueyPlatformException>()));
      final session = (borrowed.connection as StubConnection).session;
      expect(session.link.isUp, isTrue);
    });
  });

  group('keeping', () {
    test('a kept borrow leaves the link to the app', () async {
      // arrange
      final borrowed = await borrow(device);

      // act
      borrowed.keep();
      await borrowed.giveBack();

      // assert
      expect(links.closesAsked(device), 0);
      final session = (borrowed.connection as StubConnection).session;
      expect(session.link.isUp, isTrue);
    });
  });
}
