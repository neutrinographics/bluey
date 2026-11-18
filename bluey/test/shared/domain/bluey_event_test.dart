import 'package:bluey/src/shared/domain/bluey_event.dart';
import 'package:flutter_test/flutter_test.dart';

final class _ProbeEvent extends BlueyEvent {
  _ProbeEvent({super.timestamp});
}

void main() {
  group('BlueyEvent', () {
    test('an event outside events.dart can extend BlueyEvent', () {
      // arrange
      final timestamp = DateTime.utc(2026, 11, 18, 9, 5, 7, 42);

      // act
      final event = _ProbeEvent(timestamp: timestamp);

      // assert
      expect(event, isA<BlueyEvent>());
      expect(event.toString(), '[_ProbeEvent] 09:05:07.042');
    });
  });
}
