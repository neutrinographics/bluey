import 'dart:typed_data';

import 'package:collection/collection.dart';

/// UUIDs and command framing for the stress test service hosted by the
/// example server. Shared between client (stress_tests feature) and
/// server (stress_service_handler). NOT part of the bluey library — this
/// is example-app scaffolding for in-app stress testing only.
class StressProtocol {
  /// Stress service UUID. Uses the `b1e7` ("bley") prefix matching the
  /// lifecycle service; `a000` range is reserved for app-level services.
  static const String serviceUuid = 'b1e7a001-0000-1000-8000-00805f9b34fb';

  /// The single characteristic on the stress service. Properties: read,
  /// write, writeWithoutResponse, notify.
  static const String charUuid = 'b1e7a002-0000-1000-8000-00805f9b34fb';

  StressProtocol._();
}

/// Sealed Command-pattern hierarchy. Each subclass owns its encode and
/// participates in the central [decode] dispatcher.
sealed class StressCommand {
  const StressCommand();

  /// Serialize this command to bytes for transport over a GATT write.
  /// First byte is always the opcode; remaining bytes are
  /// command-specific.
  Uint8List encode();

  /// Reconstruct a [StressCommand] from a write payload received by the
  /// server. Throws [StressProtocolException] for empty input or unknown
  /// opcode.
  static StressCommand decode(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw const StressProtocolException(
        opcode: null,
        message: 'Empty stress command payload',
      );
    }
    final opcode = bytes[0];
    final body = bytes.sublist(1);
    switch (opcode) {
      case 0x01:
        return EchoCommand(body);
      case 0x02:
        if (body.length < 4) {
          throw StressProtocolException(
            opcode: opcode,
            message: 'BurstMe payload too short (${body.length}, need 4)',
          );
        }
        final view = body.buffer.asByteData(body.offsetInBytes, 4);
        return BurstMeCommand(
          count: view.getUint16(0, Endian.little),
          payloadSize: view.getUint16(2, Endian.little),
        );
      case 0x03:
        if (body.length < 2) {
          throw StressProtocolException(
            opcode: opcode,
            message: 'DelayAck payload too short (${body.length}, need 2)',
          );
        }
        return DelayAckCommand(
          delayMs: body.buffer
              .asByteData(body.offsetInBytes, 2)
              .getUint16(0, Endian.little),
        );
      case 0x05:
        if (body.length < 2) {
          throw StressProtocolException(
            opcode: opcode,
            message: 'SetPayloadSize payload too short (${body.length}, need 2)',
          );
        }
        return SetPayloadSizeCommand(
          sizeBytes: body.buffer
              .asByteData(body.offsetInBytes, 2)
              .getUint16(0, Endian.little),
        );
      default:
        throw StressProtocolException(
          opcode: opcode,
          message: 'Unknown stress command opcode: 0x${opcode.toRadixString(16).padLeft(2, '0')}',
        );
    }
  }
}

/// Echo: server stores [payload], returns it on next read, fires a
/// notification with it. Opcode 0x01.
class EchoCommand extends StressCommand {
  final Uint8List payload;

  EchoCommand(Uint8List payload) : payload = Uint8List.fromList(payload);

  @override
  Uint8List encode() {
    final out = Uint8List(payload.length + 1);
    out[0] = 0x01;
    out.setRange(1, out.length, payload);
    return out;
  }

  @override
  bool operator ==(Object other) =>
      other is EchoCommand &&
      const ListEquality<int>().equals(other.payload, payload);

  @override
  int get hashCode => Object.hashAll(payload);
}

/// BurstMe: server fires `count` notifications back-to-back, each
/// `payloadSize` bytes (deterministic pattern), prepended with a
/// burst-id byte. Opcode 0x02.
class BurstMeCommand extends StressCommand {
  final int count;
  final int payloadSize;
  const BurstMeCommand({required this.count, required this.payloadSize});

  @override
  Uint8List encode() {
    final out = Uint8List(5);
    out[0] = 0x02;
    out.buffer.asByteData().setUint16(1, count, Endian.little);
    out.buffer.asByteData().setUint16(3, payloadSize, Endian.little);
    return out;
  }

  @override
  bool operator ==(Object other) =>
      other is BurstMeCommand &&
      other.count == count &&
      other.payloadSize == payloadSize;

  @override
  int get hashCode => Object.hash(count, payloadSize);
}

/// DelayAck: server waits [delayMs] ms before responding. Opcode 0x03.
class DelayAckCommand extends StressCommand {
  final int delayMs;
  const DelayAckCommand({required this.delayMs});

  @override
  Uint8List encode() {
    final out = Uint8List(3);
    out[0] = 0x03;
    out.buffer.asByteData().setUint16(1, delayMs, Endian.little);
    return out;
  }

  @override
  bool operator ==(Object other) =>
      other is DelayAckCommand && other.delayMs == delayMs;

  @override
  int get hashCode => delayMs.hashCode;
}

/// SetPayloadSize: server's next read returns [sizeBytes] of pattern.
/// Opcode 0x05.
class SetPayloadSizeCommand extends StressCommand {
  final int sizeBytes;
  const SetPayloadSizeCommand({required this.sizeBytes});

  @override
  Uint8List encode() {
    final out = Uint8List(3);
    out[0] = 0x05;
    out.buffer.asByteData().setUint16(1, sizeBytes, Endian.little);
    return out;
  }

  @override
  bool operator ==(Object other) =>
      other is SetPayloadSizeCommand && other.sizeBytes == sizeBytes;

  @override
  int get hashCode => sizeBytes.hashCode;
}

/// Thrown when stress command bytes can't be decoded.
class StressProtocolException implements Exception {
  /// The raw opcode byte, or `null` if the payload was empty.
  final int? opcode;
  final String message;
  const StressProtocolException({required this.opcode, required this.message});
  @override
  String toString() => 'StressProtocolException: $message';
}
