import 'package:bluey/src/features/connection/application/link_operation_log.dart';
import 'package:bluey/src/features/connection/domain/connection_failure.dart';
import 'package:bluey/src/features/connection/domain/link_operation.dart';
import 'package:bluey/src/shared/application/log_level.dart';
import 'package:bluey/src/shared/domain/device_address.dart';
import 'package:bluey/src/shared/domain/either.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../fixtures/shared/application/recording_log.dart';

const _device = DeviceAddress('AA:BB:CC:DD:EE:01');

/// A clock that moves on by [step] each time it is read, so a duration is
/// the number of reads between start and answer times the step.
DateTime Function() _ticking(Duration step) {
  var at = DateTime.utc(2026, 11, 26, 10);
  return () => at = at.add(step);
}

void main() {
  late RecordingLog log;

  setUp(() => log = RecordingLog());

  Future<Either<ConnectionFailure, int>> run(
    Either<ConnectionFailure, int> answer, {
    String startDetail = 'requested=247',
  }) => loggedLinkOperation<int>(
    log,
    now: _ticking(const Duration(milliseconds: 7)),
    device: _device,
    operation: LinkOperation.negotiateMtu,
    startDetail: startDetail,
    completeDetail: (value) => 'requested=247, negotiated=$value',
    run: () async => answer,
  );

  test('answers what the operation answered', () async {
    // act
    final answer = await run(const Right(185));

    // assert
    expect(answer, const Right<ConnectionFailure, int>(185));
  });

  test(
    'logs the start with the operation\'s word and the start detail',
    () async {
      // act
      await run(const Right(185));

      // assert
      final start = log.records.first;
      expect(start.level, BlueyLogLevel.debug);
      expect(start.context, 'bluey.gatt');
      expect(start.message, 'requestMtu start');
      expect(start.data, {
        'deviceId': 'AA:BB:CC:DD:EE:01',
        'op': 'requestMtu',
        'detail': 'requested=247',
      });
    },
  );

  test(
    'logs the answer with how long it took and the complete detail',
    () async {
      // act
      await run(const Right(185));

      // assert
      final complete = log.records.last;
      expect(complete.level, BlueyLogLevel.debug);
      expect(complete.context, 'bluey.gatt');
      expect(complete.message, 'requestMtu complete');
      expect(complete.data, {
        'deviceId': 'AA:BB:CC:DD:EE:01',
        'op': 'requestMtu',
        'durationMs': 7,
        'detail': 'requested=247, negotiated=185',
      });
      expect(log.records, hasLength(2));
    },
  );

  test('a start with no detail logs no detail', () async {
    // act
    await run(const Right(185), startDetail: '');

    // assert
    expect(log.records.first.data.containsKey('detail'), isFalse);
  });

  test('a failure logs its type, and the status of a rejection', () async {
    // act
    final answer = await run(
      const Left(OperationRejected(LinkOperation.negotiateMtu, 133)),
    );

    // assert
    final failed = log.records.last;
    expect(answer, isA<Left<ConnectionFailure, int>>());
    expect(failed.level, BlueyLogLevel.error);
    expect(failed.context, 'bluey.gatt');
    expect(failed.message, 'requestMtu failed');
    expect(failed.errorCode, 'OperationRejected');
    expect(failed.data, {
      'deviceId': 'AA:BB:CC:DD:EE:01',
      'op': 'requestMtu',
      'exception': 'OperationRejected',
      'durationMs': 7,
      'status': 133,
      'detail': 'requested=247',
    });
  });

  test('a failure that is not a rejection logs no status', () async {
    // act
    await run(const Left(OperationTimedOut(LinkOperation.negotiateMtu)));

    // assert
    final failed = log.records.last;
    expect(failed.errorCode, 'OperationTimedOut');
    expect(failed.data.containsKey('status'), isFalse);
  });

  test('a failure after a start with no detail logs no detail', () async {
    // act
    await run(
      const Left(OperationTimedOut(LinkOperation.negotiateMtu)),
      startDetail: '',
    );

    // assert
    expect(log.records.last.data.containsKey('detail'), isFalse);
  });
}
