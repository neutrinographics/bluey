import 'dart:async';
import 'dart:typed_data';

import 'package:bluey/bluey.dart';

import '../../../shared/stress_protocol.dart';
import '../domain/stress_test_config.dart';
import '../domain/stress_test_result.dart';

/// Single point of contact between the stress_tests feature and a live
/// [Connection]. Each `run*` method returns a `Stream<StressTestResult>`
/// that emits incremental snapshots as ops complete and a final
/// `isRunning=false` snapshot when done.
///
/// Every method begins by sending [ResetCommand] to the server so the
/// run starts from a known baseline regardless of how the previous test
/// ended (see spec: "Test isolation").
class StressTestRunner {
  Stream<StressTestResult> runBurstWrite(
    BurstWriteConfig config,
    Connection connection,
  ) async* {
    final stressChar = await _resolveStressChar(connection);

    // Test isolation: clean baseline before measuring. Failures here
    // abort the run with an empty final snapshot — reset is prologue,
    // not measurement.
    try {
      await stressChar.write(const ResetCommand().encode(), withResponse: true);
    } on Object {
      yield StressTestResult.initial().finished(elapsed: Duration.zero);
      return;
    }

    var result = StressTestResult.initial();
    final stopwatch = Stopwatch()..start();
    yield result;

    final payload = _generatePattern(config.payloadBytes);
    final cmd = EchoCommand(payload).encode();

    final outcomes = <_OpOutcome>[];
    final futures = <Future<void>>[];
    for (var i = 0; i < config.count; i++) {
      final opStart = stopwatch.elapsedMicroseconds;
      futures.add(() async {
        try {
          await stressChar.write(cmd, withResponse: config.withResponse);
          outcomes.add(_OpOutcome.success(
            latency: Duration(
              microseconds: stopwatch.elapsedMicroseconds - opStart,
            ),
          ));
        } catch (e) {
          outcomes.add(_OpOutcome.failure(
            typeName: e.runtimeType.toString(),
            status: e is GattOperationFailedException ? e.status : null,
          ));
        }
      }());
    }
    await Future.wait(futures);
    stopwatch.stop();

    for (final o in outcomes) {
      result = o.success
          ? result.recordSuccess(latency: o.latency!)
          : result.recordFailure(typeName: o.typeName!, status: o.status);
    }
    yield result.finished(elapsed: stopwatch.elapsed);
  }

  Stream<StressTestResult> runMixedOps(
    MixedOpsConfig config,
    Connection connection,
  ) {
    throw UnimplementedError('runMixedOps implemented in Task 14');
  }

  Stream<StressTestResult> runSoak(
    SoakConfig config,
    Connection connection,
  ) {
    throw UnimplementedError('runSoak implemented in Task 15');
  }

  Stream<StressTestResult> runTimeoutProbe(
    TimeoutProbeConfig config,
    Connection connection,
  ) {
    throw UnimplementedError('runTimeoutProbe implemented in Task 16');
  }

  Stream<StressTestResult> runFailureInjection(
    FailureInjectionConfig config,
    Connection connection,
  ) {
    throw UnimplementedError('runFailureInjection implemented in Task 17');
  }

  Stream<StressTestResult> runMtuProbe(
    MtuProbeConfig config,
    Connection connection,
  ) {
    throw UnimplementedError('runMtuProbe implemented in Task 18');
  }

  Stream<StressTestResult> runNotificationThroughput(
    NotificationThroughputConfig config,
    Connection connection,
  ) {
    throw UnimplementedError('runNotificationThroughput implemented in Task 19');
  }

  Future<RemoteCharacteristic> _resolveStressChar(
    Connection connection,
  ) async {
    final services = await connection.services();
    final svc = services.firstWhere(
      (s) => s.uuid == UUID(StressProtocol.serviceUuid),
      orElse: () => throw StateError('Stress service not found on peer'),
    );
    return svc.characteristic(UUID(StressProtocol.charUuid));
  }

  static Uint8List _generatePattern(int size) {
    final out = Uint8List(size);
    for (var i = 0; i < size; i++) {
      out[i] = i & 0xff;
    }
    return out;
  }
}

/// Internal per-op outcome buffer used by runner methods that dispatch
/// ops via `Future.wait`. Collecting outcomes into a list first and
/// folding them into the final [StressTestResult] after all futures
/// complete avoids any ambiguity about shared mutable state across
/// concurrent async closures.
class _OpOutcome {
  final bool success;
  final Duration? latency;
  final String? typeName;
  final int? status;
  const _OpOutcome._({
    required this.success,
    this.latency,
    this.typeName,
    this.status,
  });
  factory _OpOutcome.success({required Duration latency}) =>
      _OpOutcome._(success: true, latency: latency);
  factory _OpOutcome.failure({required String typeName, int? status}) =>
      _OpOutcome._(success: false, typeName: typeName, status: status);
}
