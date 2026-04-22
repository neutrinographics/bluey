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
  int _payloadSize = 20;
  int _burstId = 0;
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

      case BurstMeCommand(:final count, :final payloadSize):
        _abortBurst = false;
        _burstId = (_burstId + 1) & 0xff;
        final thisBurstId = _burstId;
        if (req.responseNeeded) {
          await server.respondToWrite(req, status: GattResponseStatus.success);
        }
        for (var i = 0; i < count; i++) {
          if (_abortBurst) break;
          final pattern = _generatePattern(payloadSize);
          final framed = Uint8List(pattern.length + 1)
            ..[0] = thisBurstId
            ..setRange(1, pattern.length + 1, pattern);
          await server.notify(UUID(StressProtocol.charUuid), data: framed);
        }

      case DelayAckCommand(:final delayMs):
        await Future<void>.delayed(Duration(milliseconds: delayMs));
        if (req.responseNeeded) {
          await server.respondToWrite(req, status: GattResponseStatus.success);
        }

      case DropNextCommand():
        _dropNextWrite = true;
        if (req.responseNeeded) {
          await server.respondToWrite(req, status: GattResponseStatus.success);
        }

      case SetPayloadSizeCommand(:final sizeBytes):
        _payloadSize = sizeBytes;
        if (req.responseNeeded) {
          await server.respondToWrite(req, status: GattResponseStatus.success);
        }

      // ResetCommand stays as a placeholder until Task 6.
      case ResetCommand():
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
