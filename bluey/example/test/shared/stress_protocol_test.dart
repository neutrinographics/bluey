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
      expect(cmd.encode(), equals(Uint8List.fromList([0x01, 0xAA, 0xBB, 0xCC])));
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
      expect(cmd.payload[0], equals(1),
          reason: 'Mutating the caller\'s list must not change the command');
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
        throwsA(isA<StressProtocolException>()
            .having((e) => e.opcode, 'opcode', 0xFF)),
      );
    });
  });
}
