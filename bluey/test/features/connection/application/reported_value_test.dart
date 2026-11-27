import 'dart:async';

import 'package:bluey/src/features/connection/application/link_session.dart';
import 'package:bluey/src/features/connection/application/reported_value.dart';
import 'package:bluey/src/features/connection/domain/connection_failure.dart';
import 'package:bluey/src/features/connection/domain/link_operation.dart';
import 'package:bluey/src/shared/application/log_level.dart';
import 'package:bluey/src/shared/domain/device_address.dart';
import 'package:bluey/src/shared/domain/either.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../fixtures/features/connection/application/ports/in_memory_links.dart';
import '../../../fixtures/features/connection/application/up_session.dart';
import '../../../fixtures/shared/application/recording_log.dart';

const device = DeviceAddress('AA:BB:CC:DD:EE:01');
const timedOut = OperationTimedOut(LinkOperation.readPhy);

void main() {
  late InMemoryLinks links;
  late LinkSession session;
  late StreamController<int> reports;
  late Completer<Either<ConnectionFailure, int>> read;
  late RecordingLog log;
  late int reads;

  ReportedValue<int> valueOver({bool followed = true}) => ReportedValue<int>(
    session: session,
    initial: 0,
    reports: followed ? reports.stream : null,
    readFirst: () {
      reads++;
      return read.future;
    },
    log: log,
    failedReadLine: 'reading read failed',
  );

  setUp(() async {
    links = InMemoryLinks();
    session = await upSession(links, device);
    reports = StreamController<int>.broadcast();
    read = Completer<Either<ConnectionFailure, int>>();
    log = RecordingLog();
    reads = 0;
  });

  test('holds the initial value and reads once, at once', () {
    // act
    final value = valueOver();

    // assert
    expect(value.value, 0);
    expect(reads, 1);
  });

  test('the first read sets the value', () async {
    // arrange
    final value = valueOver();

    // act
    read.complete(const Right(7));
    await pumpEventQueue();

    // assert
    expect(value.value, 7);
  });

  test('a report replaces the value and reaches each listener after the '
      'value it had', () async {
    // arrange
    final value = valueOver();
    final seen = <int>[];
    value.follow().listen(seen.add);

    // act
    reports
      ..add(1)
      ..add(2);
    await pumpEventQueue();

    // assert
    expect(seen, [0, 1, 2]);
    expect(value.value, 2);
  });

  test('a value taken reaches the listeners and outranks the first '
      'read', () async {
    // arrange
    final value = valueOver(followed: false);
    final seen = <int>[];
    value.follow().listen(seen.add);

    // act
    value.take(5);
    read.complete(const Right(7));
    await pumpEventQueue();

    // assert
    expect(value.value, 5);
    expect(seen, [0, 5]);
  });

  test(
    'a first read that answers after a report does not replace it',
    () async {
      // arrange
      final value = valueOver();
      reports.add(3);
      await pumpEventQueue();

      // act
      read.complete(const Right(7));
      await pumpEventQueue();

      // assert
      expect(value.value, 3);
    },
  );

  test('a first read that answers after the link ended is ignored', () async {
    // arrange
    final value = valueOver();
    links.drop(device);
    await pumpEventQueue();

    // act
    read.complete(const Right(7));
    await pumpEventQueue();

    // assert
    expect(value.value, 0);
  });

  test('a failed first read is logged once and the initial value stays, '
      'even after the link ended', () async {
    // arrange
    final value = valueOver();
    links.drop(device);
    await pumpEventQueue();

    // act
    read.complete(const Left(timedOut));
    await pumpEventQueue();

    // assert
    expect(
      log.records.map((r) => (r.level, r.context, r.message, r.errorCode)),
      [(BlueyLogLevel.warn, 'bluey.connection', 'reading read failed', null)],
    );
    expect(log.records.single.data, {
      'deviceId': 'AA:BB:CC:DD:EE:01',
      'exception': 'OperationTimedOut',
    });
    expect(value.value, 0);
  });

  test('the changes end when the link ends, a later listener gets the last '
      'value and then the end, and later reports change nothing', () async {
    // arrange
    final value = valueOver();
    final early = <int>[];
    var earlyEnded = false;
    value.follow().listen(early.add, onDone: () => earlyEnded = true);
    reports.add(4);
    await pumpEventQueue();

    // act
    links.drop(device);
    await pumpEventQueue();
    reports.add(9);
    await pumpEventQueue();
    final late = <int>[];
    var lateEnded = false;
    value.follow().listen(late.add, onDone: () => lateEnded = true);
    await pumpEventQueue();

    // assert
    expect(early, [0, 4]);
    expect(earlyEnded, isTrue);
    expect(late, [4]);
    expect(lateEnded, isTrue);
    expect(value.value, 4);
    expect(reports.hasListener, isFalse);
  });

  test('a value taken after the link ended is held and reaches '
      'nobody', () async {
    // arrange
    final value = valueOver(followed: false);
    links.drop(device);
    await pumpEventQueue();

    // act
    value.take(5);

    // assert
    expect(value.value, 5);
  });

  test('an unreported value holds its value, reads nothing, and its changes '
      'are that value and then the end', () async {
    // arrange
    final value = ReportedValue<int>.unreported(0);
    final seen = <int>[];
    var ended = false;

    // act
    value.follow().listen(seen.add, onDone: () => ended = true);
    await pumpEventQueue();

    // assert
    expect(value.value, 0);
    expect(seen, [0]);
    expect(ended, isTrue);
  });
}
