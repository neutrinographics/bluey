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

/// Thrown when stress command bytes can't be decoded.
class StressProtocolException implements Exception {
  /// The raw opcode byte, or `null` if the payload was empty.
  final int? opcode;
  final String message;
  const StressProtocolException({required this.opcode, required this.message});
  @override
  String toString() => 'StressProtocolException: $message';
}
