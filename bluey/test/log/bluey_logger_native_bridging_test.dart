import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';

void main() {
  late FakeBlueyPlatform fakePlatform;

  setUp(() {
    fakePlatform = FakeBlueyPlatform();
    BlueyPlatform.instance = fakePlatform;
    Bluey.resetShared();
  });

  group('Bluey native log bridging (I307 B.9)', () {
    test('native PlatformLogEvent surfaces on bluey.logEvents', () async {
      final bluey = Bluey();
      bluey.setLogLevel(BlueyLogLevel.trace);

      final received = <BlueyLogEvent>[];
      final sub = bluey.logEvents.listen(received.add);

      final timestamp = DateTime.utc(2026, 4, 28, 12, 30, 0);
      fakePlatform.emitLog(
        PlatformLogEvent(
          timestamp: timestamp,
          level: PlatformLogLevel.warn,
          context: 'bluey.android.connection',
          message: 'native ping',
          data: const {'address': 'AA:BB:CC:DD:EE:FF'},
          errorCode: 'GATT_133',
        ),
      );

      // Allow the broadcast stream to deliver.
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(1));
      final event = received.single;
      expect(event.timestamp, timestamp);
      expect(event.level, BlueyLogLevel.warn);
      expect(event.context, 'bluey.android.connection');
      expect(event.message, 'native ping');
      expect(event.data, const {'address': 'AA:BB:CC:DD:EE:FF'});
      expect(event.errorCode, 'GATT_133');

      await sub.cancel();
      await bluey.dispose();
    });

    test('setLogLevel forwards to the platform', () async {
      final bluey = Bluey();

      bluey.setLogLevel(BlueyLogLevel.warn);
      // The forward is fire-and-forget — give the microtask a chance to run.
      await Future<void>.delayed(Duration.zero);

      expect(fakePlatform.lastSetLogLevel, PlatformLogLevel.warn);

      bluey.setLogLevel(BlueyLogLevel.error);
      await Future<void>.delayed(Duration.zero);

      expect(fakePlatform.lastSetLogLevel, PlatformLogLevel.error);

      await bluey.dispose();
    });

    test('disposing Bluey stops forwarding native events', () async {
      final bluey = Bluey();
      bluey.setLogLevel(BlueyLogLevel.trace);

      final received = <BlueyLogEvent>[];
      final sub = bluey.logEvents.listen(received.add);

      await bluey.dispose();

      // Emitting after dispose must not surface anything to the consumer.
      fakePlatform.emitLog(
        PlatformLogEvent(
          timestamp: DateTime.utc(2026, 4, 28),
          level: PlatformLogLevel.info,
          context: 'native',
          message: 'after dispose',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(received, isEmpty);

      await sub.cancel();
    });
  });
}
