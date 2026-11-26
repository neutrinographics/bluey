import 'package:bluey/src/api/connection/connections.dart';
import 'package:bluey/src/features/connection/application/connect_device.dart';
import 'package:bluey/src/features/connection/application/link_registry.dart';
import 'package:bluey/src/features/connection/application/link_session.dart';
import 'package:bluey/src/features/connection/domain/link_id.dart';
import 'package:bluey/src/shared/domain/device_address.dart';
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
  late List<LinkSession> presented;
  late Connections connections;

  setUp(() {
    links = InMemoryLinks()..reach(device);
    connect = ConnectDevice(
      LinkRegistry(
        links: links,
        events: RecordingEventPublisher(),
        log: RecordingLog(),
      ),
    );
    presented = [];
    connections = Connections(
      present: (session) {
        presented.add(session);
        return StubConnection(session);
      },
    );
  });

  Future<LinkSession> connected() async =>
      rightOf(await connect.run(const ConnectDeviceRequest(device: device)));

  group('presenting', () {
    test('one session is presented once', () async {
      // arrange
      final session = await connected();

      // act
      final first = connections.of(session);
      final second = connections.of(session);

      // assert
      expect(identical(first, second), isTrue);
      expect(presented, [session]);
    });

    test('two sessions are two Connections', () async {
      // arrange
      final earlier = await connected();
      rightOf(await earlier.disconnect());
      final later = await connected();

      // act
      final first = connections.of(earlier);
      final second = connections.of(later);

      // assert
      expect(identical(first, second), isFalse);
      expect((first as StubConnection).session, same(earlier));
      expect((second as StubConnection).session, same(later));
      expect(presented, [earlier, later]);
    });
  });

  group('the link id behind a Connection', () {
    test(
      'answers the link id behind a Connection it made, after the link ended too',
      () async {
        // arrange
        final session = await connected();
        final connection = connections.of(session);
        final whileUp = connections.linkIdOf(connection);
        links.drop(device);
        await pumpEventQueue();

        // act
        final afterEnd = connections.linkIdOf(connection);

        // assert
        expect(session.link.hasEnded, isTrue);
        expect(whileUp, LinkId(device.value));
        expect(afterEnd, LinkId(device.value));
      },
    );

    test('answers null for a Connection it did not make', () async {
      // arrange
      final session = await connected();
      connections.of(session);
      final stranger = StubConnection(session);

      // act
      final linkId = connections.linkIdOf(stranger);

      // assert
      expect(linkId, isNull);
    });
  });
}
