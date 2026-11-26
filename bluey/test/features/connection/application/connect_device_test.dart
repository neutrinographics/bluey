import 'package:clock/clock.dart';
import 'package:bluey/src/features/connection/application/borrow_link.dart';
import 'package:bluey/src/features/connection/application/connect_device.dart';
import 'package:bluey/src/features/connection/application/link_registry.dart';
import 'package:bluey/src/shared/domain/device_address.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../fixtures/either_results.dart';
import '../../../fixtures/features/connection/application/ports/in_memory_links.dart';
import '../../../fixtures/features/connection/recording_link_events.dart';
import '../../../fixtures/shared/application/recording_log.dart';

const device = DeviceAddress('AA:BB:CC:DD:EE:01');

void main() {
  late InMemoryLinks links;
  late LinkRegistry registry;
  late ConnectDevice connect;

  setUp(() {
    links = InMemoryLinks()..reach(device);
    registry = LinkRegistry(
      links: links,
      events: RecordingLinkEvents(),
      log: RecordingLog(),
      now: clock.now,
    );
    connect = ConnectDevice(registry);
  });

  group('connecting', () {
    test('answers the session of a new link, held by the app', () async {
      // act
      final session = rightOf(
        await connect.run(const ConnectDeviceRequest(device: device)),
      );

      // assert
      expect(session.link.isUp, isTrue);
      expect(session.link.device, device);
      final borrowed = rightOf(
        await BorrowLink(registry).run(const BorrowLinkRequest(device: device)),
      );
      await borrowed.giveBack();
      expect(identical(borrowed.session, session), isTrue);
      expect(links.closesAsked(device), 0);
      expect(session.link.isUp, isTrue);
    });

    test('passes the caller\'s timeout to the open', () async {
      // act
      await connect.run(
        const ConnectDeviceRequest(
          device: device,
          timeout: Duration(seconds: 5),
        ),
      );

      // assert
      expect(links.openTimeouts, [const Duration(seconds: 5)]);
    });
  });
}
