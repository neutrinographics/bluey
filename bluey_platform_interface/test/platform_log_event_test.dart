import 'package:bluey_platform_interface/bluey_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PlatformLogLevel', () {
    test('declares severity ordering trace < debug < info < warn < error', () {
      // The enum's index ordering is the canonical ordering used by
      // setLogLevel filters across the platform interface.
      expect(
        PlatformLogLevel.trace.index,
        lessThan(PlatformLogLevel.debug.index),
      );
      expect(
        PlatformLogLevel.debug.index,
        lessThan(PlatformLogLevel.info.index),
      );
      expect(
        PlatformLogLevel.info.index,
        lessThan(PlatformLogLevel.warn.index),
      );
      expect(
        PlatformLogLevel.warn.index,
        lessThan(PlatformLogLevel.error.index),
      );
    });

    test('has exactly five levels in expected order', () {
      expect(
        PlatformLogLevel.values,
        equals(<PlatformLogLevel>[
          PlatformLogLevel.trace,
          PlatformLogLevel.debug,
          PlatformLogLevel.info,
          PlatformLogLevel.warn,
          PlatformLogLevel.error,
        ]),
      );
    });
  });

  group('PlatformLogEvent', () {
    final fixedTime = DateTime.fromMicrosecondsSinceEpoch(
      1_700_000_000_000_000,
      isUtc: true,
    );

    test('stores all required fields', () {
      final event = PlatformLogEvent(
        timestamp: fixedTime,
        level: PlatformLogLevel.warn,
        context: 'gatt_client',
        message: 'mtu negotiation failed',
        data: const {'deviceId': 'AA:BB', 'attempt': 2},
        errorCode: 'GATT_133',
      );

      expect(event.timestamp, fixedTime);
      expect(event.level, PlatformLogLevel.warn);
      expect(event.context, 'gatt_client');
      expect(event.message, 'mtu negotiation failed');
      expect(event.data, {'deviceId': 'AA:BB', 'attempt': 2});
      expect(event.errorCode, 'GATT_133');
    });

    test('defaults data to const empty map and errorCode to null', () {
      final event = PlatformLogEvent(
        timestamp: fixedTime,
        level: PlatformLogLevel.debug,
        context: 'connection',
        message: 'entered',
      );

      expect(event.data, isEmpty);
      expect(event.errorCode, isNull);
    });

    test('equality is by value across every field', () {
      final a = PlatformLogEvent(
        timestamp: fixedTime,
        level: PlatformLogLevel.info,
        context: 'connection',
        message: 'connected',
        data: const {'deviceId': 'AA:BB'},
        errorCode: null,
      );
      final b = PlatformLogEvent(
        timestamp: fixedTime,
        level: PlatformLogLevel.info,
        context: 'connection',
        message: 'connected',
        data: const {'deviceId': 'AA:BB'},
        errorCode: null,
      );

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('differs when any field differs', () {
      final base = PlatformLogEvent(
        timestamp: fixedTime,
        level: PlatformLogLevel.info,
        context: 'connection',
        message: 'connected',
        data: const {'deviceId': 'AA:BB'},
      );

      expect(
        base ==
            PlatformLogEvent(
              timestamp: fixedTime.add(const Duration(microseconds: 1)),
              level: PlatformLogLevel.info,
              context: 'connection',
              message: 'connected',
              data: const {'deviceId': 'AA:BB'},
            ),
        isFalse,
      );
      expect(
        base ==
            PlatformLogEvent(
              timestamp: fixedTime,
              level: PlatformLogLevel.warn,
              context: 'connection',
              message: 'connected',
              data: const {'deviceId': 'AA:BB'},
            ),
        isFalse,
      );
      expect(
        base ==
            PlatformLogEvent(
              timestamp: fixedTime,
              level: PlatformLogLevel.info,
              context: 'gatt_client',
              message: 'connected',
              data: const {'deviceId': 'AA:BB'},
            ),
        isFalse,
      );
      expect(
        base ==
            PlatformLogEvent(
              timestamp: fixedTime,
              level: PlatformLogLevel.info,
              context: 'connection',
              message: 'disconnected',
              data: const {'deviceId': 'AA:BB'},
            ),
        isFalse,
      );
      expect(
        base ==
            PlatformLogEvent(
              timestamp: fixedTime,
              level: PlatformLogLevel.info,
              context: 'connection',
              message: 'connected',
              data: const {'deviceId': 'CC:DD'},
            ),
        isFalse,
      );
      expect(
        base ==
            PlatformLogEvent(
              timestamp: fixedTime,
              level: PlatformLogLevel.info,
              context: 'connection',
              message: 'connected',
              data: const {'deviceId': 'AA:BB'},
              errorCode: 'GATT_133',
            ),
        isFalse,
      );
    });

    test('data map equality is order-independent', () {
      final a = PlatformLogEvent(
        timestamp: fixedTime,
        level: PlatformLogLevel.info,
        context: 'connection',
        message: 'connected',
        data: const {'a': 1, 'b': 2},
      );
      final b = PlatformLogEvent(
        timestamp: fixedTime,
        level: PlatformLogLevel.info,
        context: 'connection',
        message: 'connected',
        data: const {'b': 2, 'a': 1},
      );

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });
  });
}
