import 'dart:typed_data';

import 'package:bluey_example/shared/stress_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StressProtocol UUIDs', () {
    test('service and characteristic UUIDs use the bley a000 range', () {
      expect(
        StressProtocol.serviceUuid,
        equals('b1e7a001-0000-1000-8000-00805f9b34fb'),
      );
      expect(
        StressProtocol.charUuid,
        equals('b1e7a002-0000-1000-8000-00805f9b34fb'),
      );
    });
  });

  group('EchoCommand', () {
    test('encode prepends opcode 0x01 to payload', () {
      final cmd = EchoCommand(Uint8List.fromList([0xAA, 0xBB, 0xCC]));
      expect(
        cmd.encode(),
        equals(Uint8List.fromList([0x01, 0xAA, 0xBB, 0xCC])),
      );
    });

    test('encode handles empty payload', () {
      final cmd = EchoCommand(Uint8List(0));
      expect(cmd.encode(), equals(Uint8List.fromList([0x01])));
    });

    test('decode round-trips payload bytes', () {
      final original = EchoCommand(Uint8List.fromList([0x01, 0x02, 0x03]));
      final decoded = StressCommand.decode(original.encode());
      expect(decoded, isA<EchoCommand>());
      expect((decoded as EchoCommand).payload, equals(original.payload));
    });

    test('EchoCommand values are equal when payloads match', () {
      expect(
        EchoCommand(Uint8List.fromList([1, 2, 3])),
        equals(EchoCommand(Uint8List.fromList([1, 2, 3]))),
      );
    });

    test('EchoCommand constructor defensively copies payload', () {
      final mutable = Uint8List.fromList([1, 2, 3]);
      final cmd = EchoCommand(mutable);
      mutable[0] = 99;
      expect(
        cmd.payload[0],
        equals(1),
        reason: 'Mutating the caller\'s list must not change the command',
      );
    });
  });

  group('StressCommand.decode', () {
    test('throws on empty input', () {
      expect(
        () => StressCommand.decode(Uint8List(0)),
        throwsA(isA<StressProtocolException>()),
      );
    });

    test('throws on unknown opcode', () {
      expect(
        () => StressCommand.decode(Uint8List.fromList([0xFF])),
        throwsA(
          isA<StressProtocolException>().having(
            (e) => e.opcode,
            'opcode',
            0xFF,
          ),
        ),
      );
    });
  });

  group('BurstMeCommand', () {
    test('encode is [0x02, count_lo, count_hi, size_lo, size_hi]', () {
      const cmd = BurstMeCommand(count: 0x1234, payloadSize: 0x5678);
      expect(
        cmd.encode(),
        equals(Uint8List.fromList([0x02, 0x34, 0x12, 0x78, 0x56])),
      );
    });

    test('decode round-trips count and payloadSize', () {
      const original = BurstMeCommand(count: 100, payloadSize: 20);
      final decoded = StressCommand.decode(original.encode());
      expect(decoded, isA<BurstMeCommand>());
      final b = decoded as BurstMeCommand;
      expect(b.count, equals(100));
      expect(b.payloadSize, equals(20));
    });

    test('BurstMeCommand instances with equal fields are equal', () {
      expect(
        const BurstMeCommand(count: 5, payloadSize: 10),
        equals(const BurstMeCommand(count: 5, payloadSize: 10)),
      );
      expect(
        const BurstMeCommand(count: 5, payloadSize: 10).hashCode,
        equals(const BurstMeCommand(count: 5, payloadSize: 10).hashCode),
      );
    });
  });

  group('DelayAckCommand', () {
    test('encode is [0x03, ms_lo, ms_hi]', () {
      const cmd = DelayAckCommand(delayMs: 0x0102);
      expect(cmd.encode(), equals(Uint8List.fromList([0x03, 0x02, 0x01])));
    });

    test('decode round-trips delayMs', () {
      const original = DelayAckCommand(delayMs: 5000);
      final decoded = StressCommand.decode(original.encode());
      expect(decoded, isA<DelayAckCommand>());
      expect((decoded as DelayAckCommand).delayMs, equals(5000));
    });

    test('DelayAckCommand instances with equal delayMs are equal', () {
      expect(
        const DelayAckCommand(delayMs: 100),
        equals(const DelayAckCommand(delayMs: 100)),
      );
    });
  });

  group('SetPayloadSizeCommand', () {
    test('encode is [0x05, size_lo, size_hi]', () {
      const cmd = SetPayloadSizeCommand(sizeBytes: 244);
      expect(cmd.encode(), equals(Uint8List.fromList([0x05, 0xF4, 0x00])));
    });

    test('decode round-trips sizeBytes', () {
      const original = SetPayloadSizeCommand(sizeBytes: 247);
      final decoded = StressCommand.decode(original.encode());
      expect(decoded, isA<SetPayloadSizeCommand>());
      expect((decoded as SetPayloadSizeCommand).sizeBytes, equals(247));
    });

    test('SetPayloadSizeCommand instances with equal sizeBytes are equal', () {
      expect(
        const SetPayloadSizeCommand(sizeBytes: 247),
        equals(const SetPayloadSizeCommand(sizeBytes: 247)),
      );
    });
  });

  group('DropNextCommand', () {
    test('encode is [0x04]', () {
      const cmd = DropNextCommand();
      expect(cmd.encode(), equals(Uint8List.fromList([0x04])));
    });

    test('decode round-trips', () {
      const original = DropNextCommand();
      final decoded = StressCommand.decode(original.encode());
      expect(decoded, isA<DropNextCommand>());
    });

    test('all DropNextCommand instances are equal', () {
      expect(const DropNextCommand(), equals(const DropNextCommand()));
    });
  });

  group('ResetCommand', () {
    test('encode is [0x06]', () {
      const cmd = ResetCommand();
      expect(cmd.encode(), equals(Uint8List.fromList([0x06])));
    });

    test('decode round-trips', () {
      const original = ResetCommand();
      final decoded = StressCommand.decode(original.encode());
      expect(decoded, isA<ResetCommand>());
    });

    test('all ResetCommand instances are equal', () {
      expect(const ResetCommand(), equals(const ResetCommand()));
    });
  });
}
