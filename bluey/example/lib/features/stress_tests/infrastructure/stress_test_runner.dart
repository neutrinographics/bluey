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

    // Test isolation: clean baseline before measuring.
    await stressChar.write(const ResetCommand().encode(), withResponse: true);

    var result = StressTestResult.initial();
    final stopwatch = Stopwatch()..start();
    yield result;

    final futures = <Future<void>>[];
    final payload = _generatePattern(config.payloadBytes);
    final cmd = EchoCommand(payload).encode();

    for (var i = 0; i < config.count; i++) {
      final opStart = stopwatch.elapsedMicroseconds;
      futures.add(() async {
        try {
          await stressChar.write(cmd, withResponse: config.withResponse);
          final latency = Duration(
            microseconds: stopwatch.elapsedMicroseconds - opStart,
          );
          result = result.recordSuccess(latency: latency);
        } catch (e) {
          final typeName = e.runtimeType.toString();
          final status =
              e is GattOperationFailedException ? e.status : null;
          result = result.recordFailure(typeName: typeName, status: status);
        }
      }());
    }

    await Future.wait(futures);
    stopwatch.stop();
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
