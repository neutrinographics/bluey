import 'dart:typed_data';

import 'package:bluey/bluey.dart';

import '../../../shared/stress_protocol.dart';

/// Server-side dispatcher for the stress test service.
///
/// State (`_lastEcho`, `_dropNextWrite`, `_payloadSize`, `_burstId`,
/// `_abortBurst`) is per-instance and shared across all connected
/// centrals — matches BLE peripheral semantics (one GATT database per
/// peripheral). Reset on server reconstruction or on receipt of a
/// [ResetCommand].
class StressServiceHandler {
  Uint8List _lastEcho = Uint8List(0);
  bool _dropNextWrite = false;
  // ignore: prefer_final_fields — mutated by Tasks 5-6 handlers.
  int _payloadSize = 20;
  // ignore: unused_field, prefer_final_fields — used by Tasks 5-6 burst handler.
  int _burstId = 0;
  // ignore: unused_field, prefer_final_fields — used by Tasks 5-6 burst handler.
  bool _abortBurst = false;

  /// Processes a write to [StressProtocol.charUuid]. Decodes the
  /// command, mutates server state, responds and/or notifies as
  /// appropriate.
  Future<void> onWrite(WriteRequest req, Server server) async {
    if (_dropNextWrite) {
      _dropNextWrite = false;
      return; // No response, no notification — client times out.
    }

    final StressCommand cmd;
    try {
      cmd = StressCommand.decode(req.value);
    } on StressProtocolException {
      if (req.responseNeeded) {
        await server.respondToWrite(
          req,
          status: GattResponseStatus.requestNotSupported,
        );
      }
      return;
    }

    switch (cmd) {
      case EchoCommand(:final payload):
        _lastEcho = payload;
        if (req.responseNeeded) {
          await server.respondToWrite(req, status: GattResponseStatus.success);
        }
        await server.notify(UUID(StressProtocol.charUuid), data: payload);
      // Other cases added in Tasks 5 and 6.
      case _:
        // Stub: future opcodes acknowledged but not yet implemented.
        if (req.responseNeeded) {
          await server.respondToWrite(req, status: GattResponseStatus.success);
        }
    }
  }

  /// Returns bytes for a read on [StressProtocol.charUuid]. If
  /// [_lastEcho] is non-empty, returns it; otherwise returns
  /// [_payloadSize] bytes of deterministic pattern.
  Uint8List onRead() {
    if (_lastEcho.isNotEmpty) return _lastEcho;
    return _generatePattern(_payloadSize);
  }

  static Uint8List _generatePattern(int size) {
    final out = Uint8List(size);
    for (var i = 0; i < size; i++) {
      out[i] = i & 0xff;
    }
    return out;
  }
}
