import 'package:bluey/bluey.dart';
import 'package:flutter_test/flutter_test.dart';

final _at = DateTime.utc(2026, 11, 27, 9);

void main() {
  group('the scan events', () {
    // (name, event, what it reads as)
    final rows = <(String, BlueyEvent, String)>[
      (
        'a filtered, timed start',
        ScanStartedEvent(
          serviceFilter: [UUID.short(0x180D)],
          timeout: const Duration(seconds: 10),
          timestamp: _at,
        ),
        '[Scan] Started filter=180d timeout=10s',
      ),
      ('an open start', ScanStartedEvent(timestamp: _at), '[Scan] Started'),
      (
        'a filtered, timed starting',
        ScanStartingEvent(
          serviceFilter: [UUID.short(0x180F)],
          timeout: const Duration(seconds: 5),
          timestamp: _at,
        ),
        '[Scan] Starting filter=180f timeout=5s',
      ),
      (
        'a starting with an empty filter',
        ScanStartingEvent(serviceFilter: const [], timestamp: _at),
        '[Scan] Starting',
      ),
      (
        'a named discovery',
        DeviceDiscoveredEvent(
          deviceAddress: const DeviceAddress('AA:BB:CC:DD:EE:01'),
          name: 'Heart',
          rssi: -60,
          timestamp: _at,
        ),
        '[Scan] Discovered '
            '${const DeviceAddress('AA:BB:CC:DD:EE:01').toShortString()}'
            ' "Heart" rssi=-60',
      ),
      (
        'a stop with a reason',
        ScanStoppedEvent(reason: 'timeout', timestamp: _at),
        '[Scan] Stopped (timeout)',
      ),
      ('a stop', ScanStoppedEvent(timestamp: _at), '[Scan] Stopped'),
      ('a stopping', ScanStoppingEvent(timestamp: _at), '[Scan] Stopping'),
    ];

    for (final (name, event, words) in rows) {
      test('$name reads as "$words" and keeps its timestamp', () {
        // arrange
        final given = event;

        // act
        final read = given.toString();

        // assert
        expect(read, words);
        expect(given.timestamp, _at);
      });
    }
  });
}
