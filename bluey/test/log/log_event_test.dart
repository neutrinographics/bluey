import 'package:bluey/src/log/log_event.dart';
import 'package:bluey/src/log/log_level.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final timestamp = DateTime.utc(2026, 4, 28, 12, 34, 56);

  group('BlueyLogEvent', () {
    test('constructor stores all fields', () {
      final event = BlueyLogEvent(
        timestamp: timestamp,
        level: BlueyLogLevel.info,
        context: 'connection',
        message: 'connected',
        data: const {'address': 'AA:BB'},
        errorCode: 'GATT_133',
      );
      expect(event.timestamp, timestamp);
      expect(event.level, BlueyLogLevel.info);
      expect(event.context, 'connection');
      expect(event.message, 'connected');
      expect(event.data, {'address': 'AA:BB'});
      expect(event.errorCode, 'GATT_133');
    });

    test('defaults: data is empty, errorCode is null', () {
      final event = BlueyLogEvent(
        timestamp: timestamp,
        level: BlueyLogLevel.debug,
        context: 'ctx',
        message: 'msg',
      );
      expect(event.data, isEmpty);
      expect(event.errorCode, isNull);
    });

    test('equality is by value across all fields', () {
      final a = BlueyLogEvent(
        timestamp: timestamp,
        level: BlueyLogLevel.info,
        context: 'ctx',
        message: 'msg',
        data: const {'k': 1},
        errorCode: 'E1',
      );
      final b = BlueyLogEvent(
        timestamp: timestamp,
        level: BlueyLogLevel.info,
        context: 'ctx',
        message: 'msg',
        data: const {'k': 1},
        errorCode: 'E1',
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different timestamp -> not equal', () {
      final a = BlueyLogEvent(
        timestamp: timestamp,
        level: BlueyLogLevel.info,
        context: 'ctx',
        message: 'msg',
      );
      final b = BlueyLogEvent(
        timestamp: timestamp.add(const Duration(seconds: 1)),
        level: BlueyLogLevel.info,
        context: 'ctx',
        message: 'msg',
      );
      expect(a, isNot(equals(b)));
    });

    test('different level -> not equal', () {
      final a = BlueyLogEvent(
        timestamp: timestamp,
        level: BlueyLogLevel.info,
        context: 'ctx',
        message: 'msg',
      );
      final b = BlueyLogEvent(
        timestamp: timestamp,
        level: BlueyLogLevel.warn,
        context: 'ctx',
        message: 'msg',
      );
      expect(a, isNot(equals(b)));
    });

    test('different context / message / errorCode -> not equal', () {
      final base = BlueyLogEvent(
        timestamp: timestamp,
        level: BlueyLogLevel.info,
        context: 'ctx',
        message: 'msg',
        errorCode: 'E1',
      );
      expect(
        base,
        isNot(equals(BlueyLogEvent(
          timestamp: timestamp,
          level: BlueyLogLevel.info,
          context: 'other',
          message: 'msg',
          errorCode: 'E1',
        ))),
      );
      expect(
        base,
        isNot(equals(BlueyLogEvent(
          timestamp: timestamp,
          level: BlueyLogLevel.info,
          context: 'ctx',
          message: 'other',
          errorCode: 'E1',
        ))),
      );
      expect(
        base,
        isNot(equals(BlueyLogEvent(
          timestamp: timestamp,
          level: BlueyLogLevel.info,
          context: 'ctx',
          message: 'msg',
          errorCode: 'E2',
        ))),
      );
    });

    test('data map equality is deep (same keys/values, different instance)',
        () {
      final a = BlueyLogEvent(
        timestamp: timestamp,
        level: BlueyLogLevel.info,
        context: 'ctx',
        message: 'msg',
        data: {'address': 'AA:BB', 'count': 3},
      );
      final b = BlueyLogEvent(
        timestamp: timestamp,
        level: BlueyLogLevel.info,
        context: 'ctx',
        message: 'msg',
        data: {'address': 'AA:BB', 'count': 3},
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different data -> not equal', () {
      final a = BlueyLogEvent(
        timestamp: timestamp,
        level: BlueyLogLevel.info,
        context: 'ctx',
        message: 'msg',
        data: const {'k': 1},
      );
      final b = BlueyLogEvent(
        timestamp: timestamp,
        level: BlueyLogLevel.info,
        context: 'ctx',
        message: 'msg',
        data: const {'k': 2},
      );
      expect(a, isNot(equals(b)));
    });

    test('different data length -> not equal', () {
      final a = BlueyLogEvent(
        timestamp: timestamp,
        level: BlueyLogLevel.info,
        context: 'ctx',
        message: 'msg',
        data: const {'k': 1},
      );
      final b = BlueyLogEvent(
        timestamp: timestamp,
        level: BlueyLogLevel.info,
        context: 'ctx',
        message: 'msg',
        data: const {'k': 1, 'extra': 'x'},
      );
      expect(a, isNot(equals(b)));
    });

    test('toString includes level name, context, and message', () {
      final event = BlueyLogEvent(
        timestamp: timestamp,
        level: BlueyLogLevel.warn,
        context: 'connection',
        message: 'retrying',
      );
      final s = event.toString();
      expect(s, isNotEmpty);
      expect(s, contains('warn'));
      expect(s, contains('connection'));
      expect(s, contains('retrying'));
    });
  });
}
