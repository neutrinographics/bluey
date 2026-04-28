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

  group('Bluey logger integration', () {
    test('logEvents emits when internal logger logs', () async {
      final bluey = Bluey();
      bluey.setLogLevel(BlueyLogLevel.trace);

      final received = <BlueyLogEvent>[];
      final sub = bluey.logEvents.listen(received.add);

      bluey.logger.log(
        BlueyLogLevel.info,
        'test.ctx',
        'hello',
        data: const {'k': 'v'},
      );

      // Allow the broadcast stream to deliver the event.
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(1));
      expect(received.single.context, 'test.ctx');
      expect(received.single.message, 'hello');
      expect(received.single.level, BlueyLogLevel.info);
      expect(received.single.data, const {'k': 'v'});

      await sub.cancel();
      await bluey.dispose();
    });

    test('setLogLevel forwards to internal logger', () async {
      final bluey = Bluey();
      bluey.setLogLevel(BlueyLogLevel.warn);

      final received = <BlueyLogEvent>[];
      final sub = bluey.logEvents.listen(received.add);

      bluey.logger.log(BlueyLogLevel.info, 'ctx', 'filtered out');
      bluey.logger.log(BlueyLogLevel.warn, 'ctx', 'kept');
      bluey.logger.log(BlueyLogLevel.error, 'ctx', 'kept too');

      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(2));
      expect(received[0].level, BlueyLogLevel.warn);
      expect(received[1].level, BlueyLogLevel.error);

      await sub.cancel();
      await bluey.dispose();
    });

    test('dispose() closes the logger; subsequent logs are no-ops', () async {
      final bluey = Bluey();
      bluey.setLogLevel(BlueyLogLevel.trace);

      final received = <BlueyLogEvent>[];
      final sub = bluey.logEvents.listen(received.add);

      await bluey.dispose();

      // Should not throw and should not reach any listener.
      bluey.logger.log(BlueyLogLevel.info, 'ctx', 'after dispose');
      await Future<void>.delayed(Duration.zero);

      expect(received, isEmpty);
      await sub.cancel();
    });

    test('logEvents is a broadcast stream with multiple listeners', () async {
      final bluey = Bluey();
      bluey.setLogLevel(BlueyLogLevel.trace);

      expect(bluey.logEvents.isBroadcast, isTrue);

      final a = <BlueyLogEvent>[];
      final b = <BlueyLogEvent>[];
      final subA = bluey.logEvents.listen(a.add);
      final subB = bluey.logEvents.listen(b.add);

      bluey.logger.log(BlueyLogLevel.info, 'ctx', 'msg');
      await Future<void>.delayed(Duration.zero);

      expect(a, hasLength(1));
      expect(b, hasLength(1));

      await subA.cancel();
      await subB.cancel();
      await bluey.dispose();
    });
  });
}
