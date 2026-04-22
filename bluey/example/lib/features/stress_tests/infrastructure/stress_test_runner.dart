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
  ) async* {
    final stressChar = await _resolveStressChar(connection);

    try {
      await stressChar.write(const ResetCommand().encode(), withResponse: true);
    } on Object {
      yield StressTestResult.initial().finished(elapsed: Duration.zero);
      return;
    }

    var result = StressTestResult.initial();
    final stopwatch = Stopwatch()..start();
    yield result;

    final payload = _generatePattern(20);
    final cmd = EchoCommand(payload).encode();

    Future<_OpOutcome> recordOp(Future<void> Function() op) async {
      final start = stopwatch.elapsedMicroseconds;
      try {
        await op();
        return _OpOutcome.success(
          latency: Duration(
            microseconds: stopwatch.elapsedMicroseconds - start,
          ),
        );
      } catch (e) {
        return _OpOutcome.failure(
          typeName: e.runtimeType.toString(),
          status: e is GattOperationFailedException ? e.status : null,
        );
      }
    }

    final futures = <Future<_OpOutcome>>[];
    for (var i = 0; i < config.iterations; i++) {
      futures.add(recordOp(() => stressChar.write(cmd, withResponse: true)));
      futures.add(recordOp(() => stressChar.read()));
      futures.add(recordOp(() => connection.services(cache: false)));
      futures.add(recordOp(() => connection.requestMtu(247)));
    }
    final outcomes = await Future.wait(futures);
    stopwatch.stop();

    for (final o in outcomes) {
      result = o.success
          ? result.recordSuccess(latency: o.latency!)
          : result.recordFailure(typeName: o.typeName!, status: o.status);
    }
    yield result.finished(elapsed: stopwatch.elapsed);
  }

  Stream<StressTestResult> runSoak(
    SoakConfig config,
    Connection connection,
  ) async* {
    final stressChar = await _resolveStressChar(connection);

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
    final endTime = stopwatch.elapsed + config.duration;

    while (stopwatch.elapsed < endTime) {
      final start = stopwatch.elapsedMicroseconds;
      try {
        await stressChar.write(cmd, withResponse: true);
        result = result.recordSuccess(
          latency: Duration(
            microseconds: stopwatch.elapsedMicroseconds - start,
          ),
        );
      } catch (e) {
        result = result.recordFailure(
          typeName: e.runtimeType.toString(),
          status: e is GattOperationFailedException ? e.status : null,
        );
      }
      result = result.withElapsed(stopwatch.elapsed);
      yield result;

      // Wait until next tick or end-of-test, whichever comes first.
      final remaining = endTime - stopwatch.elapsed;
      final waitFor =
          remaining < config.interval ? remaining : config.interval;
      if (waitFor > Duration.zero) {
        await Future<void>.delayed(waitFor);
      }
    }
    stopwatch.stop();
    yield result.finished(elapsed: stopwatch.elapsed);
  }

  Stream<StressTestResult> runTimeoutProbe(
    TimeoutProbeConfig config,
    Connection connection,
  ) async* {
    final stressChar = await _resolveStressChar(connection);

    try {
      await stressChar.write(const ResetCommand().encode(), withResponse: true);
    } on Object {
      yield StressTestResult.initial().finished(elapsed: Duration.zero);
      return;
    }

    var result = StressTestResult.initial();
    final stopwatch = Stopwatch()..start();
    yield result;

    // Default per-op timeout is 10s; we ask the server to delay that
    // much plus config.delayPastTimeout so the client-side timer fires
    // deterministically.
    const defaultTimeoutMs = 10000;
    final delayMs = defaultTimeoutMs + config.delayPastTimeout.inMilliseconds;

    final start = stopwatch.elapsedMicroseconds;
    try {
      await stressChar.write(
        DelayAckCommand(delayMs: delayMs).encode(),
        withResponse: true,
      );
      result = result.recordSuccess(
        latency: Duration(
          microseconds: stopwatch.elapsedMicroseconds - start,
        ),
      );
    } catch (e) {
      result = result.recordFailure(
        typeName: e.runtimeType.toString(),
        status: e is GattOperationFailedException ? e.status : null,
      );
    }
    stopwatch.stop();
    yield result.finished(elapsed: stopwatch.elapsed);
  }

  Stream<StressTestResult> runFailureInjection(
    FailureInjectionConfig config,
    Connection connection,
  ) async* {
    final stressChar = await _resolveStressChar(connection);

    try {
      await stressChar.write(const ResetCommand().encode(), withResponse: true);
      await stressChar.write(const DropNextCommand().encode(), withResponse: true);
    } on Object {
      yield StressTestResult.initial().finished(elapsed: Duration.zero);
      return;
    }

    var result = StressTestResult.initial();
    final stopwatch = Stopwatch()..start();
    yield result;

    final payload = _generatePattern(20);
    final cmd = EchoCommand(payload).encode();

    for (var i = 0; i < config.writeCount; i++) {
      final start = stopwatch.elapsedMicroseconds;
      try {
        await stressChar.write(cmd, withResponse: true);
        result = result.recordSuccess(
          latency: Duration(
            microseconds: stopwatch.elapsedMicroseconds - start,
          ),
        );
      } catch (e) {
        result = result.recordFailure(
          typeName: e.runtimeType.toString(),
          status: e is GattOperationFailedException ? e.status : null,
        );
      }
      yield result;
    }
    stopwatch.stop();
    yield result.finished(elapsed: stopwatch.elapsed);
  }

  Stream<StressTestResult> runMtuProbe(
    MtuProbeConfig config,
    Connection connection,
  ) async* {
    final stressChar = await _resolveStressChar(connection);

    try {
      await stressChar.write(const ResetCommand().encode(), withResponse: true);
    } on Object {
      yield StressTestResult.initial().finished(elapsed: Duration.zero);
      return;
    }

    var result = StressTestResult.initial();
    final stopwatch = Stopwatch()..start();
    yield result;

    // Negotiate MTU.
    final mtuStart = stopwatch.elapsedMicroseconds;
    try {
      await connection.requestMtu(config.requestedMtu);
      result = result.recordSuccess(
        latency: Duration(
          microseconds: stopwatch.elapsedMicroseconds - mtuStart,
        ),
      );
    } catch (e) {
      result = result.recordFailure(
        typeName: e.runtimeType.toString(),
        status: e is GattOperationFailedException ? e.status : null,
      );
      yield result.finished(elapsed: stopwatch.elapsed);
      return;
    }

    // Tell server to return payloadBytes-sized reads.
    try {
      await stressChar.write(
        SetPayloadSizeCommand(sizeBytes: config.payloadBytes).encode(),
        withResponse: true,
      );
    } on Object {
      // If setPayloadSize fails, the read-length check will fail — but
      // we still proceed to record the per-cycle failures uniformly.
    }

    // Three rounds: write payloadBytes, read payloadBytes, verify length.
    for (var i = 0; i < 3; i++) {
      final start = stopwatch.elapsedMicroseconds;
      try {
        final payload = _generatePattern(config.payloadBytes);
        await stressChar.write(
          EchoCommand(payload).encode(),
          withResponse: true,
        );
        final readBack = await stressChar.read();
        if (readBack.length != config.payloadBytes) {
          throw StateError(
            'MTU read returned ${readBack.length} bytes, expected ${config.payloadBytes}',
          );
        }
        result = result.recordSuccess(
          latency: Duration(
            microseconds: stopwatch.elapsedMicroseconds - start,
          ),
        );
      } catch (e) {
        result = result.recordFailure(
          typeName: e.runtimeType.toString(),
          status: e is GattOperationFailedException ? e.status : null,
        );
      }
      yield result;
    }
    stopwatch.stop();
    yield result.finished(elapsed: stopwatch.elapsed);
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
