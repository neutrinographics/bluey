import 'package:bluey/src/log/bluey_logger.dart';
import 'package:bluey/src/log/log_event.dart';
import 'package:bluey/src/log/log_level.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BlueyLogger', () {
    late BlueyLogger logger;

    setUp(() {
      logger = BlueyLogger();
    });

    tearDown(() async {
      await logger.dispose();
    });

    test('events is a broadcast stream with multiple listeners', () async {
      expect(logger.events.isBroadcast, isTrue);
      final a = <BlueyLogEvent>[];
      final b = <BlueyLogEvent>[];
      final subA = logger.events.listen(a.add);
      final subB = logger.events.listen(b.add);

      logger.log(BlueyLogLevel.info, 'ctx', 'msg');
      // Let the broadcast deliver to both listeners.
      await Future<void>.delayed(Duration.zero);

      expect(a, hasLength(1));
      expect(b, hasLength(1));
      await subA.cancel();
      await subB.cancel();
    });

    test('default minLevel is info; info event flows', () async {
      final captured = <BlueyLogEvent>[];
      final sub = logger.events.listen(captured.add);

      final before = DateTime.now();
      logger.log(BlueyLogLevel.info, 'connection', 'connected');
      await Future<void>.delayed(Duration.zero);
      final after = DateTime.now();

      expect(captured, hasLength(1));
      final event = captured.single;
      expect(event.level, BlueyLogLevel.info);
      expect(event.context, 'connection');
      expect(event.message, 'connected');
      expect(event.data, isEmpty);
      expect(event.errorCode, isNull);
      expect(
        event.timestamp.isAfter(before.subtract(const Duration(seconds: 1))),
        isTrue,
      );
      expect(
        event.timestamp.isBefore(after.add(const Duration(seconds: 1))),
        isTrue,
      );
      await sub.cancel();
    });

    test('trace is dropped when minLevel is info', () async {
      final captured = <BlueyLogEvent>[];
      final sub = logger.events.listen(captured.add);

      logger.log(BlueyLogLevel.trace, 'ctx', 'noisy');
      await Future<void>.delayed(Duration.zero);

      expect(captured, isEmpty);
      await sub.cancel();
    });

    test('debug is dropped when minLevel is info', () async {
      final captured = <BlueyLogEvent>[];
      final sub = logger.events.listen(captured.add);

      logger.log(BlueyLogLevel.debug, 'ctx', 'verbose');
      await Future<void>.delayed(Duration.zero);

      expect(captured, isEmpty);
      await sub.cancel();
    });

    test('setLevel(trace) lets trace events through', () async {
      logger.setLevel(BlueyLogLevel.trace);
      final captured = <BlueyLogEvent>[];
      final sub = logger.events.listen(captured.add);

      logger.log(BlueyLogLevel.trace, 'ctx', 'tracey');
      await Future<void>.delayed(Duration.zero);

      expect(captured, hasLength(1));
      expect(captured.single.level, BlueyLogLevel.trace);
      await sub.cancel();
    });

    test('setLevel(error) drops everything below error', () async {
      logger.setLevel(BlueyLogLevel.error);
      final captured = <BlueyLogEvent>[];
      final sub = logger.events.listen(captured.add);

      logger.log(BlueyLogLevel.trace, 'ctx', 't');
      logger.log(BlueyLogLevel.debug, 'ctx', 'd');
      logger.log(BlueyLogLevel.info, 'ctx', 'i');
      logger.log(BlueyLogLevel.warn, 'ctx', 'w');
      logger.log(BlueyLogLevel.error, 'ctx', 'e');
      await Future<void>.delayed(Duration.zero);

      expect(captured, hasLength(1));
      expect(captured.single.level, BlueyLogLevel.error);
      expect(captured.single.message, 'e');
      await sub.cancel();
    });

    test('level getter reflects current threshold', () {
      expect(logger.level, BlueyLogLevel.info);
      logger.setLevel(BlueyLogLevel.warn);
      expect(logger.level, BlueyLogLevel.warn);
    });

    test('log forwards data and errorCode onto the event', () async {
      final captured = <BlueyLogEvent>[];
      final sub = logger.events.listen(captured.add);

      logger.log(
        BlueyLogLevel.warn,
        'gatt_client',
        'retrying',
        data: const {'attempt': 2, 'address': 'AA:BB'},
        errorCode: 'GATT_133',
      );
      await Future<void>.delayed(Duration.zero);

      expect(captured, hasLength(1));
      final event = captured.single;
      expect(event.level, BlueyLogLevel.warn);
      expect(event.context, 'gatt_client');
      expect(event.message, 'retrying');
      expect(event.data, {'attempt': 2, 'address': 'AA:BB'});
      expect(event.errorCode, 'GATT_133');
      await sub.cancel();
    });

    test('constructor accepts initial level', () async {
      final l = BlueyLogger(level: BlueyLogLevel.error);
      expect(l.level, BlueyLogLevel.error);
      final captured = <BlueyLogEvent>[];
      final sub = l.events.listen(captured.add);
      l.log(BlueyLogLevel.warn, 'ctx', 'shouldDrop');
      l.log(BlueyLogLevel.error, 'ctx', 'shouldKeep');
      await Future<void>.delayed(Duration.zero);
      expect(captured, hasLength(1));
      expect(captured.single.message, 'shouldKeep');
      await sub.cancel();
      await l.dispose();
    });

    test('dispose closes the controller; subsequent log is a no-op', () async {
      final l = BlueyLogger();
      final captured = <BlueyLogEvent>[];
      final sub = l.events.listen(captured.add);
      await l.dispose();
      // Stream is closed; the listener should have received onDone.
      expect(
        () => l.log(BlueyLogLevel.error, 'ctx', 'after dispose'),
        returnsNormally,
      );
      // Nothing was emitted after dispose.
      expect(captured, isEmpty);
      await sub.cancel();
    });
  });
}
