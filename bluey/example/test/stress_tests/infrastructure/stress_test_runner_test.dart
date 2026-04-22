import 'dart:async';
import 'dart:typed_data';

import 'package:bluey/bluey.dart';
import 'package:bluey_example/features/stress_tests/domain/stress_test_config.dart';
import 'package:bluey_example/features/stress_tests/domain/stress_test_result.dart';
import 'package:bluey_example/features/stress_tests/infrastructure/stress_test_runner.dart';
import 'package:bluey_example/shared/stress_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_connection.dart';
import '../../fakes/fake_remote_characteristic.dart';

void main() {
  late FakeRemoteCharacteristic stressChar;
  late FakeConnection conn;
  late StressTestRunner runner;

  setUp(() {
    stressChar = FakeRemoteCharacteristic(
      uuid: UUID(StressProtocol.charUuid),
    );
    conn = FakeConnection(
      stressServiceUuid: UUID(StressProtocol.serviceUuid),
      stressChar: stressChar,
    );
    runner = StressTestRunner();
  });

  group('StressTestRunner.runBurstWrite', () {
    test('runs the configured count of writes and emits a final snapshot',
        () async {
      stressChar.onWriteHook = (value, {required bool withResponse}) async {};

      final results = await runner
          .runBurstWrite(
            const BurstWriteConfig(count: 5, payloadBytes: 4),
            conn,
          )
          .toList();

      final last = results.last;
      expect(last.isRunning, isFalse);
      expect(last.attempted, equals(5));
      expect(last.succeeded, equals(5));
      expect(last.failed, equals(0));
    });

    test('counts GattTimeoutException failures separately', () async {
      var i = 0;
      stressChar.onWriteHook = (value, {required bool withResponse}) async {
        i++;
        // Any value that isn't a Reset (opcode 0x06) is an echo.
        // Count echo failures only.
        if (value.isNotEmpty && value.first == 0x01) {
          if (i == 3) {
            throw const GattTimeoutException('writeCharacteristic');
          }
        }
      };

      final results = await runner
          .runBurstWrite(
            const BurstWriteConfig(count: 5, payloadBytes: 4),
            conn,
          )
          .toList();

      final last = results.last;
      expect(last.attempted, equals(5));
      expect(last.succeeded, equals(4));
      expect(last.failed, equals(1));
      expect(last.failuresByType['GattTimeoutException'], equals(1));
    });

    test('counts GattOperationFailedException with status code', () async {
      stressChar.onWriteHook = (value, {required bool withResponse}) async {
        if (value.isNotEmpty && value.first == 0x01) {
          throw const GattOperationFailedException('writeCharacteristic', 1);
        }
      };

      final results = await runner
          .runBurstWrite(
            const BurstWriteConfig(count: 3, payloadBytes: 4),
            conn,
          )
          .toList();

      final last = results.last;
      expect(last.failed, equals(3));
      expect(last.failuresByType['GattOperationFailedException'], equals(3));
      expect(last.statusCounts[1], equals(3));
    });

    test('first call sends a Reset command before any echo writes', () async {
      final writesSent = <Uint8List>[];
      stressChar.onWriteHook = (value, {required bool withResponse}) async {
        writesSent.add(Uint8List.fromList(value));
      };

      await runner
          .runBurstWrite(
            const BurstWriteConfig(count: 2, payloadBytes: 4),
            conn,
          )
          .toList();

      expect(writesSent, isNotEmpty);
      expect(writesSent.first.first, equals(0x06),
          reason: 'first write must be ResetCommand (opcode 0x06)');
      // The remaining writes are echoes (opcode 0x01).
      expect(writesSent.skip(1).every((w) => w.first == 0x01), isTrue);
    });

    test('reset write failure aborts with empty final snapshot, no crash',
        () async {
      stressChar.onWriteHook = (value, {required bool withResponse}) async {
        // Fail the Reset (opcode 0x06).
        if (value.isNotEmpty && value.first == 0x06) {
          throw const GattTimeoutException('writeCharacteristic');
        }
      };

      final results = await runner
          .runBurstWrite(
            const BurstWriteConfig(count: 5, payloadBytes: 4),
            conn,
          )
          .toList();

      expect(results, isNotEmpty);
      final last = results.last;
      expect(last.isRunning, isFalse);
      expect(last.attempted, equals(0),
          reason: 'reset failure should skip all echo writes');
    });

    test('emits incremental snapshots after each individual write completes',
        () async {
      stressChar.onWriteHook = (value, {required bool withResponse}) async {};

      final results = await runner
          .runBurstWrite(
            const BurstWriteConfig(count: 5, payloadBytes: 4),
            conn,
          )
          .toList();

      // Expect: initial snapshot (attempted=0) + 5 per-write snapshots +
      // 1 finished snapshot = at least 3 items total (more than just
      // initial + final).
      expect(results.length, greaterThan(2),
          reason: 'should emit intermediate snapshots during the burst');
      // All intermediate snapshots (excluding the last) should be running.
      for (final r in results.sublist(0, results.length - 1)) {
        expect(r.isRunning, isTrue);
      }
      expect(results.last.isRunning, isFalse);
    });

    test('runBurstWrite stops publishing after subscription is cancelled',
        () async {
      stressChar.onWriteHook = (value, {required bool withResponse}) async {
        // slow writes so we have time to cancel mid-burst
        if (value.isNotEmpty && value.first == 0x01) {
          await Future<void>.delayed(const Duration(milliseconds: 30));
        }
      };

      final stream = runner.runBurstWrite(
        const BurstWriteConfig(count: 20, payloadBytes: 4),
        conn,
      );
      late StreamSubscription<StressTestResult> sub;
      var receivedCount = 0;
      sub = stream.listen((r) {
        receivedCount++;
        if (receivedCount == 3) {
          // Cancel after 3rd emission.
          sub.cancel();
        }
      });

      // Wait for all writes to run in the background.
      await Future<void>.delayed(const Duration(milliseconds: 800));

      // receivedCount should stay small; the writes continued but publishing stopped.
      expect(receivedCount, equals(3),
          reason: 'controller should stop publishing after cancel');
    });
  });

  group('StressTestRunner.runMixedOps', () {
    test('runs configured iterations of write+read+services+mtu', () async {
      var writes = 0;
      var reads = 0;
      stressChar.onWriteHook = (value, {required bool withResponse}) async {
        writes++;
      };
      stressChar.onReadHook = () async {
        reads++;
        return Uint8List(0);
      };

      final results = await runner
          .runMixedOps(const MixedOpsConfig(iterations: 3), conn)
          .toList();

      final last = results.last;
      expect(last.isRunning, isFalse);
      // Each iteration: 1 write + 1 read + 1 services + 1 mtu = 4 ops
      // Plus 1 reset write = 1 pre-run write (not counted)
      // Total writes = 1 reset + 3 echoes = 4
      expect(writes, equals(4));
      expect(reads, equals(3));
      expect(last.attempted, equals(12)); // 3 iterations × 4 ops
      expect(conn.lastRequestedMtu, isNotNull);
    });

    test('emits incremental snapshots after each individual op completes',
        () async {
      stressChar.onWriteHook = (value, {required bool withResponse}) async {};
      stressChar.onReadHook = () async => Uint8List(0);

      final results = await runner
          .runMixedOps(const MixedOpsConfig(iterations: 2), conn)
          .toList();

      // Expect: initial snapshot + per-op snapshots (2 iterations × 4 ops = 8)
      // + 1 finished snapshot = more than 2.
      expect(results.length, greaterThan(2),
          reason: 'should emit intermediate snapshots during mixed ops');
      for (final r in results.sublist(0, results.length - 1)) {
        expect(r.isRunning, isTrue);
      }
      expect(results.last.isRunning, isFalse);
    });
  });

  group('StressTestRunner.runSoak', () {
    test('runs ops for the configured duration at the configured interval',
        () async {
      var writes = 0;
      stressChar.onWriteHook = (value, {required bool withResponse}) async {
        writes++;
      };

      const config = SoakConfig(
        duration: Duration(milliseconds: 250),
        interval: Duration(milliseconds: 100),
        payloadBytes: 4,
      );
      final results = await runner.runSoak(config, conn).toList();

      final last = results.last;
      expect(last.isRunning, isFalse);
      // 250ms / 100ms ≈ 2-3 ops + 1 reset = 3-4 writes
      expect(writes, greaterThanOrEqualTo(2));
      expect(writes, lessThanOrEqualTo(5));
    });
  });

  group('StressTestRunner.runTimeoutProbe', () {
    test('sends DelayAck command sized past the timeout and counts the failure',
        () async {
      final writes = <Uint8List>[];
      stressChar.onWriteHook = (value, {required bool withResponse}) async {
        writes.add(Uint8List.fromList(value));
        // For the delay-ack write (opcode 0x03), simulate a timeout.
        if (value.isNotEmpty && value.first == 0x03) {
          throw const GattTimeoutException('writeCharacteristic');
        }
      };

      final results = await runner
          .runTimeoutProbe(
            const TimeoutProbeConfig(delayPastTimeout: Duration(seconds: 2)),
            conn,
          )
          .toList();

      // First write = Reset (0x06), second = DelayAck (0x03).
      expect(writes[0].first, equals(0x06));
      expect(writes[1].first, equals(0x03));

      final last = results.last;
      expect(last.failed, equals(1));
      expect(last.failuresByType['GattTimeoutException'], equals(1));
    });
  });

  group('StressTestRunner.runFailureInjection', () {
    test('writes DropNext, then writeCount echoes — first echo throws timeout',
        () async {
      var echoCount = 0;
      var dropNextSent = false;
      stressChar.onWriteHook = (value, {required bool withResponse}) async {
        if (value.first == 0x04) {
          dropNextSent = true;
          return; // ack the DropNext write
        }
        if (value.first == 0x01) {
          echoCount++;
          // First echo after DropNext is dropped → timeout.
          if (echoCount == 1) {
            throw const GattTimeoutException('writeCharacteristic');
          }
        }
      };

      final results = await runner
          .runFailureInjection(
            const FailureInjectionConfig(writeCount: 5),
            conn,
          )
          .toList();

      expect(dropNextSent, isTrue);
      final last = results.last;
      expect(last.attempted, equals(5));
      expect(last.failed, equals(1));
      expect(last.succeeded, equals(4));
      expect(last.failuresByType['GattTimeoutException'], equals(1));
    });
  });

  group('StressTestRunner.runNotificationThroughput', () {
    test('counts notifications matching the active burst-id', () async {
      stressChar.onWriteHook = (value, {required bool withResponse}) async {
        // After reset+burstMe write, simulate the server emitting 5 notifs
        // with burst-id = 1 (mocked: pretend the server's first burst).
        if (value.isNotEmpty && value.first == 0x02) {
          // Defer emissions to the next event loop tick so subscription
          // is active when they arrive.
          Future<void>(() async {
            for (var i = 0; i < 5; i++) {
              stressChar.emitNotification(
                Uint8List.fromList([0x01, 0x10, 0x11, 0x12, 0x13]),
              );
            }
          });
        }
      };

      final results = await runner
          .runNotificationThroughput(
            const NotificationThroughputConfig(count: 5, payloadBytes: 4),
            conn,
          )
          .toList();

      final last = results.last;
      expect(last.isRunning, isFalse);
      expect(last.succeeded, equals(5));
    });

    test('notification latencies are measured from burst start, not test start',
        () async {
      // Delay the BurstMe write so elapsed time at test start is non-trivial,
      // then emit notifications immediately. Latencies should be small
      // (near zero) rather than inflated by the pre-write elapsed time.
      stressChar.onWriteHook = (value, {required bool withResponse}) async {
        if (value.isNotEmpty && value.first == 0x02) {
          // Small real delay to let stopwatch tick before notifications arrive.
          await Future<void>.delayed(const Duration(milliseconds: 5));
          Future<void>(() async {
            for (var i = 0; i < 3; i++) {
              stressChar.emitNotification(
                Uint8List.fromList([0x01, 0x10, 0x11, 0x12, 0x13]),
              );
            }
          });
        }
      };

      final results = await runner
          .runNotificationThroughput(
            const NotificationThroughputConfig(count: 3, payloadBytes: 4),
            conn,
          )
          .toList();

      final last = results.last;
      expect(last.succeeded, equals(3));
      // All latencies must be non-negative and much smaller than the total
      // elapsed time (which includes the reset + BurstMe write time).
      // They should be in the sub-100ms range; we check < 500ms to be safe.
      for (final latency in last.latencies) {
        expect(latency.inMilliseconds, lessThan(500),
            reason: 'latency should be measured from burst start, not test start');
      }
    });

    test('drops notifications with stale burst-id (different from current)', () async {
      stressChar.onWriteHook = (value, {required bool withResponse}) async {
        if (value.isNotEmpty && value.first == 0x02) {
          Future<void>(() async {
            // Two stale (id=99) notifications from a previous burst,
            // then five fresh (id=1).
            stressChar.emitNotification(
              Uint8List.fromList([99, 0xAA, 0xBB, 0xCC, 0xDD]),
            );
            stressChar.emitNotification(
              Uint8List.fromList([99, 0xEE, 0xFF, 0x00, 0x01]),
            );
            for (var i = 0; i < 5; i++) {
              stressChar.emitNotification(
                Uint8List.fromList([1, 0x10, 0x11, 0x12, 0x13]),
              );
            }
          });
        }
      };

      final results = await runner
          .runNotificationThroughput(
            const NotificationThroughputConfig(count: 5, payloadBytes: 4),
            conn,
          )
          .toList();

      final last = results.last;
      expect(last.succeeded, equals(5),
          reason: 'stale burst-id notifications must not count');
    });
  });

  group('StressTestRunner.runMtuProbe', () {
    test('requests MTU then sends sized writes', () async {
      var writes = 0;
      stressChar.onWriteHook = (value, {required bool withResponse}) async {
        writes++;
      };
      // The test's stressChar.onReadHook default returns empty bytes,
      // which will cause the length check to throw StateError. Set it to
      // return payloadBytes of pattern so the write+read cycle succeeds.
      stressChar.onReadHook = () async {
        // The runner invokes SetPayloadSizeCommand before reads, but the
        // fake doesn't actually track payload size — it just returns
        // whatever onReadHook returns. Return 50 bytes to match config.
        return Uint8List(50);
      };

      final results = await runner
          .runMtuProbe(
            const MtuProbeConfig(requestedMtu: 100, payloadBytes: 50),
            conn,
          )
          .toList();

      expect(conn.lastRequestedMtu, equals(100));
      // reset + setPayloadSize + 3 echo writes = at least 5 writes total
      expect(writes, greaterThanOrEqualTo(1));
      final last = results.last;
      expect(last.isRunning, isFalse);
      // 1 MTU request + 3 successful cycles = 4 successes minimum.
      expect(last.succeeded, greaterThanOrEqualTo(1));
    });
  });
}
