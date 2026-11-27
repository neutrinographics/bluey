import '../../../shared/application/log.dart';
import '../../../shared/application/log_level.dart';
import '../../../shared/application/now.dart';
import '../../../shared/domain/device_address.dart';
import '../../../shared/domain/either.dart';
import '../domain/connection_failure.dart';
import '../domain/link_operation.dart';
import 'connection_log_words.dart';
import 'link_session.dart';

/// Runs one operation on a link and logs its start and its answer, as the
/// GATT log always has, so an app's filters on those lines hold.
///
/// [startDetail] is logged with the start and with a failure, and
/// [completeDetail] words a success; an empty detail is left out.
Future<Either<ConnectionFailure, T>> _loggedLinkOperation<T>(
  Log log, {
  required Now now,
  required DeviceAddress device,
  required LinkOperation operation,
  String startDetail = '',
  required String Function(T value) completeDetail,
  required Future<Either<ConnectionFailure, T>> Function() run,
}) async {
  final op = operationWordOf(operation);
  log.log(
    BlueyLogLevel.debug,
    gattLogContext,
    '$op start',
    data: {
      'deviceId': '$device',
      'op': op,
      if (startDetail.isNotEmpty) 'detail': startDetail,
    },
  );
  final started = now();
  final answer = await run();
  final durationMs = now().difference(started).inMilliseconds;
  answer.fold(
    (failure) => log.log(
      BlueyLogLevel.error,
      gattLogContext,
      '$op failed',
      data: {
        'deviceId': '$device',
        'op': op,
        'exception': failureCodeOf(failure),
        'durationMs': durationMs,
        if (failure case OperationRejected(:final status)) 'status': status,
        if (startDetail.isNotEmpty) 'detail': startDetail,
      },
      errorCode: failureCodeOf(failure),
    ),
    (value) {
      final detail = completeDetail(value);
      log.log(
        BlueyLogLevel.debug,
        gattLogContext,
        '$op complete',
        data: {
          'deviceId': '$device',
          'op': op,
          'durationMs': durationMs,
          if (detail.isNotEmpty) 'detail': detail,
        },
      );
    },
  );
  return answer;
}

/// Runs one operation over [session]'s link as the GATT log always has: a
/// link that is not up is answered its end and logs nothing, and a link that
/// ends while the operation is in flight logs the failure as soon as the
/// caller is answered, never the platform's late answer.
Future<Either<ConnectionFailure, T>> loggedWhileUp<T>(
  Log log, {
  required Now now,
  required LinkSession session,
  required LinkOperation operation,
  String startDetail = '',
  required String Function(T value) completeDetail,
  required Future<Either<ConnectionFailure, T>> Function() run,
}) async {
  if (session.link.endInSight case final end?) return Left(LinkHadEnded(end));
  return _loggedLinkOperation(
    log,
    now: now,
    device: session.link.device,
    operation: operation,
    startDetail: startDetail,
    completeDetail: completeDetail,
    run: () => session.whileUp(run, orEnd: LinkHadEnded.new),
  );
}
