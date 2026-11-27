import 'package:bluey/src/api/connection/connection_event_translation.dart';
import 'package:bluey/src/api/connection/connection_events.dart';
import 'package:bluey/src/features/connection/domain/link_end.dart';
import 'package:bluey/src/features/connection/domain/link_event.dart';
import 'package:bluey/src/shared/domain/device_address.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/shared/application/recording_event_publisher.dart';
import 'package:bluey/src/shared/domain/radio_outage.dart';

const device = DeviceAddress('AA:BB:CC:DD:EE:01');
final at = DateTime.utc(2026, 11, 26, 10);

void main() {
  // (name, the link's event, the published type, the reason in words)
  final rows = <(String, LinkEvent, Type, String?)>[
    (
      'an open that began is a connecting event',
      LinkOpenBegan(device: device, at: at),
      ConnectingEvent,
      null,
    ),
    (
      'a link that opened is a connected event',
      LinkOpened(device: device, at: at),
      ConnectedEvent,
      null,
    ),
    (
      'a link ended on request is a disconnect for "requested"',
      LinkEnded(device: device, at: at, end: const EndedOnRequest()),
      DisconnectedEvent,
      'requested',
    ),
    (
      'a dropped link is a disconnect for "linkLoss"',
      LinkEnded(device: device, at: at, end: const EndedByDrop()),
      DisconnectedEvent,
      'linkLoss',
    ),
    (
      'a link ended by an outage is a disconnect for "radioOutage"',
      LinkEnded(
        device: device,
        at: at,
        end: const EndedByRadioOutage(RadioOutage.off),
      ),
      DisconnectedEvent,
      'radioOutage',
    ),
  ];

  for (final (name, event, type, reason) in rows) {
    test(name, () {
      // arrange
      final publisher = RecordingEventPublisher();

      // act
      PublishedLinkEvents(publisher).raise(event);

      // assert
      final published = publisher.events.single;
      expect(published.runtimeType, type);
      expect(published.timestamp, at);
      final (address, said) = switch (published) {
        ConnectingEvent(:final deviceAddress) => (deviceAddress, null),
        ConnectedEvent(:final deviceAddress) => (deviceAddress, null),
        DisconnectedEvent(:final deviceAddress, :final reason) => (
          deviceAddress,
          reason,
        ),
        _ => fail('not a connection event: $published'),
      };
      expect(address, device);
      expect(said, reason);
    });
  }
}
