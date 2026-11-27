import 'package:bluey/src/features/connection/application/link_session.dart';
import 'package:bluey/src/features/connection/application/read_rssi.dart';
import 'package:bluey/src/features/connection/domain/connection_failure.dart';
import 'package:bluey/src/features/connection/domain/link_end.dart';
import 'package:bluey/src/features/connection/domain/link_operation.dart';
import 'package:bluey/src/shared/application/log_level.dart';
import 'package:bluey/src/shared/domain/device_address.dart';
import 'package:bluey/src/shared/domain/either.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../fixtures/features/connection/application/ports/in_memory_links.dart';
import '../../../fixtures/features/connection/application/ports/in_memory_signal_strength.dart';
import '../../../fixtures/features/connection/application/up_session.dart';
import '../../../fixtures/shared/application/recording_log.dart';

const device = DeviceAddress('AA:BB:CC:DD:EE:01');

void main() {
  late InMemoryLinks links;
  late InMemorySignalStrength strength;
  late RecordingLog log;
  late LinkSession session;
  late ReadRssi read;

  setUp(() async {
    links = InMemoryLinks();
    strength = InMemorySignalStrength()..rssi = -58;
    log = RecordingLog();
    session = await upSession(links, device);
    read = ReadRssi(strength: strength, log: log, now: DateTime.now);
  });

  test('answers the reading', () async {
    // act
    final answer = await read.run(session);

    // assert
    expect(answer, const Right<ConnectionFailure, int>(-58));
    expect(strength.reads, [session.id]);
  });

  test('answers the end of a link that is not up, and asks nothing', () async {
    // arrange
    await session.disconnect();

    // act
    final answer = await read.run(session);

    // assert
    expect(
      answer,
      const Left<ConnectionFailure, int>(LinkHadEnded(EndedOnRequest())),
    );
    expect(strength.reads, isEmpty);
    expect(log.records, isEmpty);
  });

  test('logs start, complete and failed as the GATT log does', () async {
    // arrange
    await read.run(session);
    strength.failNext(
      const OperationTimedOut(LinkOperation.readSignalStrength),
    );

    // act
    await read.run(session);

    // assert
    expect(
      log.records.map(
        (r) => (r.level, r.context, r.message, r.data['op'], r.data['detail']),
      ),
      [
        (BlueyLogLevel.debug, 'bluey.gatt', 'readRssi start', 'readRssi', null),
        (
          BlueyLogLevel.debug,
          'bluey.gatt',
          'readRssi complete',
          'readRssi',
          'rssi=-58dBm',
        ),
        (BlueyLogLevel.debug, 'bluey.gatt', 'readRssi start', 'readRssi', null),
        (
          BlueyLogLevel.error,
          'bluey.gatt',
          'readRssi failed',
          'readRssi',
          null,
        ),
      ],
    );
    expect(log.records.last.errorCode, 'OperationTimedOut');
    expect(log.records.last.data.containsKey('status'), isFalse);
  });

  test('a link that drops during a reading logs the failure at once, and '
      'nothing when the radio answers late', () {
    fakeAsync((async) {
      // arrange
      const timed = DeviceAddress('AA:BB:CC:DD:EE:02');
      late LinkSession timedSession;
      upSession(links, timed).then((value) => timedSession = value);
      async.elapse(Duration.zero);
      strength.delay = const Duration(seconds: 1);
      read.run(timedSession);
      async.elapse(const Duration(milliseconds: 500));

      // act
      links.drop(timed);
      async.elapse(Duration.zero);
      final logged = [...log.records];
      async.elapse(const Duration(seconds: 1));

      // assert

      expect(
        logged.map(
          (r) => (r.level, r.message, r.errorCode, r.data['exception']),
        ),
        [
          (BlueyLogLevel.debug, 'readRssi start', null, null),
          (BlueyLogLevel.error, 'readRssi failed', 'LinkEnded', 'LinkEnded'),
        ],
      );
      expect(log.records.length, 2);
    });
  });
}
