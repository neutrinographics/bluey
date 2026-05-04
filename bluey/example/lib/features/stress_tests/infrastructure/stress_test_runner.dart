import 'dart:async';
import 'dart:typed_data';

import 'package:bluey/bluey.dart';

import '../../../shared/stress_protocol.dart';
import '../domain/stress_test_config.dart';
import '../domain/stress_test_result.dart';

String _typeName(Object e) {
  if (e is BlueyPlatformException) {
    return 'BlueyPlatformException(${e.code ?? 'null'})';
  }
  return e.runtimeType.toString();
}

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
    var cancelled = false;
    controller = StreamController<StressTestResult>(
      onListen: () async {
        try {
          final stressChar = await _resolveStressChar(connection);

          if (!await _prologue(connection, stressChar)) {
            if (!cancelled && !controller.isClosed) {
              controller.add(
                StressTestResult.initial().finished(elapsed: Duration.zero),
              );
            }
            if (!controller.isClosed) await controller.close();
            return;
          }

          var result = StressTestResult.initial();
          final stopwatch = Stopwatch()..start();
          if (!cancelled && !controller.isClosed) controller.add(result);

          final payload = _generatePattern(config.payloadBytes);
          final cmd = EchoCommand(payload).encode();

          void publish(_OpOutcome outcome) {
            if (cancelled || controller.isClosed) return;
            if (!outcome.success &&
                outcome.typeName == 'DisconnectedException') {
              result = result.markConnectionLost();
            }
            result =
                outcome.success
                    ? result.recordSuccess(latency: outcome.latency!)
                    : result.recordFailure(
                      typeName: outcome.typeName!,
                      status: outcome.status,
                    );
            controller.add(result);
          }

          final futures = <Future<void>>[];
          for (var i = 0; i < config.count; i++) {
            final opStart = stopwatch.elapsedMicroseconds;
            futures.add(() async {
              try {
                await stressChar.write(cmd, withResponse: config.withResponse);
                publish(
                  _OpOutcome.success(
                    latency: Duration(
                      microseconds: stopwatch.elapsedMicroseconds - opStart,
                    ),
                  ),
                );
              } catch (e) {
                publish(
                  _OpOutcome.failure(
                    typeName: _typeName(e),
                    status: e is GattOperationFailedException ? e.status : null,
                  ),
                );
              }
            }());
          }

          await Future.wait(futures);
          stopwatch.stop();
          if (!cancelled && !controller.isClosed) {
            controller.add(result.finished(elapsed: stopwatch.elapsed));
          }
        } catch (error, stackTrace) {
          if (!cancelled && !controller.isClosed) {
            controller.addError(error, stackTrace);
          }
        } finally {
          if (!controller.isClosed) await controller.close();
        }
      },
      onCancel: () async {
        cancelled = true;
        if (!controller.isClosed) await controller.close();
      },
    );
    return controller.stream;
  }

  Stream<StressTestResult> runMixedOps(
    MixedOpsConfig config,
    Connection connection,
  ) {
    late final StreamController<StressTestResult> controller;
    var cancelled = false;
    controller = StreamController<StressTestResult>(
      onListen: () async {
        try {
          final stressChar = await _resolveStressChar(connection);

          if (!await _prologue(connection, stressChar)) {
            if (!cancelled && !controller.isClosed) {
              controller.add(
                StressTestResult.initial().finished(elapsed: Duration.zero),
              );
            }
            if (!controller.isClosed) await controller.close();
            return;
          }

          var result = StressTestResult.initial();
          final stopwatch = Stopwatch()..start();
          if (!cancelled && !controller.isClosed) controller.add(result);

          final payload = _generatePattern(20);
          final cmd = EchoCommand(payload).encode();

          void publish(_OpOutcome outcome) {
            if (cancelled || controller.isClosed) return;
            if (!outcome.success &&
                outcome.typeName == 'DisconnectedException') {
              result = result.markConnectionLost();
            }
            result =
                outcome.success
                    ? result.recordSuccess(latency: outcome.latency!)
                    : result.recordFailure(
                      typeName: outcome.typeName!,
                      status: outcome.status,
                    );
            controller.add(result);
          }

          Future<void> recordOp(Future<void> Function() op) async {
            final start = stopwatch.elapsedMicroseconds;
            try {
              await op();
              publish(
                _OpOutcome.success(
                  latency: Duration(
                    microseconds: stopwatch.elapsedMicroseconds - start,
                  ),
                ),
              );
            } catch (e) {
              publish(
                _OpOutcome.failure(
                  typeName: _typeName(e),
                  status: e is GattOperationFailedException ? e.status : null,
                ),
              );
            }
          }

          final futures = <Future<void>>[];
          for (var i = 0; i < config.iterations; i++) {
            futures.add(
              recordOp(() => stressChar.write(cmd, withResponse: true)),
            );
            futures.add(recordOp(() => stressChar.read()));
            futures.add(recordOp(() => connection.services(cache: false)));
            futures.add(
              recordOp(() => connection.requestMtu(Mtu.fromPlatform(247))),
            );
          }
          await Future.wait(futures);
          stopwatch.stop();
          if (!cancelled && !controller.isClosed) {
            controller.add(result.finished(elapsed: stopwatch.elapsed));
          }
        } catch (error, stackTrace) {
          if (!cancelled && !controller.isClosed) {
            controller.addError(error, stackTrace);
          }
        } finally {
          if (!controller.isClosed) await controller.close();
        }
      },
      onCancel: () async {
        cancelled = true;
        if (!controller.isClosed) await controller.close();
      },
    );
    return controller.stream;
  }

  Stream<StressTestResult> runSoak(
    SoakConfig config,
    Connection connection,
  ) async* {
    final stressChar = await _resolveStressChar(connection);

    if (!await _prologue(connection, stressChar)) {
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
          typeName: _typeName(e),
          status: e is GattOperationFailedException ? e.status : null,
        );
      }
      result = result.withElapsed(stopwatch.elapsed);
      yield result;

      // Wait until next tick or end-of-test, whichever comes first.
      final remaining = endTime - stopwatch.elapsed;
      final waitFor = remaining < config.interval ? remaining : config.interval;
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

    if (!await _prologue(connection, stressChar)) {
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
        latency: Duration(microseconds: stopwatch.elapsedMicroseconds - start),
      );
    } catch (e) {
      if (e is DisconnectedException) {
        result = result.markConnectionLost();
      }
      result = result.recordFailure(
        typeName: _typeName(e),
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

    if (!await _prologue(connection, stressChar)) {
      yield StressTestResult.initial().finished(elapsed: Duration.zero);
      return;
    }

    try {
      await stressChar.write(
        const DropNextCommand().encode(),
        withResponse: true,
      );
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
          typeName: _typeName(e),
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
      await connection.requestMtu(Mtu.fromPlatform(config.requestedMtu));
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
        typeName: _typeName(e),
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
          typeName: _typeName(e),
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

    if (!await _prologue(connection, stressChar)) {
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
        microseconds: stopwatch.elapsedMicroseconds - burstStartedAt!,
      );
      (latenciesPerId[id] ??= []).add(latency);
      if (latenciesPerId[id]!.length >= config.count &&
          !completer.isCompleted) {
        winningBurstId = id;
        completer.complete();
      }
    });

    // Kick the server. If the write fails, cancel the sub and return early.
    var writeSucceeded = true;
    try {
      await stressChar.write(
        BurstMeCommand(
          count: config.count,
          payloadSize: config.payloadBytes,
        ).encode(),
        withResponse: true,
      );
    } catch (e) {
      if (e is DisconnectedException) {
        result = result.markConnectionLost();
      }
      result = result.recordFailure(
        typeName: _typeName(e),
        status: e is GattOperationFailedException ? e.status : null,
      );
      writeSucceeded = false;
    } finally {
      if (!writeSucceeded) await sub.cancel();
    }

    if (!writeSucceeded) {
      stopwatch.stop();
      yield result.finished(elapsed: stopwatch.elapsed);
      return;
    }

    // Wait for all expected notifications. Per-test budget is
    // configurable via `config.timeout`; the default heuristic
    // (10 ms × count + 2 s) sizes for the post-I040 iOS-server
    // delivery rate (~2–3 ms / notification, queue-drain bound) with
    // a 5× safety margin.
    final timeout =
        config.timeout ?? Duration(milliseconds: 10 * config.count + 2000);
    try {
      await completer.future.timeout(timeout);
    } on TimeoutException {
      // nothing — handled below after sub is cancelled
    }
    await sub.cancel();

    // Pick the burst-id with the most arrivals as the result winner.
    // If a burst hit `count` mid-stream, `winningBurstId` was set by
    // the listener and the completer fired early — that's the same
    // burst we'd pick here. If the timeout fired with a partial
    // delivery, this surfaces what we actually received instead of
    // discarding it as a total failure (I316).
    int? bestBurstId;
    var bestArrivalCount = 0;
    for (final entry in latenciesPerId.entries) {
      if (entry.value.length > bestArrivalCount) {
        bestArrivalCount = entry.value.length;
        bestBurstId = entry.key;
      }
    }
    final winnerLatencies =
        bestBurstId != null ? latenciesPerId[bestBurstId]! : <Duration>[];
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

  /// Shared prologue for every stress test. Requests a higher MTU so
  /// first-run bursts with >20-byte payloads don't fail before auto-MTU
  /// negotiation completes, then sends `ResetCommand` to zero the
  /// server-side counters. MTU failure is swallowed — not every peer
  /// honours a higher MTU and that's fine; the test still runs (at the
  /// peer's default payload limit).
  ///
  /// Returns true if the reset succeeded; false if the reset failed,
  /// in which case the caller should emit a zero-elapsed final snapshot
  /// and close its stream.
  Future<bool> _prologue(
    Connection connection,
    RemoteCharacteristic stressChar,
  ) async {
    try {
      await connection.requestMtu(Mtu.fromPlatform(247));
    } catch (_) {
      // Swallow — MTU upgrade is best-effort.
    }

    try {
      await stressChar.write(const ResetCommand().encode(), withResponse: true);
      return true;
    } on Object {
      return false;
    }
  }

  Future<RemoteCharacteristic> _resolveStressChar(Connection connection) async {
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
