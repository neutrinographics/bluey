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
  ) {
    late final StreamController<StressTestResult> controller;
    controller = StreamController<StressTestResult>(
      onListen: () async {
        try {
          final stressChar = await _resolveStressChar(connection);

          // Test isolation: clean baseline before measuring. Failures here
          // abort the run with an empty final snapshot — reset is prologue,
          // not measurement.
          try {
            await stressChar.write(
                const ResetCommand().encode(), withResponse: true);
          } on Object {
            controller
                .add(StressTestResult.initial().finished(elapsed: Duration.zero));
            await controller.close();
            return;
          }

          var result = StressTestResult.initial();
          final stopwatch = Stopwatch()..start();
          controller.add(result);

          final payload = _generatePattern(config.payloadBytes);
          final cmd = EchoCommand(payload).encode();

          void publish(_OpOutcome outcome) {
            if (!outcome.success &&
                outcome.typeName == 'DisconnectedException') {
              result = result.markConnectionLost();
            }
            result = outcome.success
                ? result.recordSuccess(latency: outcome.latency!)
                : result.recordFailure(
                    typeName: outcome.typeName!, status: outcome.status);
            if (!controller.isClosed) controller.add(result);
          }

          final futures = <Future<void>>[];
          for (var i = 0; i < config.count; i++) {
            final opStart = stopwatch.elapsedMicroseconds;
            futures.add(() async {
              try {
                await stressChar.write(cmd, withResponse: config.withResponse);
                publish(_OpOutcome.success(
                  latency: Duration(
                      microseconds:
                          stopwatch.elapsedMicroseconds - opStart),
                ));
              } catch (e) {
                publish(_OpOutcome.failure(
                  typeName: e.runtimeType.toString(),
                  status:
                      e is GattOperationFailedException ? e.status : null,
                ));
              }
            }());
          }

          await Future.wait(futures);
          stopwatch.stop();
          if (!controller.isClosed) {
            controller.add(result.finished(elapsed: stopwatch.elapsed));
          }
        } catch (error, stackTrace) {
          if (!controller.isClosed) controller.addError(error, stackTrace);
        } finally {
          if (!controller.isClosed) await controller.close();
        }
      },
    );
    return controller.stream;
  }

  Stream<StressTestResult> runMixedOps(
    MixedOpsConfig config,
    Connection connection,
  ) {
    late final StreamController<StressTestResult> controller;
    controller = StreamController<StressTestResult>(
      onListen: () async {
        try {
          final stressChar = await _resolveStressChar(connection);

          try {
            await stressChar.write(
                const ResetCommand().encode(), withResponse: true);
          } on Object {
            controller.add(
                StressTestResult.initial().finished(elapsed: Duration.zero));
            await controller.close();
            return;
          }

          var result = StressTestResult.initial();
          final stopwatch = Stopwatch()..start();
          controller.add(result);

          final payload = _generatePattern(20);
          final cmd = EchoCommand(payload).encode();

          void publish(_OpOutcome outcome) {
            if (!outcome.success &&
                outcome.typeName == 'DisconnectedException') {
              result = result.markConnectionLost();
            }
            result = outcome.success
                ? result.recordSuccess(latency: outcome.latency!)
                : result.recordFailure(
                    typeName: outcome.typeName!, status: outcome.status);
            if (!controller.isClosed) controller.add(result);
          }

          Future<void> recordOp(Future<void> Function() op) async {
            final start = stopwatch.elapsedMicroseconds;
            try {
              await op();
              publish(_OpOutcome.success(
                latency: Duration(
                    microseconds: stopwatch.elapsedMicroseconds - start),
              ));
            } catch (e) {
              publish(_OpOutcome.failure(
                typeName: e.runtimeType.toString(),
                status: e is GattOperationFailedException ? e.status : null,
              ));
            }
          }

          final futures = <Future<void>>[];
          for (var i = 0; i < config.iterations; i++) {
            futures
                .add(recordOp(() => stressChar.write(cmd, withResponse: true)));
            futures.add(recordOp(() => stressChar.read()));
            futures.add(recordOp(() => connection.services(cache: false)));
            futures.add(recordOp(() => connection.requestMtu(247)));
          }
          await Future.wait(futures);
          stopwatch.stop();
          if (!controller.isClosed) {
            controller.add(result.finished(elapsed: stopwatch.elapsed));
          }
        } catch (error, stackTrace) {
          if (!controller.isClosed) controller.addError(error, stackTrace);
        } finally {
          if (!controller.isClosed) await controller.close();
        }
      },
    );
    return controller.stream;
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
        if (e is DisconnectedException) {
          result = result.markConnectionLost();
        }
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
      if (e is DisconnectedException) {
        result = result.markConnectionLost();
      }
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
        if (e is DisconnectedException) {
          result = result.markConnectionLost();
        }
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
      if (e is DisconnectedException) {
        result = result.markConnectionLost();
      }
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
        if (e is DisconnectedException) {
          result = result.markConnectionLost();
        }
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

    // Track latencies per burst-id. The first id to accumulate [config.count]
    // notifications is the winning (current) burst; all other ids are
    // stragglers from a previous (cancelled) burst and are dropped.
    final latenciesPerId = <int, List<Duration>>{};
    int? winningBurstId;
    int? burstStartedAt;
    final completer = Completer<void>();

    final sub = stressChar.notifications.listen((bytes) {
      if (bytes.isEmpty) return;
      final id = bytes[0];
      // Once a winner is determined, drop notifications from other burst-ids.
      if (winningBurstId != null && id != winningBurstId) return;
      // Record the moment the first matching notification arrives as the
      // burst start reference, so latency = time since server started emitting.
      burstStartedAt ??= stopwatch.elapsedMicroseconds;
      final latency = Duration(
          microseconds: stopwatch.elapsedMicroseconds - burstStartedAt!);
      (latenciesPerId[id] ??= []).add(latency);
      if (latenciesPerId[id]!.length >= config.count &&
          !completer.isCompleted) {
        winningBurstId = id;
        completer.complete();
      }
    });

    // Kick the server.
    try {
      await stressChar.write(
        BurstMeCommand(count: config.count, payloadSize: config.payloadBytes)
            .encode(),
        withResponse: true,
      );
    } catch (e) {
      if (e is DisconnectedException) {
        result = result.markConnectionLost();
      }
      result = result.recordFailure(
        typeName: e.runtimeType.toString(),
        status: e is GattOperationFailedException ? e.status : null,
      );
      await sub.cancel();
      stopwatch.stop();
      yield result.finished(elapsed: stopwatch.elapsed);
      return;
    }

    // Wait for all expected notifications, with a generous timeout
    // proportional to count (1ms per notification + 1s overhead).
    final timeout = Duration(milliseconds: config.count + 1000);
    try {
      await completer.future.timeout(timeout);
    } on TimeoutException {
      // nothing — handled below after sub is cancelled
    }
    await sub.cancel();

    // Only count the winning burst's notifications as successes; everything
    // else is a straggler and should not appear in the result.
    final winnerLatencies =
        winningBurstId != null ? latenciesPerId[winningBurstId]! : <Duration>[];
    for (final l in winnerLatencies) {
      result = result.recordSuccess(latency: l);
    }
    final missing = config.count - winnerLatencies.length;
    for (var i = 0; i < missing; i++) {
      result = result.recordFailure(typeName: 'NotificationTimeout');
    }

    stopwatch.stop();
    yield result.finished(elapsed: stopwatch.elapsed);
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
