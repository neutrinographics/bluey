import 'dart:typed_data';

import 'package:bluey/bluey.dart';
import 'package:bluey_example/features/stress_tests/domain/stress_test_config.dart';
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
  });
}
