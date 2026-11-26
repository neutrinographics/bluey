import 'package:bluey/src/features/connection/domain/link_end.dart';
import 'package:bluey/src/features/connection/domain/link_event.dart';
import 'package:bluey/src/shared/domain/device_address.dart';
import 'package:flutter_test/flutter_test.dart';

const device = DeviceAddress('AA:BB:CC:DD:EE:01');
const other = DeviceAddress('AA:BB:CC:DD:EE:02');
final at = DateTime.utc(2026, 11, 26, 10);
final later = DateTime.utc(2026, 11, 26, 11);

void main() {
  group('equality', () {
    // (name, an event, the same event built again, events that differ)
    final rows = <(String, LinkEvent, LinkEvent, List<LinkEvent>)>[
      (
        'an open that began',
        LinkOpenBegan(device: device, at: at),
        LinkOpenBegan(device: device, at: at),
        [
          LinkOpenBegan(device: other, at: at),
          LinkOpenBegan(device: device, at: later),
          LinkOpened(device: device, at: at),
        ],
      ),
      (
        'a link that opened',
        LinkOpened(device: device, at: at),
        LinkOpened(device: device, at: at),
        [
          LinkOpened(device: other, at: at),
          LinkOpened(device: device, at: later),
          LinkOpenBegan(device: device, at: at),
        ],
      ),
      (
        'a link that ended',
        LinkEnded(device: device, at: at, end: const EndedByDrop()),
        LinkEnded(device: device, at: at, end: const EndedByDrop()),
        [
          LinkEnded(device: other, at: at, end: const EndedByDrop()),
          LinkEnded(device: device, at: later, end: const EndedByDrop()),
          LinkEnded(device: device, at: at, end: const EndedOnRequest()),
        ],
      ),
    ];

    for (final (name, event, again, differing) in rows) {
      test('$name equals itself built again and nothing else', () {
        // assert
        expect(event, again);
        expect(event.hashCode, again.hashCode);
        for (final different in differing) {
          expect(event, isNot(different));
        }
      });
    }
  });

  test('every event names its device and when it happened', () {
    // arrange
    final events = <LinkEvent>[
      LinkOpenBegan(device: device, at: at),
      LinkOpened(device: device, at: at),
      LinkEnded(device: device, at: at, end: const EndedOnRequest()),
    ];

    // assert
    for (final event in events) {
      expect((event.device, event.at), (device, at));
    }
  });
}
