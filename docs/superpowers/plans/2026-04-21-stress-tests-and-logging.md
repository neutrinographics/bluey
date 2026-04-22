# In-App Stress Tests + Library Logging Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an in-app stress test tool in the example app (7 tests against a custom 6-opcode GATT service) plus lightweight `dart:developer.log` instrumentation across the bluey library at ~15-20 key points.

**Architecture:** Stress tests live entirely in `bluey/example/lib/features/stress_tests/` and `bluey/example/lib/shared/stress_protocol.dart`; the example server hosts the stress service via `bluey/example/lib/features/server/infrastructure/stress_service_handler.dart`. The bluey library is touched only for logging — no new files, no API changes, just `dart:developer.log` calls. UI button on `ConnectionScreen` is visibility-gated by whether the connected peer's discovered services include the stress service UUID.

**Tech Stack:** Dart, Flutter, flutter_bloc (existing example pattern), get_it (existing DI), mocktail + fake_async (existing test patterns), dart:developer.log (logging)

**Spec:** `docs/superpowers/specs/2026-04-21-stress-tests-and-logging-design.md`

---

## File map

### New files (created by this plan)

```
bluey/example/lib/shared/
  stress_protocol.dart                                  (Tasks 1-3)

bluey/example/lib/features/server/infrastructure/
  stress_service_handler.dart                           (Tasks 4-7)

bluey/example/lib/features/stress_tests/
  domain/
    stress_test.dart                                    (Task 9)
    stress_test_config.dart                             (Task 9)
    stress_test_result.dart                             (Task 10)
  application/
    run_burst_write.dart                                (Task 13)
    run_mixed_ops.dart                                  (Task 15)
    run_soak.dart                                       (Task 16)
    run_timeout_probe.dart                              (Task 17)
    run_failure_injection.dart                          (Task 18)
    run_mtu_probe.dart                                  (Task 19)
    run_notification_throughput.dart                    (Task 20)
  infrastructure/
    stress_test_runner.dart                             (Tasks 11, 13, 15-20)
  presentation/
    stress_tests_screen.dart                            (Task 12)
    stress_tests_cubit.dart                             (Task 12)
    stress_tests_state.dart                             (Task 12)
    widgets/
      test_card.dart                                    (Task 14)
      config_form.dart                                  (Task 14)
      results_panel.dart                                (Task 14)
  di/
    stress_tests_module.dart                            (Task 12)

bluey/example/test/shared/
  stress_protocol_test.dart                             (Tasks 1-3)
bluey/example/test/server/infrastructure/
  stress_service_handler_test.dart                      (Tasks 4-7)
bluey/example/test/stress_tests/
  domain/
    stress_test_result_test.dart                        (Task 10)
  application/
    run_burst_write_test.dart                           (Task 13)
    [one test file per use case]                        (Tasks 15-20)
  infrastructure/
    stress_test_runner_test.dart                        (Tasks 13, 15-20)
  presentation/
    stress_tests_cubit_test.dart                        (Task 12)
    widgets/
      test_card_test.dart                               (Task 14)
```

### Modified files

```
bluey/example/lib/features/server/presentation/server_cubit.dart    (Task 8)
bluey/example/lib/features/connection/presentation/connection_screen.dart  (Task 12)
bluey/example/lib/shared/di/service_locator.dart                    (Task 12)
bluey/example/test/fakes/                                           (test fakes — Task 13)

bluey/lib/src/bluey.dart                                            (Task 21)
bluey/lib/src/connection/bluey_connection.dart                      (Task 21)
bluey/lib/src/connection/lifecycle_client.dart                      (Task 21)
bluey/lib/src/peer/bluey_peer.dart                                  (Task 21)
bluey/lib/src/gatt_server/bluey_server.dart                         (Task 21)
```

### Test fakes

```
bluey/example/test/fakes/fake_connection.dart                       (Task 13)
bluey/example/test/fakes/fake_remote_characteristic.dart            (Task 13)
```

(These mirror the patterns already used in `bluey/test/fakes/`. The example app currently uses mocktail mocks; we add focused fakes here because stress tests need predictable behaviour over many ops, not per-call stubbing.)

---

## Task 1: Stress protocol scaffold + EchoCommand

**Files:**
- Create: `bluey/example/lib/shared/stress_protocol.dart`
- Create: `bluey/example/test/shared/stress_protocol_test.dart`

- [ ] **Step 1: Write the failing test**

Write to `bluey/example/test/shared/stress_protocol_test.dart`:

```dart
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
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd bluey/example && flutter test test/shared/stress_protocol_test.dart
```

Expected: compilation failure — `bluey_example/shared/stress_protocol.dart` not found.

- [ ] **Step 3: Implement minimal protocol**

Write to `bluey/example/lib/shared/stress_protocol.dart`:

```dart
import 'dart:typed_data';

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
        opcode: -1,
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
  const EchoCommand(this.payload);

  @override
  Uint8List encode() {
    final out = Uint8List(payload.length + 1);
    out[0] = 0x01;
    out.setRange(1, out.length, payload);
    return out;
  }
}

/// Thrown when stress command bytes can't be decoded.
class StressProtocolException implements Exception {
  final int opcode;
  final String message;
  const StressProtocolException({required this.opcode, required this.message});
  @override
  String toString() => 'StressProtocolException: $message';
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd bluey/example && flutter test test/shared/stress_protocol_test.dart
```

Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add bluey/example/lib/shared/stress_protocol.dart \
        bluey/example/test/shared/stress_protocol_test.dart
git commit -m "feat(example): add StressProtocol with EchoCommand"
```

---

## Task 2: BurstMeCommand + DelayAckCommand + SetPayloadSizeCommand (uint16-payload commands)

**Files:**
- Modify: `bluey/example/lib/shared/stress_protocol.dart`
- Modify: `bluey/example/test/shared/stress_protocol_test.dart`

These three commands all encode `uint16` little-endian payloads. Adding them together is appropriate because their pattern is identical.

- [ ] **Step 1: Write failing tests**

Append to `bluey/example/test/shared/stress_protocol_test.dart` (inside the `void main()` block):

```dart
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
});
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd bluey/example && flutter test test/shared/stress_protocol_test.dart
```

Expected: compilation errors for `BurstMeCommand`, `DelayAckCommand`, `SetPayloadSizeCommand` (not yet defined).

- [ ] **Step 3: Implement the three commands**

In `bluey/example/lib/shared/stress_protocol.dart`, add the three command classes after `EchoCommand`:

```dart
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
}
```

Then extend the `decode` switch in `StressCommand`:

```dart
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
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd bluey/example && flutter test test/shared/stress_protocol_test.dart
```

Expected: all tests pass (Task 1's tests still green plus the 6 new ones).

- [ ] **Step 5: Commit**

```bash
git add bluey/example/lib/shared/stress_protocol.dart \
        bluey/example/test/shared/stress_protocol_test.dart
git commit -m "feat(example): add BurstMe / DelayAck / SetPayloadSize commands"
```

---

## Task 3: DropNextCommand + ResetCommand (no-payload commands)

**Files:**
- Modify: `bluey/example/lib/shared/stress_protocol.dart`
- Modify: `bluey/example/test/shared/stress_protocol_test.dart`

- [ ] **Step 1: Write failing tests**

Append to `bluey/example/test/shared/stress_protocol_test.dart`:

```dart
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
});
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd bluey/example && flutter test test/shared/stress_protocol_test.dart
```

Expected: compilation errors for `DropNextCommand` and `ResetCommand`.

- [ ] **Step 3: Implement the two commands**

In `bluey/example/lib/shared/stress_protocol.dart`, append:

```dart
/// DropNext: server silently ignores the next write (no response, no
/// notification). Self-clears after one drop. Opcode 0x04.
class DropNextCommand extends StressCommand {
  const DropNextCommand();
  @override
  Uint8List encode() => Uint8List.fromList([0x04]);
}

/// Reset: clears all server-side stress state (lastEcho, dropNext flag,
/// payloadSize) and aborts any in-flight burstMe loop. Opcode 0x06.
class ResetCommand extends StressCommand {
  const ResetCommand();
  @override
  Uint8List encode() => Uint8List.fromList([0x06]);
}
```

Extend the `decode` switch with two more cases (in `StressCommand.decode`):

```dart
      case 0x04:
        return const DropNextCommand();
      case 0x06:
        return const ResetCommand();
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd bluey/example && flutter test test/shared/stress_protocol_test.dart
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add bluey/example/lib/shared/stress_protocol.dart \
        bluey/example/test/shared/stress_protocol_test.dart
git commit -m "feat(example): add DropNext and Reset commands"
```

---

## Task 4: StressServiceHandler scaffold + Echo handling

**Files:**
- Create: `bluey/example/lib/features/server/infrastructure/stress_service_handler.dart`
- Create: `bluey/example/test/server/infrastructure/stress_service_handler_test.dart`

- [ ] **Step 1: Write the failing test**

Write to `bluey/example/test/server/infrastructure/stress_service_handler_test.dart`:

```dart
import 'dart:typed_data';

import 'package:bluey/bluey.dart';
import 'package:bluey_example/features/server/infrastructure/stress_service_handler.dart';
import 'package:bluey_example/shared/stress_protocol.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockServer extends Mock implements Server {}
class _MockClient extends Mock implements Client {}

void main() {
  late _MockServer mockServer;
  late _MockClient mockClient;

  setUp(() {
    mockServer = _MockServer();
    mockClient = _MockClient();
    when(() => mockClient.id).thenReturn('test-client');
    when(() => mockServer.respondToWrite(
          any(),
          status: any(named: 'status'),
        )).thenAnswer((_) async {});
    when(() => mockServer.notify(any(), any())).thenAnswer((_) async {});
  });

  group('StressServiceHandler — Echo', () {
    test('echo stores payload, responds success, and notifies', () async {
      final handler = StressServiceHandler();
      final payload = Uint8List.fromList([0xAA, 0xBB, 0xCC]);
      final write = WriteRequest(
        client: mockClient,
        characteristicUuid: UUID(StressProtocol.charUuid),
        value: const EchoCommand(/* dummy */ Uint8List(0)).encode(), // overwritten below
        responseNeeded: true,
      );
      // Re-create with the actual payload via EchoCommand
      final realWrite = WriteRequest(
        client: mockClient,
        characteristicUuid: UUID(StressProtocol.charUuid),
        value: EchoCommand(payload).encode(),
        responseNeeded: true,
      );

      await handler.onWrite(realWrite, mockServer);

      verify(() => mockServer.respondToWrite(
            realWrite,
            status: GattResponseStatus.success,
          )).called(1);
      verify(() => mockServer.notify(
            UUID(StressProtocol.charUuid),
            payload,
          )).called(1);

      // Read after echo returns the stored payload
      final readResponse = handler.onRead();
      expect(readResponse, equals(payload));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd bluey/example && flutter test test/server/infrastructure/stress_service_handler_test.dart
```

Expected: compilation failure — `stress_service_handler.dart` doesn't exist.

- [ ] **Step 3: Implement the handler with echo only**

Write to `bluey/example/lib/features/server/infrastructure/stress_service_handler.dart`:

```dart
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
        await server.notify(UUID(StressProtocol.charUuid), payload);
      // Other cases added in subsequent tasks.
      case _:
        // Stub: future opcodes acknowledged but not yet implemented.
        if (req.responseNeeded) {
          await server.respondToWrite(req, status: GattResponseStatus.success);
        }
    }
  }

  /// Returns bytes for a read on [StressProtocol.charUuid]. If [_lastEcho]
  /// is non-empty, returns it; otherwise returns [_payloadSize] bytes of
  /// deterministic pattern.
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
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd bluey/example && flutter test test/server/infrastructure/stress_service_handler_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add bluey/example/lib/features/server/infrastructure/stress_service_handler.dart \
        bluey/example/test/server/infrastructure/stress_service_handler_test.dart
git commit -m "feat(example): add StressServiceHandler with echo support"
```

---

## Task 5: BurstMe + DelayAck + DropNext + SetPayloadSize handlers

**Files:**
- Modify: `bluey/example/lib/features/server/infrastructure/stress_service_handler.dart`
- Modify: `bluey/example/test/server/infrastructure/stress_service_handler_test.dart`

- [ ] **Step 1: Write failing tests**

Append to the test file (inside `void main()`):

```dart
group('StressServiceHandler — BurstMe', () {
  test('burstMe responds success then fires N notifications with burst-id prefix', () async {
    final handler = StressServiceHandler();
    final write = WriteRequest(
      client: mockClient,
      characteristicUuid: UUID(StressProtocol.charUuid),
      value: const BurstMeCommand(count: 3, payloadSize: 4).encode(),
      responseNeeded: true,
    );

    await handler.onWrite(write, mockServer);

    verify(() => mockServer.respondToWrite(
          write,
          status: GattResponseStatus.success,
        )).called(1);
    // 3 notifications, each: [burstId, 0x00, 0x01, 0x02, 0x03]
    final captured = verify(() => mockServer.notify(
          UUID(StressProtocol.charUuid),
          captureAny(),
        )).captured.cast<Uint8List>();
    expect(captured, hasLength(3));
    final firstBurstId = captured.first.first;
    for (final notif in captured) {
      expect(notif.first, equals(firstBurstId), reason: 'all notifs in one burst share id');
      expect(notif.sublist(1), equals(Uint8List.fromList([0x00, 0x01, 0x02, 0x03])));
    }
  });

  test('successive burstMe commands use incrementing burst-ids', () async {
    final handler = StressServiceHandler();
    Uint8List makeBurst(int count) =>
        BurstMeCommand(count: count, payloadSize: 1).encode();

    await handler.onWrite(
      WriteRequest(
        client: mockClient,
        characteristicUuid: UUID(StressProtocol.charUuid),
        value: makeBurst(1),
        responseNeeded: true,
      ),
      mockServer,
    );
    await handler.onWrite(
      WriteRequest(
        client: mockClient,
        characteristicUuid: UUID(StressProtocol.charUuid),
        value: makeBurst(1),
        responseNeeded: true,
      ),
      mockServer,
    );

    final captured = verify(() => mockServer.notify(
          UUID(StressProtocol.charUuid),
          captureAny(),
        )).captured.cast<Uint8List>();
    expect(captured, hasLength(2));
    expect(captured[1].first, equals((captured[0].first + 1) & 0xff));
  });
});

group('StressServiceHandler — DelayAck', () {
  test('delayAck waits the requested duration before responding', () async {
    final handler = StressServiceHandler();
    final write = WriteRequest(
      client: mockClient,
      characteristicUuid: UUID(StressProtocol.charUuid),
      value: const DelayAckCommand(delayMs: 50).encode(),
      responseNeeded: true,
    );

    final stopwatch = Stopwatch()..start();
    await handler.onWrite(write, mockServer);
    stopwatch.stop();

    expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(50));
    verify(() => mockServer.respondToWrite(
          write,
          status: GattResponseStatus.success,
        )).called(1);
  });
});

group('StressServiceHandler — DropNext', () {
  test('dropNext sets flag; next write is silent and self-clears', () async {
    final handler = StressServiceHandler();

    // First write: dropNext command itself responds normally.
    final dropCmd = WriteRequest(
      client: mockClient,
      characteristicUuid: UUID(StressProtocol.charUuid),
      value: const DropNextCommand().encode(),
      responseNeeded: true,
    );
    await handler.onWrite(dropCmd, mockServer);
    verify(() => mockServer.respondToWrite(
          dropCmd,
          status: GattResponseStatus.success,
        )).called(1);

    // Second write: should be silently dropped (no respondToWrite, no notify).
    final droppedWrite = WriteRequest(
      client: mockClient,
      characteristicUuid: UUID(StressProtocol.charUuid),
      value: EchoCommand(Uint8List.fromList([0x42])).encode(),
      responseNeeded: true,
    );
    await handler.onWrite(droppedWrite, mockServer);
    verifyNever(() => mockServer.respondToWrite(
          droppedWrite,
          status: any(named: 'status'),
        ));
    verifyNever(() => mockServer.notify(any(), any()));

    // Third write: dropNext has self-cleared, write echoes normally.
    final normalWrite = WriteRequest(
      client: mockClient,
      characteristicUuid: UUID(StressProtocol.charUuid),
      value: EchoCommand(Uint8List.fromList([0x99])).encode(),
      responseNeeded: true,
    );
    await handler.onWrite(normalWrite, mockServer);
    verify(() => mockServer.respondToWrite(
          normalWrite,
          status: GattResponseStatus.success,
        )).called(1);
  });
});

group('StressServiceHandler — SetPayloadSize', () {
  test('setPayloadSize changes the size of subsequent reads', () async {
    final handler = StressServiceHandler();
    expect(handler.onRead(), hasLength(20)); // default

    final cmd = WriteRequest(
      client: mockClient,
      characteristicUuid: UUID(StressProtocol.charUuid),
      value: const SetPayloadSizeCommand(sizeBytes: 50).encode(),
      responseNeeded: true,
    );
    await handler.onWrite(cmd, mockServer);

    expect(handler.onRead(), hasLength(50));
  });
});

group('StressServiceHandler — unknown opcode', () {
  test('unknown opcode responds with requestNotSupported', () async {
    final handler = StressServiceHandler();
    final write = WriteRequest(
      client: mockClient,
      characteristicUuid: UUID(StressProtocol.charUuid),
      value: Uint8List.fromList([0xFF]), // unknown opcode
      responseNeeded: true,
    );

    await handler.onWrite(write, mockServer);

    verify(() => mockServer.respondToWrite(
          write,
          status: GattResponseStatus.requestNotSupported,
        )).called(1);
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd bluey/example && flutter test test/server/infrastructure/stress_service_handler_test.dart
```

Expected: BurstMe / DelayAck / DropNext / SetPayloadSize tests fail (the stub `case _:` swallows them with success and no behaviour); the unknown-opcode test passes (decode already raises and the handler responds with requestNotSupported).

- [ ] **Step 3: Replace the stub `_:` case with real implementations**

Edit `bluey/example/lib/features/server/infrastructure/stress_service_handler.dart` — replace the stub `case _:` with explicit cases for the four new commands. The full `switch (cmd)` becomes:

```dart
    switch (cmd) {
      case EchoCommand(:final payload):
        _lastEcho = payload;
        if (req.responseNeeded) {
          await server.respondToWrite(req, status: GattResponseStatus.success);
        }
        await server.notify(UUID(StressProtocol.charUuid), payload);

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
          await server.notify(UUID(StressProtocol.charUuid), framed);
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

      // ResetCommand handled in Task 6.
      case ResetCommand():
        if (req.responseNeeded) {
          await server.respondToWrite(req, status: GattResponseStatus.success);
        }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd bluey/example && flutter test test/server/infrastructure/stress_service_handler_test.dart
```

Expected: all tests pass (Task 4's echo test still green plus 6 new ones).

- [ ] **Step 5: Commit**

```bash
git add bluey/example/lib/features/server/infrastructure/stress_service_handler.dart \
        bluey/example/test/server/infrastructure/stress_service_handler_test.dart
git commit -m "feat(example): handle BurstMe/DelayAck/DropNext/SetPayloadSize in stress service"
```

---

## Task 6: Reset handling + burst-abort-on-reset

**Files:**
- Modify: `bluey/example/lib/features/server/infrastructure/stress_service_handler.dart`
- Modify: `bluey/example/test/server/infrastructure/stress_service_handler_test.dart`

- [ ] **Step 1: Write failing tests**

Append to the test file:

```dart
group('StressServiceHandler — Reset', () {
  test('reset clears all state', () async {
    final handler = StressServiceHandler();

    // Set state on the handler.
    await handler.onWrite(
      WriteRequest(
        client: mockClient,
        characteristicUuid: UUID(StressProtocol.charUuid),
        value: EchoCommand(Uint8List.fromList([0xAA, 0xBB])).encode(),
        responseNeeded: true,
      ),
      mockServer,
    );
    await handler.onWrite(
      WriteRequest(
        client: mockClient,
        characteristicUuid: UUID(StressProtocol.charUuid),
        value: const SetPayloadSizeCommand(sizeBytes: 100).encode(),
        responseNeeded: true,
      ),
      mockServer,
    );
    await handler.onWrite(
      WriteRequest(
        client: mockClient,
        characteristicUuid: UUID(StressProtocol.charUuid),
        value: const DropNextCommand().encode(),
        responseNeeded: true,
      ),
      mockServer,
    );

    // Now reset.
    await handler.onWrite(
      WriteRequest(
        client: mockClient,
        characteristicUuid: UUID(StressProtocol.charUuid),
        value: const ResetCommand().encode(),
        responseNeeded: true,
      ),
      mockServer,
    );

    // _lastEcho cleared → reads return pattern of default size 20.
    expect(handler.onRead(), hasLength(20));

    // _dropNextWrite cleared → next write echoes normally.
    final probe = WriteRequest(
      client: mockClient,
      characteristicUuid: UUID(StressProtocol.charUuid),
      value: EchoCommand(Uint8List.fromList([0x99])).encode(),
      responseNeeded: true,
    );
    clearInteractions(mockServer);
    when(() => mockServer.respondToWrite(any(), status: any(named: 'status')))
        .thenAnswer((_) async {});
    when(() => mockServer.notify(any(), any())).thenAnswer((_) async {});
    await handler.onWrite(probe, mockServer);
    verify(() => mockServer.respondToWrite(probe, status: GattResponseStatus.success))
        .called(1);
  });

  test('reset interrupts an in-flight burstMe loop', () async {
    final handler = StressServiceHandler();

    // Configure mockServer.notify so that the second notification
    // triggers a reset mid-loop.
    var notifyCount = 0;
    when(() => mockServer.notify(any(), any())).thenAnswer((_) async {
      notifyCount++;
      if (notifyCount == 2) {
        // Mid-burst, fire a reset that flips _abortBurst.
        await handler.onWrite(
          WriteRequest(
            client: mockClient,
            characteristicUuid: UUID(StressProtocol.charUuid),
            value: const ResetCommand().encode(),
            responseNeeded: false,
          ),
          mockServer,
        );
      }
    });

    final write = WriteRequest(
      client: mockClient,
      characteristicUuid: UUID(StressProtocol.charUuid),
      value: const BurstMeCommand(count: 100, payloadSize: 4).encode(),
      responseNeeded: true,
    );
    await handler.onWrite(write, mockServer);

    // Should have stopped well before 100 — exact count depends on the
    // event loop's microtask ordering, but we expect << 100.
    expect(notifyCount, lessThan(10),
        reason: 'reset should have aborted the burst quickly');
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd bluey/example && flutter test test/server/infrastructure/stress_service_handler_test.dart
```

Expected: the first reset test fails because `ResetCommand` doesn't actually clear state (Task 5 stubbed it). The burst-abort test fails because `_abortBurst` is never set by reset.

- [ ] **Step 3: Implement reset properly**

In `stress_service_handler.dart`, replace the `case ResetCommand():` with:

```dart
      case ResetCommand():
        _lastEcho = Uint8List(0);
        _dropNextWrite = false;
        _payloadSize = 20;
        _abortBurst = true; // interrupts any in-flight burstMe loop
        if (req.responseNeeded) {
          await server.respondToWrite(req, status: GattResponseStatus.success);
        }
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd bluey/example && flutter test test/server/infrastructure/stress_service_handler_test.dart
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add bluey/example/lib/features/server/infrastructure/stress_service_handler.dart \
        bluey/example/test/server/infrastructure/stress_service_handler_test.dart
git commit -m "feat(example): implement Reset opcode + burst-abort-on-reset"
```

---

## Task 7: Wire stress service into example server

**Files:**
- Modify: `bluey/example/lib/features/server/presentation/server_cubit.dart`

The existing `ServerCubit.initializeServer` method (or equivalent) registers the demo service. We need to:
1. Construct a `StressServiceHandler` instance
2. Register the stress service via `addService`
3. Subscribe to read/write requests, route ones for `StressProtocol.charUuid` to the handler

- [ ] **Step 1: Read the current server_cubit registration block**

Open `bluey/example/lib/features/server/presentation/server_cubit.dart` and locate (around line 162) the `await _addService(HostedService(uuid: demoServiceUuid, ...))` call and the existing `_writeRequestSubscription` listener. Note how requests are routed by `request.characteristicUuid`.

- [ ] **Step 2: Modify the cubit to register the stress service**

In `server_cubit.dart`:

(a) Add the import:

```dart
import '../../../shared/stress_protocol.dart';
import '../infrastructure/stress_service_handler.dart';
```

(b) Add a field on `ServerCubit`:

```dart
final StressServiceHandler _stressHandler = StressServiceHandler();
```

(c) After the existing `_addService(HostedService(uuid: demoServiceUuid, ...))` block, add another `_addService` call for the stress service:

```dart
    // Stress test service: hidden behind a feature flag in the UI; only
    // visible to clients when discovered. Hosts a single characteristic
    // with read/write/writeWithoutResponse/notify properties.
    await _addService(
      HostedService(
        uuid: UUID(StressProtocol.serviceUuid),
        isPrimary: true,
        characteristics: [
          HostedCharacteristic(
            uuid: UUID(StressProtocol.charUuid),
            properties: const CharacteristicProperties(
              canRead: true,
              canWrite: true,
              canWriteWithoutResponse: true,
              canNotify: true,
            ),
            permissions: const [GattPermission.read, GattPermission.write],
            descriptors: const [],
          ),
        ],
      ),
    );
    _addLog('Server', 'Registered stress test service');
```

(d) In the existing `_writeRequestSubscription` listener (around line 142), route stress-service writes to the handler before the existing demo-write logic. Pre-condition: a `_server` field must exist that holds the `Server` instance — check what variable holds it in the cubit. Add this branch at the top of the listener:

```dart
    _writeRequestSubscription = _observeWriteRequests().listen((request) async {
      if (request.characteristicUuid == UUID(StressProtocol.charUuid)) {
        try {
          await _stressHandler.onWrite(request, _server!);
        } catch (e) {
          _addLog('Stress', 'Handler error: $e');
        }
        return;
      }
      // ... existing demo-write logic unchanged ...
```

(e) In the existing `_readRequestSubscription` listener (search for `_observeReadRequests`), add a similar branch:

```dart
    _readRequestSubscription = _observeReadRequests().listen((request) async {
      if (request.characteristicUuid == UUID(StressProtocol.charUuid)) {
        try {
          final value = _stressHandler.onRead();
          await _observeReadRequests.respond(
            request,
            status: GattResponseStatus.success,
            value: value,
          );
        } catch (e) {
          _addLog('Stress', 'Read handler error: $e');
        }
        return;
      }
      // ... existing demo-read logic unchanged ...
```

(Note: the exact `_observeWriteRequests`/`_server` variable names may differ. Inspect the file. If the cubit uses a typed reference or the requests come through a different surface, adapt the integration.)

- [ ] **Step 3: Run all server tests to verify nothing regresses**

```bash
cd bluey/example && flutter test test/server/
```

Expected: all existing server tests still pass; stress handler tests still pass.

- [ ] **Step 4: Manual smoke check**

Run the example app on a device, start the server, and from a generic BLE scanner (e.g. `nRF Connect`) verify that:
- The stress service UUID `b1e7a001-...` appears in the advertised services
- Its characteristic `b1e7a002-...` lists read/write/notify properties

This step has no automated test — it's a one-time setup verification.

- [ ] **Step 5: Commit**

```bash
git add bluey/example/lib/features/server/presentation/server_cubit.dart
git commit -m "feat(example): register stress test service in example server"
```

---

## Task 8: Domain types — StressTest enum + StressTestConfig sealed hierarchy

**Files:**
- Create: `bluey/example/lib/features/stress_tests/domain/stress_test.dart`
- Create: `bluey/example/lib/features/stress_tests/domain/stress_test_config.dart`

These are pure data; no test file needed (no logic to test). They unblock all subsequent application/presentation tasks.

- [ ] **Step 1: Create the StressTest enum**

Write to `bluey/example/lib/features/stress_tests/domain/stress_test.dart`:

```dart
/// Identifier for each stress test the example app can run. One enum
/// value per UI card / use case.
enum StressTest {
  burstWrite,
  mixedOps,
  soak,
  timeoutProbe,
  failureInjection,
  mtuProbe,
  notificationThroughput,
}

extension StressTestX on StressTest {
  /// Human-readable name shown on the test card.
  String get displayName => switch (this) {
        StressTest.burstWrite => 'Burst write',
        StressTest.mixedOps => 'Mixed ops',
        StressTest.soak => 'Soak',
        StressTest.timeoutProbe => 'Timeout probe',
        StressTest.failureInjection => 'Failure injection',
        StressTest.mtuProbe => 'MTU probe',
        StressTest.notificationThroughput => 'Notification throughput',
      };
}
```

- [ ] **Step 2: Create the config sealed hierarchy**

Write to `bluey/example/lib/features/stress_tests/domain/stress_test_config.dart`:

```dart
/// Per-test configuration. Each subclass holds the parameters its test
/// needs. Defaults are sensible and chosen to complete in seconds-ish
/// against a typical example-server.
sealed class StressTestConfig {
  const StressTestConfig();
}

class BurstWriteConfig extends StressTestConfig {
  /// Total number of writes to fire.
  final int count;
  /// Payload bytes per write (excluding the 1-byte opcode prefix).
  final int payloadBytes;
  /// Whether each write requests a response (true) or fires
  /// without-response (false).
  final bool withResponse;

  const BurstWriteConfig({
    this.count = 50,
    this.payloadBytes = 20,
    this.withResponse = true,
  });
}

class MixedOpsConfig extends StressTestConfig {
  /// Number of (write, read, discoverServices, requestMtu) cycles.
  final int iterations;
  const MixedOpsConfig({this.iterations = 10});
}

class SoakConfig extends StressTestConfig {
  /// Total wall-clock duration of the soak.
  final Duration duration;
  /// Time between successive write attempts.
  final Duration interval;
  /// Echo payload size per write.
  final int payloadBytes;

  const SoakConfig({
    this.duration = const Duration(minutes: 5),
    this.interval = const Duration(seconds: 1),
    this.payloadBytes = 20,
  });
}

class TimeoutProbeConfig extends StressTestConfig {
  /// How far past the per-op timeout the server should delay its ack.
  /// 2s past the default 10s timeout = 12s total wait.
  final Duration delayPastTimeout;
  const TimeoutProbeConfig({
    this.delayPastTimeout = const Duration(seconds: 2),
  });
}

class FailureInjectionConfig extends StressTestConfig {
  /// Total writes to attempt after the dropNext command.
  /// First should time out (dropped); rest should succeed.
  final int writeCount;
  const FailureInjectionConfig({this.writeCount = 10});
}

class MtuProbeConfig extends StressTestConfig {
  /// MTU value to request from the platform.
  final int requestedMtu;
  /// Payload bytes per write/read (defaults to negotiated MTU - 3 ATT
  /// header bytes if 0).
  final int payloadBytes;
  const MtuProbeConfig({this.requestedMtu = 247, this.payloadBytes = 244});
}

class NotificationThroughputConfig extends StressTestConfig {
  /// Number of notifications to ask the server to fire.
  final int count;
  /// Bytes per notification (excluding the burst-id prefix byte).
  final int payloadBytes;
  const NotificationThroughputConfig({
    this.count = 100,
    this.payloadBytes = 20,
  });
}
```

- [ ] **Step 3: Verify the file compiles**

```bash
cd bluey/example && flutter analyze lib/features/stress_tests/
```

Expected: No issues found.

- [ ] **Step 4: Commit**

```bash
git add bluey/example/lib/features/stress_tests/domain/stress_test.dart \
        bluey/example/lib/features/stress_tests/domain/stress_test_config.dart
git commit -m "feat(example): add StressTest enum and StressTestConfig hierarchy"
```

---

## Task 9: StressTestResult value object with aggregation logic

**Files:**
- Create: `bluey/example/lib/features/stress_tests/domain/stress_test_result.dart`
- Create: `bluey/example/test/stress_tests/domain/stress_test_result_test.dart`

`StressTestResult` accumulates counters and computes derived stats (median, p95). It's a value object, but it has aggregation logic worth testing.

- [ ] **Step 1: Write failing tests**

Write to `bluey/example/test/stress_tests/domain/stress_test_result_test.dart`:

```dart
import 'package:bluey_example/features/stress_tests/domain/stress_test_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StressTestResult', () {
    test('empty result has zero counters and isRunning=true', () {
      final r = StressTestResult.initial();
      expect(r.attempted, equals(0));
      expect(r.succeeded, equals(0));
      expect(r.failed, equals(0));
      expect(r.failuresByType, isEmpty);
      expect(r.statusCounts, isEmpty);
      expect(r.latencies, isEmpty);
      expect(r.isRunning, isTrue);
    });

    test('recordSuccess increments attempted and succeeded', () {
      final r = StressTestResult.initial()
          .recordSuccess(latency: const Duration(milliseconds: 10));
      expect(r.attempted, equals(1));
      expect(r.succeeded, equals(1));
      expect(r.failed, equals(0));
      expect(r.latencies, equals([const Duration(milliseconds: 10)]));
    });

    test('recordFailure increments attempted and failed', () {
      final r = StressTestResult.initial()
          .recordFailure(typeName: 'GattTimeoutException');
      expect(r.attempted, equals(1));
      expect(r.succeeded, equals(0));
      expect(r.failed, equals(1));
      expect(r.failuresByType['GattTimeoutException'], equals(1));
    });

    test('recordFailure with status increments statusCounts', () {
      final r = StressTestResult.initial().recordFailure(
        typeName: 'GattOperationFailedException',
        status: 1,
      );
      expect(r.statusCounts[1], equals(1));
    });

    test('multiple failures of same type accumulate', () {
      var r = StressTestResult.initial();
      r = r.recordFailure(typeName: 'GattTimeoutException');
      r = r.recordFailure(typeName: 'GattTimeoutException');
      r = r.recordFailure(typeName: 'DisconnectedException');
      expect(r.failuresByType['GattTimeoutException'], equals(2));
      expect(r.failuresByType['DisconnectedException'], equals(1));
      expect(r.failed, equals(3));
    });

    test('medianLatency returns middle value', () {
      var r = StressTestResult.initial();
      for (final ms in [5, 10, 15, 20, 25]) {
        r = r.recordSuccess(latency: Duration(milliseconds: ms));
      }
      expect(r.medianLatency, equals(const Duration(milliseconds: 15)));
    });

    test('medianLatency returns Duration.zero when no latencies', () {
      expect(StressTestResult.initial().medianLatency, equals(Duration.zero));
    });

    test('p95Latency returns 95th-percentile value', () {
      var r = StressTestResult.initial();
      for (var i = 1; i <= 100; i++) {
        r = r.recordSuccess(latency: Duration(milliseconds: i));
      }
      // 95th percentile of 1..100 = 95.
      expect(r.p95Latency, equals(const Duration(milliseconds: 95)));
    });

    test('finished sets isRunning false and freezes elapsed', () {
      final r = StressTestResult.initial().finished(
        elapsed: const Duration(seconds: 3),
      );
      expect(r.isRunning, isFalse);
      expect(r.elapsed, equals(const Duration(seconds: 3)));
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd bluey/example && flutter test test/stress_tests/domain/stress_test_result_test.dart
```

Expected: compilation failure — `stress_test_result.dart` not found.

- [ ] **Step 3: Implement StressTestResult**

Write to `bluey/example/lib/features/stress_tests/domain/stress_test_result.dart`:

```dart
/// Immutable snapshot of a stress test's running counters.
///
/// Created via [StressTestResult.initial] and updated functionally via
/// [recordSuccess] / [recordFailure] / [finished], each returning a new
/// instance. The runner emits successive snapshots on its result stream.
class StressTestResult {
  final int attempted;
  final int succeeded;
  final int failed;

  /// Failure counts keyed by exception class name (e.g.
  /// `'GattTimeoutException'`, `'DisconnectedException'`).
  final Map<String, int> failuresByType;

  /// Status-code counts for failures of type
  /// `GattOperationFailedException`. Empty for any other failure type.
  final Map<int, int> statusCounts;

  /// Per-op latencies, in submission order. Used for median / p95.
  final List<Duration> latencies;

  /// Wall-clock elapsed since the test started. Updated incrementally
  /// while the test runs; frozen by [finished].
  final Duration elapsed;

  /// Whether the test is still in flight. False after [finished].
  final bool isRunning;

  const StressTestResult._({
    required this.attempted,
    required this.succeeded,
    required this.failed,
    required this.failuresByType,
    required this.statusCounts,
    required this.latencies,
    required this.elapsed,
    required this.isRunning,
  });

  factory StressTestResult.initial() => const StressTestResult._(
        attempted: 0,
        succeeded: 0,
        failed: 0,
        failuresByType: {},
        statusCounts: {},
        latencies: [],
        elapsed: Duration.zero,
        isRunning: true,
      );

  StressTestResult recordSuccess({required Duration latency}) {
    return StressTestResult._(
      attempted: attempted + 1,
      succeeded: succeeded + 1,
      failed: failed,
      failuresByType: failuresByType,
      statusCounts: statusCounts,
      latencies: [...latencies, latency],
      elapsed: elapsed,
      isRunning: isRunning,
    );
  }

  StressTestResult recordFailure({
    required String typeName,
    int? status,
  }) {
    final newFailures = Map<String, int>.from(failuresByType);
    newFailures[typeName] = (newFailures[typeName] ?? 0) + 1;
    final newStatusCounts = Map<int, int>.from(statusCounts);
    if (status != null) {
      newStatusCounts[status] = (newStatusCounts[status] ?? 0) + 1;
    }
    return StressTestResult._(
      attempted: attempted + 1,
      succeeded: succeeded,
      failed: failed + 1,
      failuresByType: newFailures,
      statusCounts: newStatusCounts,
      latencies: latencies,
      elapsed: elapsed,
      isRunning: isRunning,
    );
  }

  StressTestResult withElapsed(Duration newElapsed) {
    return StressTestResult._(
      attempted: attempted,
      succeeded: succeeded,
      failed: failed,
      failuresByType: failuresByType,
      statusCounts: statusCounts,
      latencies: latencies,
      elapsed: newElapsed,
      isRunning: isRunning,
    );
  }

  StressTestResult finished({required Duration elapsed}) {
    return StressTestResult._(
      attempted: attempted,
      succeeded: succeeded,
      failed: failed,
      failuresByType: failuresByType,
      statusCounts: statusCounts,
      latencies: latencies,
      elapsed: elapsed,
      isRunning: false,
    );
  }

  /// Median (50th-percentile) latency. Zero if no successes recorded.
  Duration get medianLatency {
    if (latencies.isEmpty) return Duration.zero;
    final sorted = [...latencies]..sort();
    return sorted[sorted.length ~/ 2];
  }

  /// 95th-percentile latency. Zero if no successes recorded.
  Duration get p95Latency {
    if (latencies.isEmpty) return Duration.zero;
    final sorted = [...latencies]..sort();
    final idx = ((sorted.length - 1) * 0.95).round();
    return sorted[idx];
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd bluey/example && flutter test test/stress_tests/domain/stress_test_result_test.dart
```

Expected: all 9 tests pass.

- [ ] **Step 5: Commit**

```bash
git add bluey/example/lib/features/stress_tests/domain/stress_test_result.dart \
        bluey/example/test/stress_tests/domain/stress_test_result_test.dart
git commit -m "feat(example): add StressTestResult with aggregation logic"
```

---

## Task 10: StressTestRunner skeleton (no impls yet)

**Files:**
- Create: `bluey/example/lib/features/stress_tests/infrastructure/stress_test_runner.dart`

A skeleton that defines the public methods so use cases and the cubit can compile against the interface. Each method throws `UnimplementedError` until its dedicated task implements it.

- [ ] **Step 1: Create the runner skeleton**

Write to `bluey/example/lib/features/stress_tests/infrastructure/stress_test_runner.dart`:

```dart
import 'package:bluey/bluey.dart';

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
    throw UnimplementedError('runBurstWrite implemented in Task 11');
  }

  Stream<StressTestResult> runMixedOps(
    MixedOpsConfig config,
    Connection connection,
  ) {
    throw UnimplementedError('runMixedOps implemented in Task 14');
  }

  Stream<StressTestResult> runSoak(
    SoakConfig config,
    Connection connection,
  ) {
    throw UnimplementedError('runSoak implemented in Task 15');
  }

  Stream<StressTestResult> runTimeoutProbe(
    TimeoutProbeConfig config,
    Connection connection,
  ) {
    throw UnimplementedError('runTimeoutProbe implemented in Task 16');
  }

  Stream<StressTestResult> runFailureInjection(
    FailureInjectionConfig config,
    Connection connection,
  ) {
    throw UnimplementedError('runFailureInjection implemented in Task 17');
  }

  Stream<StressTestResult> runMtuProbe(
    MtuProbeConfig config,
    Connection connection,
  ) {
    throw UnimplementedError('runMtuProbe implemented in Task 18');
  }

  Stream<StressTestResult> runNotificationThroughput(
    NotificationThroughputConfig config,
    Connection connection,
  ) {
    throw UnimplementedError('runNotificationThroughput implemented in Task 19');
  }
}
```

- [ ] **Step 2: Verify it compiles**

```bash
cd bluey/example && flutter analyze lib/features/stress_tests/
```

Expected: No issues found.

- [ ] **Step 3: Commit**

```bash
git add bluey/example/lib/features/stress_tests/infrastructure/stress_test_runner.dart
git commit -m "feat(example): scaffold StressTestRunner with method stubs"
```

---

## Task 11: Implement runBurstWrite + integration test

**Files:**
- Create: `bluey/example/test/stress_tests/infrastructure/stress_test_runner_test.dart`
- Create: `bluey/example/test/fakes/fake_connection.dart`
- Create: `bluey/example/test/fakes/fake_remote_characteristic.dart`
- Modify: `bluey/example/lib/features/stress_tests/infrastructure/stress_test_runner.dart`

This task introduces the test fakes that all subsequent runner tasks reuse.

- [ ] **Step 1: Create fakes**

Write to `bluey/example/test/fakes/fake_remote_characteristic.dart`:

```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:bluey/bluey.dart';

/// Per-test programmable characteristic. Tests configure
/// `onWriteHook`/`onReadHook`/`emitNotification` to model the server side.
class FakeRemoteCharacteristic implements RemoteCharacteristic {
  @override
  final UUID uuid;
  @override
  final CharacteristicProperties properties;

  /// Called for each write. Default: succeed with no side effects.
  /// Override to inject delays or throws.
  Future<void> Function(Uint8List value, {required bool withResponse})
      onWriteHook = (_, {required bool withResponse}) async {};

  /// Called for each read. Default: returns empty bytes.
  Future<Uint8List> Function() onReadHook = () async => Uint8List(0);

  final _notif = StreamController<Uint8List>.broadcast();

  FakeRemoteCharacteristic({
    required this.uuid,
    this.properties = const CharacteristicProperties(
      canRead: true,
      canWrite: true,
      canWriteWithoutResponse: true,
      canNotify: true,
    ),
  });

  /// Inject a notification to subscribers.
  void emitNotification(Uint8List value) => _notif.add(value);

  @override
  Future<Uint8List> read() => onReadHook();

  @override
  Future<void> write(Uint8List value, {bool withResponse = true}) =>
      onWriteHook(value, withResponse: withResponse);

  @override
  Stream<Uint8List> get notifications => _notif.stream;

  @override
  RemoteDescriptor descriptor(UUID uuid) =>
      throw UnimplementedError('FakeRemoteCharacteristic.descriptor');

  @override
  List<RemoteDescriptor> get descriptors => const [];
}
```

Write to `bluey/example/test/fakes/fake_connection.dart`:

```dart
import 'dart:async';

import 'package:bluey/bluey.dart';

import 'fake_remote_characteristic.dart';

/// Programmable [Connection] for runner tests. Holds a single fake
/// service with one fake characteristic that tests configure via
/// `stressChar.onWriteHook` / `stressChar.onReadHook` /
/// `stressChar.emitNotification`.
class FakeConnection implements Connection {
  final FakeRemoteCharacteristic stressChar;
  final UUID stressServiceUuid;
  final _stateController = StreamController<ConnectionState>.broadcast();

  ConnectionState _state = ConnectionState.connected;
  int _mtu = 23;
  int? _mtuRequest;

  FakeConnection({
    required this.stressServiceUuid,
    required this.stressChar,
  });

  @override
  ConnectionState get state => _state;

  @override
  Stream<ConnectionState> get stateChanges => _stateController.stream;

  @override
  int get mtu => _mtu;

  @override
  Future<int> requestMtu(int requested) async {
    _mtuRequest = requested;
    _mtu = requested;
    return requested;
  }

  /// Tests can call to record what mtu was requested.
  int? get lastRequestedMtu => _mtuRequest;

  @override
  Future<List<RemoteService>> services({bool cache = true}) async {
    return [_FakeService(stressServiceUuid, [stressChar])];
  }

  @override
  Future<void> disconnect() async {
    _state = ConnectionState.disconnected;
    _stateController.add(_state);
  }

  /// Test-only: simulate an external disconnect mid-run.
  void simulateDisconnect() {
    _state = ConnectionState.disconnected;
    _stateController.add(_state);
  }

  // The following members fall through to UnimplementedError unless the
  // tests need them. Add as needed.

  @override
  UUID get deviceId => throw UnimplementedError();

  @override
  Future<int> readRssi() => throw UnimplementedError();
}

class _FakeService implements RemoteService {
  @override
  final UUID uuid;
  @override
  final List<RemoteCharacteristic> characteristics;
  _FakeService(this.uuid, this.characteristics);

  @override
  bool get isPrimary => true;

  @override
  RemoteCharacteristic characteristic(UUID uuid) =>
      characteristics.firstWhere((c) => c.uuid == uuid);

  @override
  List<RemoteService> get includedServices => const [];
}
```

(Notes for implementer: the exact `Connection` interface members may have evolved. If a method on `Connection` is added or removed, mirror the change here. Look at `bluey/lib/src/connection/connection.dart` for the canonical contract.)

- [ ] **Step 2: Write the failing runner test**

Write to `bluey/example/test/stress_tests/infrastructure/stress_test_runner_test.dart`:

```dart
import 'dart:typed_data';

import 'package:bluey/bluey.dart';
import 'package:bluey_example/features/stress_tests/domain/stress_test_config.dart';
import 'package:bluey_example/features/stress_tests/domain/stress_test_result.dart';
import 'package:bluey_example/features/stress_tests/infrastructure/stress_test_runner.dart';
import 'package:bluey_example/shared/stress_protocol.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart' as plat;
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
    test('runs the configured count of writes and emits a final snapshot', () async {
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
        if (i == 3) {
          throw const GattTimeoutException('writeCharacteristic');
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
        throw const GattOperationFailedException('writeCharacteristic', 1);
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
```

- [ ] **Step 3: Run tests to verify they fail**

```bash
cd bluey/example && flutter test test/stress_tests/infrastructure/stress_test_runner_test.dart
```

Expected: tests fail with `UnimplementedError: runBurstWrite implemented in Task 11`.

- [ ] **Step 4: Implement runBurstWrite**

In `bluey/example/lib/features/stress_tests/infrastructure/stress_test_runner.dart`, replace the `runBurstWrite` body:

```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:bluey/bluey.dart';

import '../../../shared/stress_protocol.dart';
import '../domain/stress_test_config.dart';
import '../domain/stress_test_result.dart';

class StressTestRunner {
  Stream<StressTestResult> runBurstWrite(
    BurstWriteConfig config,
    Connection connection,
  ) async* {
    final stressChar = await _resolveStressChar(connection);

    // Test isolation: clean baseline before measuring.
    await stressChar.write(const ResetCommand().encode(), withResponse: true);

    var result = StressTestResult.initial();
    final stopwatch = Stopwatch()..start();
    yield result;

    final futures = <Future<void>>[];
    final payload = _generatePattern(config.payloadBytes);
    final cmd = EchoCommand(payload).encode();

    for (var i = 0; i < config.count; i++) {
      final opStart = stopwatch.elapsedMicroseconds;
      futures.add(() async {
        try {
          await stressChar.write(cmd, withResponse: config.withResponse);
          final latency = Duration(
            microseconds: stopwatch.elapsedMicroseconds - opStart,
          );
          result = result.recordSuccess(latency: latency);
        } catch (e) {
          final typeName = e.runtimeType.toString();
          final status = e is GattOperationFailedException ? e.status : null;
          result = result.recordFailure(typeName: typeName, status: status);
        }
      }());
    }

    await Future.wait(futures);
    stopwatch.stop();
    yield result.finished(elapsed: stopwatch.elapsed);
  }

  // ... other methods stubbed (UnimplementedError) until subsequent tasks ...

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
```

(Keep the other `run*` method stubs from Task 10 in place — they get replaced one at a time.)

- [ ] **Step 5: Run tests to verify they pass**

```bash
cd bluey/example && flutter test test/stress_tests/infrastructure/stress_test_runner_test.dart
```

Expected: 4 tests pass.

- [ ] **Step 6: Commit**

```bash
git add bluey/example/lib/features/stress_tests/infrastructure/stress_test_runner.dart \
        bluey/example/test/stress_tests/infrastructure/stress_test_runner_test.dart \
        bluey/example/test/fakes/fake_connection.dart \
        bluey/example/test/fakes/fake_remote_characteristic.dart
git commit -m "feat(example): implement StressTestRunner.runBurstWrite + test fakes"
```

---

## Task 12: Cubit + screen scaffold + visibility-gated button

**Files:**
- Create: `bluey/example/lib/features/stress_tests/presentation/stress_tests_state.dart`
- Create: `bluey/example/lib/features/stress_tests/presentation/stress_tests_cubit.dart`
- Create: `bluey/example/lib/features/stress_tests/presentation/stress_tests_screen.dart`
- Create: `bluey/example/lib/features/stress_tests/application/run_burst_write.dart`
- Create: `bluey/example/lib/features/stress_tests/di/stress_tests_module.dart`
- Modify: `bluey/example/lib/shared/di/service_locator.dart`
- Modify: `bluey/example/lib/features/connection/presentation/connection_screen.dart`

This task scaffolds enough UI to navigate from the connection screen to an empty stress-tests screen. Per-test cards and per-test logic come in subsequent tasks.

- [ ] **Step 1: Add the RunBurstWrite use case**

Write to `bluey/example/lib/features/stress_tests/application/run_burst_write.dart`:

```dart
import 'package:bluey/bluey.dart';

import '../domain/stress_test_config.dart';
import '../domain/stress_test_result.dart';
import '../infrastructure/stress_test_runner.dart';

class RunBurstWrite {
  final StressTestRunner _runner;
  RunBurstWrite(this._runner);

  Stream<StressTestResult> call(BurstWriteConfig config, Connection connection) {
    return _runner.runBurstWrite(config, connection);
  }
}
```

- [ ] **Step 2: Define the cubit state**

Write to `bluey/example/lib/features/stress_tests/presentation/stress_tests_state.dart`:

```dart
import 'package:equatable/equatable.dart';

import '../domain/stress_test.dart';
import '../domain/stress_test_config.dart';
import '../domain/stress_test_result.dart';

/// One per StressTest enum value. Holds the per-card UI state.
class TestCardState extends Equatable {
  final StressTest test;
  final StressTestConfig config;
  final StressTestResult? result;
  final bool isRunning;

  const TestCardState({
    required this.test,
    required this.config,
    this.result,
    this.isRunning = false,
  });

  TestCardState copyWith({
    StressTestConfig? config,
    StressTestResult? result,
    bool? isRunning,
  }) {
    return TestCardState(
      test: test,
      config: config ?? this.config,
      result: result,
      isRunning: isRunning ?? this.isRunning,
    );
  }

  @override
  List<Object?> get props => [test, config, result, isRunning];
}

class StressTestsState extends Equatable {
  final Map<StressTest, TestCardState> cards;

  /// True when ANY card is running; used to disable other cards' Run buttons.
  bool get anyRunning => cards.values.any((c) => c.isRunning);

  const StressTestsState({required this.cards});

  factory StressTestsState.initial() {
    return StressTestsState(cards: {
      StressTest.burstWrite: const TestCardState(
        test: StressTest.burstWrite,
        config: BurstWriteConfig(),
      ),
      StressTest.mixedOps: const TestCardState(
        test: StressTest.mixedOps,
        config: MixedOpsConfig(),
      ),
      StressTest.soak: const TestCardState(
        test: StressTest.soak,
        config: SoakConfig(),
      ),
      StressTest.timeoutProbe: const TestCardState(
        test: StressTest.timeoutProbe,
        config: TimeoutProbeConfig(),
      ),
      StressTest.failureInjection: const TestCardState(
        test: StressTest.failureInjection,
        config: FailureInjectionConfig(),
      ),
      StressTest.mtuProbe: const TestCardState(
        test: StressTest.mtuProbe,
        config: MtuProbeConfig(),
      ),
      StressTest.notificationThroughput: const TestCardState(
        test: StressTest.notificationThroughput,
        config: NotificationThroughputConfig(),
      ),
    });
  }

  StressTestsState updateCard(StressTest test, TestCardState newState) {
    return StressTestsState(cards: {
      for (final entry in cards.entries)
        entry.key: entry.key == test ? newState : entry.value,
    });
  }

  @override
  List<Object?> get props => [cards];
}
```

- [ ] **Step 3: Create the cubit**

Write to `bluey/example/lib/features/stress_tests/presentation/stress_tests_cubit.dart`:

```dart
import 'dart:async';

import 'package:bluey/bluey.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../application/run_burst_write.dart';
import '../domain/stress_test.dart';
import '../domain/stress_test_config.dart';
import 'stress_tests_state.dart';

class StressTestsCubit extends Cubit<StressTestsState> {
  final RunBurstWrite _runBurstWrite;
  final Connection _connection;
  StreamSubscription? _activeSub;

  StressTestsCubit({
    required RunBurstWrite runBurstWrite,
    required Connection connection,
  })  : _runBurstWrite = runBurstWrite,
        _connection = connection,
        super(StressTestsState.initial());

  /// Updates the config form for a card. Disabled while running.
  void updateConfig(StressTest test, StressTestConfig config) {
    final card = state.cards[test]!;
    if (card.isRunning) return;
    emit(state.updateCard(test, card.copyWith(config: config)));
  }

  /// Kicks off the test for [test]. Disables other Run buttons via
  /// state.anyRunning.
  Future<void> run(StressTest test) async {
    if (state.anyRunning) return;
    final card = state.cards[test]!;
    emit(state.updateCard(test, card.copyWith(isRunning: true)));

    final stream = switch (test) {
      StressTest.burstWrite =>
        _runBurstWrite(card.config as BurstWriteConfig, _connection),
      _ => Stream.error(UnimplementedError('Test $test not yet wired')),
    };

    _activeSub = stream.listen(
      (result) {
        emit(state.updateCard(
          test,
          card.copyWith(result: result, isRunning: result.isRunning),
        ));
      },
      onDone: () {
        emit(state.updateCard(
          test,
          state.cards[test]!.copyWith(isRunning: false),
        ));
      },
      onError: (Object e) {
        emit(state.updateCard(
          test,
          state.cards[test]!.copyWith(isRunning: false),
        ));
      },
    );
  }

  /// Cancels the current run. Background ops complete uncounted; the
  /// next run's Reset prologue cleans up server state.
  void stop() {
    _activeSub?.cancel();
    _activeSub = null;
    final running = state.cards.values
        .firstWhere((c) => c.isRunning, orElse: () => state.cards.values.first);
    if (running.isRunning) {
      emit(state.updateCard(running.test, running.copyWith(isRunning: false)));
    }
  }

  @override
  Future<void> close() {
    _activeSub?.cancel();
    return super.close();
  }
}
```

- [ ] **Step 4: Create a placeholder screen**

Write to `bluey/example/lib/features/stress_tests/presentation/stress_tests_screen.dart`:

```dart
import 'package:bluey/bluey.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../shared/di/service_locator.dart';
import '../application/run_burst_write.dart';
import 'stress_tests_cubit.dart';
import 'stress_tests_state.dart';

class StressTestsScreen extends StatelessWidget {
  final Connection connection;
  const StressTestsScreen({super.key, required this.connection});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => StressTestsCubit(
        runBurstWrite: getIt<RunBurstWrite>(),
        connection: connection,
      ),
      child: Scaffold(
        appBar: AppBar(title: const Text('Stress Tests')),
        body: BlocBuilder<StressTestsCubit, StressTestsState>(
          builder: (context, state) {
            // Per-card widgets land in Task 13. For scaffold, show the
            // count of cards and the running flag.
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('${state.cards.length} tests configured'),
                  const SizedBox(height: 8),
                  Text(
                    state.anyRunning ? 'A test is running' : 'Idle',
                    style: TextStyle(
                      color: state.anyRunning ? Colors.orange : Colors.grey,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Wire DI**

Write to `bluey/example/lib/features/stress_tests/di/stress_tests_module.dart`:

```dart
import 'package:get_it/get_it.dart';

import '../application/run_burst_write.dart';
import '../infrastructure/stress_test_runner.dart';

void registerStressTestsModule(GetIt getIt) {
  getIt.registerLazySingleton<StressTestRunner>(() => StressTestRunner());
  getIt.registerFactory<RunBurstWrite>(() => RunBurstWrite(getIt()));
}
```

In `bluey/example/lib/shared/di/service_locator.dart`, find the section that calls each `register…Module(getIt)` and add:

```dart
import '../../features/stress_tests/di/stress_tests_module.dart';
// ...
  registerStressTestsModule(getIt);
```

- [ ] **Step 6: Add the visibility-gated button to ConnectionScreen**

In `bluey/example/lib/features/connection/presentation/connection_screen.dart`:

(a) Add the imports at the top:

```dart
import '../../stress_tests/presentation/stress_tests_screen.dart';
import '../../../shared/stress_protocol.dart';
```

(b) Find the "Disconnect button" block (around line 609 in current code) and immediately after the closing `),` of the disconnect `GestureDetector`, add:

```dart
          // Stress Tests button (visible only when peer hosts the stress service)
          if (_hasStressService(state.services))
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => StressTestsScreen(
                      connection: state.connection!,
                    ),
                  ),
                ),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.bolt, size: 16, color: Colors.blueAccent),
                      const SizedBox(width: 8),
                      Text(
                        'Stress Tests',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.blueAccent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
```

(c) Add the visibility helper at the bottom of the file (or as a top-level function):

```dart
bool _hasStressService(List<bluey.RemoteService>? services) {
  if (services == null) return false;
  return services.any((s) => s.uuid.toString() == StressProtocol.serviceUuid);
}
```

- [ ] **Step 7: Run the workspace test suite to verify nothing regresses**

```bash
cd bluey/example && flutter test
```

Expected: all tests pass (no new tests added in this task; the new code is just UI/DI scaffolding).

- [ ] **Step 8: Manual smoke check**

Run the example app, start the server (so it registers the stress service), connect from another device. Verify:
- Connecting to a non-stress peer shows no "Stress Tests" button.
- Connecting to the example server (which hosts the stress service from Task 7) shows the button beneath Disconnect.
- Tapping the button navigates to the placeholder Stress Tests screen showing "7 tests configured / Idle".

- [ ] **Step 9: Commit**

```bash
git add bluey/example/lib/features/stress_tests/ \
        bluey/example/lib/shared/di/service_locator.dart \
        bluey/example/lib/features/connection/presentation/connection_screen.dart
git commit -m "feat(example): scaffold stress_tests feature + visibility-gated nav button"
```

---

## Task 13: TestCard + ConfigForm + ResultsPanel widgets — wire the BurstWrite card

**Files:**
- Create: `bluey/example/lib/features/stress_tests/presentation/widgets/test_card.dart`
- Create: `bluey/example/lib/features/stress_tests/presentation/widgets/config_form.dart`
- Create: `bluey/example/lib/features/stress_tests/presentation/widgets/results_panel.dart`
- Modify: `bluey/example/lib/features/stress_tests/presentation/stress_tests_screen.dart`
- Create: `bluey/example/test/stress_tests/presentation/widgets/test_card_test.dart`

This task adds the visible UI for one test (BurstWrite) end-to-end so we have the pattern set. Subsequent per-test tasks (15-20) just add config-form variants for their tests.

- [ ] **Step 1: Write a widget test for TestCard**

Write to `bluey/example/test/stress_tests/presentation/widgets/test_card_test.dart`:

```dart
import 'package:bluey_example/features/stress_tests/domain/stress_test.dart';
import 'package:bluey_example/features/stress_tests/domain/stress_test_config.dart';
import 'package:bluey_example/features/stress_tests/domain/stress_test_result.dart';
import 'package:bluey_example/features/stress_tests/presentation/widgets/test_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('Idle card shows test name and Run button', (tester) async {
    await tester.pumpWidget(wrap(TestCard(
      test: StressTest.burstWrite,
      config: const BurstWriteConfig(),
      result: null,
      isRunning: false,
      anyRunning: false,
      onRun: () {},
      onStop: () {},
      onConfigChanged: (_) {},
    )));

    expect(find.text('Burst write'), findsOneWidget);
    expect(find.text('Run'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);
  });

  testWidgets('Run button is disabled when another card is running', (tester) async {
    bool ran = false;
    await tester.pumpWidget(wrap(TestCard(
      test: StressTest.burstWrite,
      config: const BurstWriteConfig(),
      result: null,
      isRunning: false,
      anyRunning: true,
      onRun: () => ran = true,
      onStop: () {},
      onConfigChanged: (_) {},
    )));

    await tester.tap(find.text('Run'));
    await tester.pump();
    expect(ran, isFalse, reason: 'Run should be no-op when another card runs');
  });

  testWidgets('Results panel renders attempted/succeeded/failed', (tester) async {
    final result = StressTestResult.initial()
        .recordSuccess(latency: const Duration(milliseconds: 10))
        .recordFailure(typeName: 'GattTimeoutException');

    await tester.pumpWidget(wrap(TestCard(
      test: StressTest.burstWrite,
      config: const BurstWriteConfig(),
      result: result,
      isRunning: false,
      anyRunning: false,
      onRun: () {},
      onStop: () {},
      onConfigChanged: (_) {},
    )));

    expect(find.textContaining('2'), findsWidgets); // attempted
    expect(find.textContaining('GattTimeoutException'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd bluey/example && flutter test test/stress_tests/presentation/widgets/test_card_test.dart
```

Expected: compilation failure — `TestCard` not defined.

- [ ] **Step 3: Implement TestCard**

Write to `bluey/example/lib/features/stress_tests/presentation/widgets/test_card.dart`:

```dart
import 'package:flutter/material.dart';

import '../../domain/stress_test.dart';
import '../../domain/stress_test_config.dart';
import '../../domain/stress_test_result.dart';
import 'config_form.dart';
import 'results_panel.dart';

class TestCard extends StatelessWidget {
  final StressTest test;
  final StressTestConfig config;
  final StressTestResult? result;
  final bool isRunning;
  /// True when *some* card (possibly this one) is running. Used to
  /// disable the Run button on idle cards.
  final bool anyRunning;
  final VoidCallback onRun;
  final VoidCallback onStop;
  final ValueChanged<StressTestConfig> onConfigChanged;

  const TestCard({
    super.key,
    required this.test,
    required this.config,
    required this.result,
    required this.isRunning,
    required this.anyRunning,
    required this.onRun,
    required this.onStop,
    required this.onConfigChanged,
  });

  @override
  Widget build(BuildContext context) {
    final canRun = !anyRunning;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  test.displayName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Row(
                  children: [
                    OutlinedButton(
                      onPressed: canRun ? onRun : null,
                      child: const Text('Run'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: isRunning ? onStop : null,
                      child: const Text('Stop'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            ConfigForm(
              config: config,
              enabled: !isRunning,
              onChanged: onConfigChanged,
            ),
            if (result != null) ...[
              const SizedBox(height: 8),
              ResultsPanel(result: result!),
            ],
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Implement ConfigForm (BurstWrite-only for now)**

Write to `bluey/example/lib/features/stress_tests/presentation/widgets/config_form.dart`:

```dart
import 'package:flutter/material.dart';

import '../../domain/stress_test_config.dart';

class ConfigForm extends StatelessWidget {
  final StressTestConfig config;
  final bool enabled;
  final ValueChanged<StressTestConfig> onChanged;

  const ConfigForm({
    super.key,
    required this.config,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = config;
    if (c is BurstWriteConfig) return _burst(c);
    // Fallback for as-yet-unsupported configs (later tasks fill these in)
    return Text('Config form for ${c.runtimeType} not implemented yet');
  }

  Widget _burst(BurstWriteConfig c) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _intField(
          label: 'count',
          value: c.count,
          onChanged: (v) => onChanged(BurstWriteConfig(
            count: v,
            payloadBytes: c.payloadBytes,
            withResponse: c.withResponse,
          )),
        ),
        _intField(
          label: 'bytes',
          value: c.payloadBytes,
          onChanged: (v) => onChanged(BurstWriteConfig(
            count: c.count,
            payloadBytes: v,
            withResponse: c.withResponse,
          )),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(
              value: c.withResponse,
              onChanged: enabled
                  ? (v) => onChanged(BurstWriteConfig(
                        count: c.count,
                        payloadBytes: c.payloadBytes,
                        withResponse: v ?? true,
                      ))
                  : null,
            ),
            const Text('withResponse'),
          ],
        ),
      ],
    );
  }

  Widget _intField({
    required String label,
    required int value,
    required ValueChanged<int> onChanged,
  }) {
    return SizedBox(
      width: 100,
      child: TextField(
        enabled: enabled,
        controller: TextEditingController(text: value.toString()),
        decoration: InputDecoration(labelText: label, isDense: true),
        keyboardType: TextInputType.number,
        onSubmitted: (s) {
          final parsed = int.tryParse(s);
          if (parsed != null && parsed > 0) onChanged(parsed);
        },
      ),
    );
  }
}
```

- [ ] **Step 5: Implement ResultsPanel**

Write to `bluey/example/lib/features/stress_tests/presentation/widgets/results_panel.dart`:

```dart
import 'package:flutter/material.dart';

import '../../domain/stress_test_result.dart';

class ResultsPanel extends StatelessWidget {
  final StressTestResult result;
  const ResultsPanel({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final r = result;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Attempted ${r.attempted}  Succeeded ${r.succeeded}  Failed ${r.failed}'),
          if (r.failuresByType.isNotEmpty) ...[
            const SizedBox(height: 4),
            const Text('Failures:'),
            for (final entry in r.failuresByType.entries)
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Text('${entry.key} × ${entry.value}'),
              ),
            if (r.statusCounts.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Text(
                  'Status codes: ${r.statusCounts.entries.map((e) => '0x${e.key.toRadixString(16)} × ${e.value}').join(', ')}',
                ),
              ),
          ],
          if (r.latencies.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Median: ${r.medianLatency.inMilliseconds}ms  p95: ${r.p95Latency.inMilliseconds}ms',
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Elapsed: ${_format(r.elapsed)}',
              style: TextStyle(color: Colors.grey.shade700),
            ),
          ),
        ],
      ),
    );
  }

  String _format(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
```

- [ ] **Step 6: Update the screen to render TestCard for each card**

Replace the body of `StressTestsScreen` in `bluey/example/lib/features/stress_tests/presentation/stress_tests_screen.dart`:

```dart
        body: BlocBuilder<StressTestsCubit, StressTestsState>(
          builder: (context, state) {
            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                for (final entry in state.cards.entries)
                  TestCard(
                    test: entry.key,
                    config: entry.value.config,
                    result: entry.value.result,
                    isRunning: entry.value.isRunning,
                    anyRunning: state.anyRunning,
                    onRun: () => context.read<StressTestsCubit>().run(entry.key),
                    onStop: () => context.read<StressTestsCubit>().stop(),
                    onConfigChanged: (cfg) => context
                        .read<StressTestsCubit>()
                        .updateConfig(entry.key, cfg),
                  ),
              ],
            );
          },
        ),
```

Add the imports:

```dart
import 'widgets/test_card.dart';
```

- [ ] **Step 7: Run the widget tests**

```bash
cd bluey/example && flutter test test/stress_tests/presentation/widgets/test_card_test.dart
```

Expected: all 3 tests pass.

- [ ] **Step 8: Manual smoke check**

Run the example app, navigate to Stress Tests. Verify:
- 7 cards appear, one per test enum value.
- Burst write card has working `count`/`bytes`/`withResponse` form.
- Other cards show "Config form for X not implemented yet".
- Tap Run on Burst write — see live counter updates, then a final result.
- Hit Run on Burst write while it's running on another card — the second Run does nothing (other Run buttons are disabled).

- [ ] **Step 9: Commit**

```bash
git add bluey/example/lib/features/stress_tests/presentation/widgets/ \
        bluey/example/lib/features/stress_tests/presentation/stress_tests_screen.dart \
        bluey/example/test/stress_tests/presentation/widgets/
git commit -m "feat(example): TestCard/ConfigForm/ResultsPanel widgets + BurstWrite UI"
```

---

## Task 14: Implement runMixedOps + use case + UI

**Files:**
- Modify: `bluey/example/lib/features/stress_tests/infrastructure/stress_test_runner.dart`
- Create: `bluey/example/lib/features/stress_tests/application/run_mixed_ops.dart`
- Modify: `bluey/example/lib/features/stress_tests/di/stress_tests_module.dart`
- Modify: `bluey/example/lib/features/stress_tests/presentation/stress_tests_cubit.dart`
- Modify: `bluey/example/lib/features/stress_tests/presentation/widgets/config_form.dart`
- Modify: `bluey/example/test/stress_tests/infrastructure/stress_test_runner_test.dart`

- [ ] **Step 1: Write the failing runner test**

Append to `stress_test_runner_test.dart`:

```dart
group('StressTestRunner.runMixedOps', () {
  test('runs configured iterations of write+read+services+mtu', () async {
    // Track ops by what gets called.
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
    // Plus 1 reset write at the start = 1
    // Total writes = 1 + 3 = 4 (1 reset + 3 echoes)
    expect(writes, equals(4));
    expect(reads, equals(3));
    expect(last.attempted, equals(12)); // 3 iterations × 4 ops
    expect(conn.lastRequestedMtu, isNotNull);
  });
});
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd bluey/example && flutter test test/stress_tests/infrastructure/stress_test_runner_test.dart
```

Expected: fails with `UnimplementedError: runMixedOps implemented in Task 14`.

- [ ] **Step 3: Implement runMixedOps**

Replace the stub in `stress_test_runner.dart`:

```dart
  Stream<StressTestResult> runMixedOps(
    MixedOpsConfig config,
    Connection connection,
  ) async* {
    final stressChar = await _resolveStressChar(connection);

    await stressChar.write(const ResetCommand().encode(), withResponse: true);

    var result = StressTestResult.initial();
    final stopwatch = Stopwatch()..start();
    yield result;

    final payload = _generatePattern(20);
    final cmd = EchoCommand(payload).encode();

    Future<void> recordOp(Future<void> Function() op) async {
      final start = stopwatch.elapsedMicroseconds;
      try {
        await op();
        result = result.recordSuccess(
          latency: Duration(
            microseconds: stopwatch.elapsedMicroseconds - start,
          ),
        );
      } catch (e) {
        final status = e is GattOperationFailedException ? e.status : null;
        result = result.recordFailure(
          typeName: e.runtimeType.toString(),
          status: status,
        );
      }
    }

    final futures = <Future<void>>[];
    for (var i = 0; i < config.iterations; i++) {
      futures.add(recordOp(() => stressChar.write(cmd, withResponse: true)));
      futures.add(recordOp(() => stressChar.read()));
      futures.add(recordOp(() => connection.services(cache: false)));
      futures.add(recordOp(() => connection.requestMtu(247)));
    }
    await Future.wait(futures);
    stopwatch.stop();
    yield result.finished(elapsed: stopwatch.elapsed);
  }
```

(`requestMtu` is a method on `Connection`. If your local `Connection` doesn't expose it directly, route through `connection.requestMtu` or whatever the equivalent is.)

- [ ] **Step 4: Add the use case**

Write to `bluey/example/lib/features/stress_tests/application/run_mixed_ops.dart`:

```dart
import 'package:bluey/bluey.dart';

import '../domain/stress_test_config.dart';
import '../domain/stress_test_result.dart';
import '../infrastructure/stress_test_runner.dart';

class RunMixedOps {
  final StressTestRunner _runner;
  RunMixedOps(this._runner);

  Stream<StressTestResult> call(MixedOpsConfig config, Connection connection) {
    return _runner.runMixedOps(config, connection);
  }
}
```

- [ ] **Step 5: Register in DI**

In `stress_tests_module.dart`:

```dart
import '../application/run_mixed_ops.dart';
// ...
  getIt.registerFactory<RunMixedOps>(() => RunMixedOps(getIt()));
```

- [ ] **Step 6: Wire into the cubit**

In `stress_tests_cubit.dart`, add the use case as a constructor field and extend the `switch` in `run`:

```dart
import '../application/run_mixed_ops.dart';

// inside StressTestsCubit:
  final RunMixedOps _runMixedOps;

  StressTestsCubit({
    required RunBurstWrite runBurstWrite,
    required RunMixedOps runMixedOps,
    required Connection connection,
  })  : _runBurstWrite = runBurstWrite,
        _runMixedOps = runMixedOps,
        // ...

// inside run():
    final stream = switch (test) {
      StressTest.burstWrite =>
        _runBurstWrite(card.config as BurstWriteConfig, _connection),
      StressTest.mixedOps =>
        _runMixedOps(card.config as MixedOpsConfig, _connection),
      _ => Stream.error(UnimplementedError('Test $test not yet wired')),
    };
```

In `stress_tests_screen.dart`, update the `BlocProvider.create` to wire the new dependency:

```dart
        create: (_) => StressTestsCubit(
          runBurstWrite: getIt<RunBurstWrite>(),
          runMixedOps: getIt<RunMixedOps>(),
          connection: connection,
        ),
```

- [ ] **Step 7: Add a config form for MixedOpsConfig**

In `config_form.dart`, after the `_burst` method, add `_mixedOps` and dispatch to it from `build`:

```dart
  @override
  Widget build(BuildContext context) {
    final c = config;
    if (c is BurstWriteConfig) return _burst(c);
    if (c is MixedOpsConfig) return _mixedOps(c);
    return Text('Config form for ${c.runtimeType} not implemented yet');
  }

  Widget _mixedOps(MixedOpsConfig c) {
    return _intField(
      label: 'iterations',
      value: c.iterations,
      onChanged: (v) => onChanged(MixedOpsConfig(iterations: v)),
    );
  }
```

- [ ] **Step 8: Run all stress_tests tests**

```bash
cd bluey/example && flutter test test/stress_tests/
```

Expected: all tests pass.

- [ ] **Step 9: Commit**

```bash
git add bluey/example/lib/features/stress_tests/ \
        bluey/example/test/stress_tests/infrastructure/
git commit -m "feat(example): implement runMixedOps + UI"
```

---

## Task 15: Implement runSoak + use case + UI

**Files:**
- Modify: `bluey/example/lib/features/stress_tests/infrastructure/stress_test_runner.dart`
- Create: `bluey/example/lib/features/stress_tests/application/run_soak.dart`
- Modify: `bluey/example/lib/features/stress_tests/di/stress_tests_module.dart`
- Modify: `bluey/example/lib/features/stress_tests/presentation/stress_tests_cubit.dart`
- Modify: `bluey/example/lib/features/stress_tests/presentation/widgets/config_form.dart`
- Modify: `bluey/example/test/stress_tests/infrastructure/stress_test_runner_test.dart`

- [ ] **Step 1: Write the failing runner test**

Append to `stress_test_runner_test.dart`:

```dart
group('StressTestRunner.runSoak', () {
  test('runs ops for the configured duration at the configured interval', () async {
    var writes = 0;
    stressChar.onWriteHook = (value, {required bool withResponse}) async {
      writes++;
    };

    final config = const SoakConfig(
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
```

- [ ] **Step 2: Run to verify fail**

Expected: `UnimplementedError`.

- [ ] **Step 3: Implement runSoak**

In `stress_test_runner.dart`:

```dart
  Stream<StressTestResult> runSoak(
    SoakConfig config,
    Connection connection,
  ) async* {
    final stressChar = await _resolveStressChar(connection);

    await stressChar.write(const ResetCommand().encode(), withResponse: true);

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
        final status = e is GattOperationFailedException ? e.status : null;
        result = result.recordFailure(
          typeName: e.runtimeType.toString(),
          status: status,
        );
      }
      result = result.withElapsed(stopwatch.elapsed);
      yield result;
      // Wait until next tick or end-of-test, whichever comes first.
      final remaining = endTime - stopwatch.elapsed;
      final waitFor = remaining < config.interval ? remaining : config.interval;
      if (waitFor > Duration.zero) await Future<void>.delayed(waitFor);
    }
    stopwatch.stop();
    yield result.finished(elapsed: stopwatch.elapsed);
  }
```

- [ ] **Step 4: Add use case + DI + cubit wiring + form**

Mirror Task 14 exactly: create `run_soak.dart`, register in module, add field on cubit + dispatch in switch + screen wiring, add `_soak(c)` form to `config_form.dart`:

```dart
  Widget _soak(SoakConfig c) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _intField(
          label: 'duration (s)',
          value: c.duration.inSeconds,
          onChanged: (v) => onChanged(SoakConfig(
            duration: Duration(seconds: v),
            interval: c.interval,
            payloadBytes: c.payloadBytes,
          )),
        ),
        _intField(
          label: 'interval (ms)',
          value: c.interval.inMilliseconds,
          onChanged: (v) => onChanged(SoakConfig(
            duration: c.duration,
            interval: Duration(milliseconds: v),
            payloadBytes: c.payloadBytes,
          )),
        ),
        _intField(
          label: 'bytes',
          value: c.payloadBytes,
          onChanged: (v) => onChanged(SoakConfig(
            duration: c.duration,
            interval: c.interval,
            payloadBytes: v,
          )),
        ),
      ],
    );
  }
```

Add `if (c is SoakConfig) return _soak(c);` to the dispatch in `build`.

- [ ] **Step 5: Run tests and commit**

```bash
cd bluey/example && flutter test test/stress_tests/
git add bluey/example/lib/features/stress_tests/ \
        bluey/example/test/stress_tests/
git commit -m "feat(example): implement runSoak + UI"
```

---

## Task 16: Implement runTimeoutProbe + use case + UI

**Files:** same shape as Task 14 — runner method, use case, DI, cubit, form, runner test.

- [ ] **Step 1: Failing test**

```dart
group('StressTestRunner.runTimeoutProbe', () {
  test('sends DelayAck command sized past the timeout and counts the failure', () async {
    final writes = <Uint8List>[];
    stressChar.onWriteHook = (value, {required bool withResponse}) async {
      writes.add(Uint8List.fromList(value));
      // For the actual delay-ack write (opcode 0x03), simulate a timeout.
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
```

- [ ] **Step 2: Verify red**

- [ ] **Step 3: Implement runTimeoutProbe**

```dart
  Stream<StressTestResult> runTimeoutProbe(
    TimeoutProbeConfig config,
    Connection connection,
  ) async* {
    final stressChar = await _resolveStressChar(connection);

    await stressChar.write(const ResetCommand().encode(), withResponse: true);

    var result = StressTestResult.initial();
    final stopwatch = Stopwatch()..start();
    yield result;

    // Default per-op timeout is 10s; we ask the server to delay 2s past
    // that so the client-side timer fires deterministically.
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
      final status = e is GattOperationFailedException ? e.status : null;
      result = result.recordFailure(
        typeName: e.runtimeType.toString(),
        status: status,
      );
    }
    stopwatch.stop();
    yield result.finished(elapsed: stopwatch.elapsed);
  }
```

- [ ] **Step 4-7: Use case, DI, cubit dispatch, form (one int field for `delayPastTimeout` in seconds), commit**

```bash
git commit -m "feat(example): implement runTimeoutProbe + UI"
```

---

## Task 17: Implement runFailureInjection + use case + UI

**Files:** same shape.

- [ ] **Step 1: Failing test**

```dart
group('StressTestRunner.runFailureInjection', () {
  test('writes DropNext, then writeCount echoes — first echo throws timeout', () async {
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
```

- [ ] **Step 2: Verify red**

- [ ] **Step 3: Implement runFailureInjection**

```dart
  Stream<StressTestResult> runFailureInjection(
    FailureInjectionConfig config,
    Connection connection,
  ) async* {
    final stressChar = await _resolveStressChar(connection);

    await stressChar.write(const ResetCommand().encode(), withResponse: true);
    await stressChar.write(const DropNextCommand().encode(), withResponse: true);

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
        final status = e is GattOperationFailedException ? e.status : null;
        result = result.recordFailure(
          typeName: e.runtimeType.toString(),
          status: status,
        );
      }
      yield result;
    }
    stopwatch.stop();
    yield result.finished(elapsed: stopwatch.elapsed);
  }
```

- [ ] **Steps 4-7: Use case, DI, cubit dispatch, form (single `writeCount` int field), commit**

```bash
git commit -m "feat(example): implement runFailureInjection + UI"
```

---

## Task 18: Implement runMtuProbe + use case + UI

**Files:** same shape.

- [ ] **Step 1: Failing test**

```dart
group('StressTestRunner.runMtuProbe', () {
  test('requests MTU then sends sized writes', () async {
    var writes = 0;
    stressChar.onWriteHook = (value, {required bool withResponse}) async {
      // Reset + SetPayloadSize + N echoes; we just count.
      writes++;
    };

    final results = await runner
        .runMtuProbe(
          const MtuProbeConfig(requestedMtu: 100, payloadBytes: 50),
          conn,
        )
        .toList();

    expect(conn.lastRequestedMtu, equals(100));
    final last = results.last;
    expect(last.isRunning, isFalse);
    // At least one successful write of payloadBytes=50.
    expect(last.succeeded, greaterThanOrEqualTo(1));
  });
});
```

- [ ] **Step 2: Verify red**

- [ ] **Step 3: Implement runMtuProbe**

```dart
  Stream<StressTestResult> runMtuProbe(
    MtuProbeConfig config,
    Connection connection,
  ) async* {
    final stressChar = await _resolveStressChar(connection);

    await stressChar.write(const ResetCommand().encode(), withResponse: true);

    var result = StressTestResult.initial();
    final stopwatch = Stopwatch()..start();
    yield result;

    // Negotiate MTU.
    try {
      await connection.requestMtu(config.requestedMtu);
      result = result.recordSuccess(
        latency: Duration(microseconds: stopwatch.elapsedMicroseconds),
      );
    } catch (e) {
      final status = e is GattOperationFailedException ? e.status : null;
      result = result.recordFailure(
        typeName: e.runtimeType.toString(),
        status: status,
      );
      yield result.finished(elapsed: stopwatch.elapsed);
      return;
    }

    // Tell the server to return payloadBytes-sized reads.
    await stressChar.write(
      SetPayloadSizeCommand(sizeBytes: config.payloadBytes).encode(),
      withResponse: true,
    );

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
        final status = e is GattOperationFailedException ? e.status : null;
        result = result.recordFailure(
          typeName: e.runtimeType.toString(),
          status: status,
        );
      }
      yield result;
    }
    stopwatch.stop();
    yield result.finished(elapsed: stopwatch.elapsed);
  }
```

- [ ] **Steps 4-7: Use case, DI, cubit dispatch, form (`requestedMtu` and `payloadBytes` int fields), commit**

```bash
git commit -m "feat(example): implement runMtuProbe + UI"
```

---

## Task 19: Implement runNotificationThroughput + use case + UI

**Files:** same shape.

- [ ] **Step 1: Failing test**

```dart
group('StressTestRunner.runNotificationThroughput', () {
  test('counts notifications matching the active burst-id', () async {
    stressChar.onWriteHook = (value, {required bool withResponse}) async {
      // After reset+burstMe write, simulate the server emitting 5 notifs
      // with burst-id = 1 (mocked: pretend the server's first burst).
      if (value.isNotEmpty && value.first == 0x02) {
        // Defer emissions to the next event loop tick.
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
```

- [ ] **Step 2: Verify red**

- [ ] **Step 3: Implement runNotificationThroughput**

```dart
  Stream<StressTestResult> runNotificationThroughput(
    NotificationThroughputConfig config,
    Connection connection,
  ) async* {
    final stressChar = await _resolveStressChar(connection);

    await stressChar.write(const ResetCommand().encode(), withResponse: true);

    var result = StressTestResult.initial();
    final stopwatch = Stopwatch()..start();
    yield result;

    int? expectedBurstId;
    var receivedCount = 0;
    final completer = Completer<void>();

    final sub = stressChar.notifications.listen((bytes) {
      if (bytes.isEmpty) return;
      final id = bytes[0];
      if (expectedBurstId == null) {
        expectedBurstId = id;
      } else if (id != expectedBurstId) {
        return; // Straggler from a previous burst — drop.
      }
      receivedCount++;
      result = result.recordSuccess(
        latency: Duration(microseconds: stopwatch.elapsedMicroseconds),
      );
      if (receivedCount >= config.count && !completer.isCompleted) {
        completer.complete();
      }
    });

    // Kick the server.
    await stressChar.write(
      BurstMeCommand(count: config.count, payloadSize: config.payloadBytes)
          .encode(),
      withResponse: true,
    );

    // Wait for all expected notifications, with a generous timeout
    // proportional to count (1ms per notification + 1s overhead).
    final timeout = Duration(milliseconds: config.count + 1000);
    try {
      await completer.future.timeout(timeout);
    } on TimeoutException {
      // Record any missing notifications as failures.
      final missing = config.count - receivedCount;
      for (var i = 0; i < missing; i++) {
        result = result.recordFailure(typeName: 'NotificationTimeout');
      }
    }
    await sub.cancel();

    stopwatch.stop();
    yield result.finished(elapsed: stopwatch.elapsed);
  }
```

- [ ] **Steps 4-7: Use case, DI, cubit dispatch, form (`count` and `payloadBytes` fields), commit**

```bash
git commit -m "feat(example): implement runNotificationThroughput + UI"
```

---

## Task 20: Library logging instrumentation — bluey.connection + bluey.gatt

**Files:**
- Modify: `bluey/lib/src/bluey.dart`
- Modify: `bluey/lib/src/connection/bluey_connection.dart`

The library has zero logging today; this and Task 21 add `dart:developer.log` calls at the points named in the spec.

- [ ] **Step 1: Add bluey.connection logger to Bluey.connect**

In `bluey/lib/src/bluey.dart`, add `import 'dart:developer' as dev;` at the top.

Find the public `connect` method on `Bluey`. At the start of the method (after argument validation), add:

```dart
    dev.log(
      'connect started: deviceId=${device.id}, address=${device.address}',
      name: 'bluey.connection',
    );
```

After `_upgradeIfBlueyServer` (or wherever the success path returns), add:

```dart
    dev.log(
      'connect succeeded: deviceId=${device.id}, services=${(connection as BlueyConnection).cachedServiceCount ?? '?'}',
      name: 'bluey.connection',
    );
```

In any catch block on the connect path that emits a failure result:

```dart
    dev.log(
      'connect failed: deviceId=${device.id}, exception=${e.runtimeType}',
      name: 'bluey.connection',
      level: 1000, // SEVERE
      error: e,
    );
```

(Note: `cachedServiceCount` doesn't exist yet — either add a public getter to `BlueyConnection` returning the cached service list size, or omit the count from the log. Trust the implementer to make the smallest change.)

- [ ] **Step 2: Add bluey.gatt logger for op lifecycle in BlueyConnection**

In `bluey/lib/src/connection/bluey_connection.dart`, add `import 'dart:developer' as dev;`.

Wrap each public op method (read, write, discoverServices, requestMtu, readRssi, setNotification) with start/complete logging. The pattern, illustrated for `write`:

```dart
  Future<void> write(Uint8List value, {bool withResponse = true}) async {
    dev.log(
      'write start: deviceId=$_deviceId, char=$uuid, bytes=${value.length}',
      name: 'bluey.gatt',
    );
    final stopwatch = Stopwatch()..start();
    try {
      await _translateGattPlatformError(
        _deviceId,
        'writeCharacteristic',
        () => _platform.writeCharacteristic(
          _connectionId,
          uuid.toString(),
          value,
          withResponse,
        ),
      );
      dev.log(
        'write complete: deviceId=$_deviceId, char=$uuid, '
        '${stopwatch.elapsedMilliseconds}ms',
        name: 'bluey.gatt',
      );
    } catch (e) {
      final status = e is GattOperationFailedException ? ' status=${e.status}' : '';
      dev.log(
        'write failed: deviceId=$_deviceId, char=$uuid, '
        'exception=${e.runtimeType}$status, ${stopwatch.elapsedMilliseconds}ms',
        name: 'bluey.gatt',
        level: 900, // WARNING
        error: e,
      );
      rethrow;
    }
  }
```

Apply the same pattern to `read`, `services` (discover), `requestMtu`, `readRssi`, and `setNotification`. Include relevant identifying info per op.

For state-stream emissions in `BlueyConnection` (find where `_stateController.add(state)` is called), add:

```dart
    dev.log(
      'state transition: $_state → $newState',
      name: 'bluey.connection',
    );
```

For Service Changed (find the platform service-changed subscription):

```dart
    dev.log(
      'Service Changed received: deviceId=$_deviceId',
      name: 'bluey.gatt',
    );
```

- [ ] **Step 3: Run all bluey tests**

```bash
cd bluey && flutter test
```

Expected: all tests pass (logging is additive; no behaviour changes).

- [ ] **Step 4: Manual smoke check**

Run the example app with devtools open, perform a connect / disconnect cycle. Filter the devtools log by `bluey.connection` and `bluey.gatt` — verify entries appear at the right lifecycle points.

- [ ] **Step 5: Commit**

```bash
git add bluey/lib/src/bluey.dart bluey/lib/src/connection/bluey_connection.dart
git commit -m "chore(bluey): instrument bluey.connection and bluey.gatt loggers"
```

---

## Task 21: Library logging — bluey.lifecycle + bluey.peer + bluey.server

**Files:**
- Modify: `bluey/lib/src/connection/lifecycle_client.dart`
- Modify: `bluey/lib/src/peer/bluey_peer.dart`
- Modify: `bluey/lib/src/bluey.dart` (for `_upgradeIfBlueyServer`)
- Modify: `bluey/lib/src/gatt_server/bluey_server.dart`

- [ ] **Step 1: Add lifecycle logger**

In `bluey/lib/src/connection/lifecycle_client.dart`, add `import 'dart:developer' as dev;`.

In `start()`, after `_heartbeatCharUuid = heartbeatChar.uuid.toString();`:

```dart
    dev.log(
      'heartbeat started: char=$_heartbeatCharUuid',
      name: 'bluey.lifecycle',
    );
```

In `_beginHeartbeat(interval)`:

```dart
    dev.log(
      'heartbeat interval set: ${interval.inMilliseconds}ms',
      name: 'bluey.lifecycle',
    );
```

In `_sendHeartbeat`'s `catchError` (only on counted dead-peer signals):

```dart
      _consecutiveFailures++;
      dev.log(
        'heartbeat failed (counted): $_consecutiveFailures/$maxFailedHeartbeats — ${error.runtimeType}',
        name: 'bluey.lifecycle',
        level: 900,
      );
      if (_consecutiveFailures >= maxFailedHeartbeats) {
        dev.log(
          'heartbeat threshold reached — invoking onServerUnreachable',
          name: 'bluey.lifecycle',
          level: 1000,
        );
        stop();
        onServerUnreachable();
      }
```

(Successful heartbeats deliberately not logged — would be ~12 entries/minute per connection.)

- [ ] **Step 2: Add peer logger**

In `bluey/lib/src/peer/bluey_peer.dart` and `bluey/lib/src/bluey.dart` `_upgradeIfBlueyServer`, instrument the upgrade path:

```dart
import 'dart:developer' as dev;

// At the top of the upgrade attempt:
    dev.log('upgrade attempt: deviceId=...', name: 'bluey.peer');

// After control service discovery:
    dev.log(
      controlService != null
          ? 'control service discovered'
          : 'no control service — peer is not a bluey peer',
      name: 'bluey.peer',
    );

// After server ID read (success):
    dev.log('serverId read: $serverId', name: 'bluey.peer');

// After successful upgrade:
    dev.log('upgrade complete: deviceId=...', name: 'bluey.peer');
```

(Adapt the variable names to match the actual code.)

- [ ] **Step 3: Add server logger**

In `bluey/lib/src/gatt_server/bluey_server.dart`, add `import 'dart:developer' as dev;`.

Instrument:
- Server start (constructor or `start()` method): `'server initialized'`
- `addService`: `'service added: ${service.uuid}'`
- `startAdvertising` / `stopAdvertising`: `'advertising started'` / `'advertising stopped'`
- Central connected (in the connection observer): `'central connected: ${client.id}'`
- Central disconnected: `'central disconnected: $clientId'`

Each at default level except disconnect, which uses `Level.WARNING` (900) if it was unexpected.

- [ ] **Step 4: Run all tests**

```bash
cd bluey && flutter test
cd ../bluey_platform_interface && flutter test
cd ../bluey_android && flutter test
cd ../bluey_ios && flutter test
cd ../bluey_android/android && ./gradlew test
```

Expected: all green.

- [ ] **Step 5: Manual verification**

Run the example app with devtools open. Connect, then disconnect, then reconnect. Verify each logger namespace shows entries:
- `bluey.connection` — connect lifecycle
- `bluey.gatt` — per-op start/complete (from Task 20)
- `bluey.lifecycle` — heartbeat start, interval, no per-heartbeat noise
- `bluey.peer` — upgrade path
- `bluey.server` — service / advertising / central events

- [ ] **Step 6: Commit**

```bash
git add bluey/lib/src/connection/lifecycle_client.dart \
        bluey/lib/src/peer/bluey_peer.dart \
        bluey/lib/src/bluey.dart \
        bluey/lib/src/gatt_server/bluey_server.dart
git commit -m "chore(bluey): instrument bluey.lifecycle, bluey.peer, bluey.server loggers"
```

---

## Task 22: Final verification + docs

**Files:**
- Modify: `bluey/example/README.md` (or create if absent) — short note on stress tests
- Modify: `bluey/README.md` (or wherever consumer-facing docs live) — document logger names

- [ ] **Step 1: Run full test suite + analyze**

```bash
cd bluey && flutter test 2>&1 | tail -5
cd ../bluey_platform_interface && flutter test 2>&1 | tail -5
cd ../bluey_android && flutter test 2>&1 | tail -5
cd ../bluey_ios && flutter test 2>&1 | tail -5
cd ../bluey/example && flutter test 2>&1 | tail -5
cd ../../ && flutter analyze
cd bluey_android/android && ./gradlew test
```

Expected: all green; `flutter analyze` shows "No issues found".

- [ ] **Step 2: Document the logger namespace**

In `bluey/README.md`, add a section near the top:

```markdown
## Logging

Bluey emits diagnostic events via `dart:developer.log` under five named loggers:

| Logger | Events |
|--------|--------|
| `bluey.connection` | connect / disconnect lifecycle, state transitions |
| `bluey.gatt` | per-operation start/complete/fail (read, write, discover, MTU, RSSI, notify) |
| `bluey.lifecycle` | heartbeat start, failure counter increments, peer-unreachable trip |
| `bluey.peer` | bluey-peer upgrade path (control-service discovery, serverId read) |
| `bluey.server` | server start, service registration, advertising state, central connect/disconnect |

Filter in DevTools by logger name; in Android logcat, filter for `flutter:`; in Xcode console, filter for the named-logger string.
```

- [ ] **Step 3: Document stress tests in example README**

In `bluey/example/README.md`, add:

```markdown
## Stress tests

When connected to a peer running this example app's server, a "Stress Tests" button appears beneath Disconnect on the connection screen. Seven tests are available:

- **Burst write** — N parallel writes; measures success rate and latency
- **Mixed ops** — concurrent write/read/discoverServices/requestMtu cycles
- **Soak** — sustained writes over a duration
- **Timeout probe** — deliberately triggers GattTimeoutException via `delayAck`
- **Failure injection** — server drops one write via `dropNext`; verifies recovery
- **MTU probe** — negotiates MTU then writes/reads payloads at the new size
- **Notification throughput** — server bursts N notifications; verifies all received

Each card has its own configuration form. While one test runs, the Run buttons on other cards disable (one-test-at-a-time invariant).

Tests are isolated by sending a `Reset` command before each run; this clears any state left by a prior cancelled test.
```

- [ ] **Step 4: Commit**

```bash
git add bluey/README.md bluey/example/README.md
git commit -m "docs: document bluey logger namespace and example stress tests"
```

- [ ] **Step 5: Push the branch**

```bash
git push -u origin <branch-name>
```

(If using a worktree on a feature branch, push that branch.)

---

## Self-review checklist

Reviewed against the spec:

| Spec section | Plan task(s) | Coverage |
|---|---|---|
| Stress protocol UUIDs + 6 opcodes | Tasks 1, 2, 3 | ✓ |
| Server-side `StressServiceHandler` (echo) | Task 4 | ✓ |
| Server-side handlers for BurstMe / DelayAck / DropNext / SetPayloadSize | Task 5 | ✓ |
| Server-side `Reset` + burst-abort | Task 6 | ✓ |
| Wire stress service into example server | Task 7 | ✓ |
| `StressTest` enum + `StressTestConfig` hierarchy | Task 8 | ✓ |
| `StressTestResult` aggregation | Task 9 | ✓ |
| `StressTestRunner` skeleton | Task 10 | ✓ |
| `runBurstWrite` impl + tests | Task 11 | ✓ |
| Cubit + screen + visibility-gated nav | Task 12 | ✓ |
| `TestCard` + `ConfigForm` + `ResultsPanel` widgets | Task 13 | ✓ |
| `runMixedOps` | Task 14 | ✓ |
| `runSoak` | Task 15 | ✓ |
| `runTimeoutProbe` | Task 16 | ✓ |
| `runFailureInjection` | Task 17 | ✓ |
| `runMtuProbe` | Task 18 | ✓ |
| `runNotificationThroughput` (with burst-id filtering) | Task 19 | ✓ |
| Library `bluey.connection` + `bluey.gatt` logging | Task 20 | ✓ |
| Library `bluey.lifecycle` + `bluey.peer` + `bluey.server` logging | Task 21 | ✓ |
| Documentation | Task 22 | ✓ |
| Test isolation (Reset prologue) | Tasks 11, 14, 15, 16, 17, 18, 19 (built into each runner method) | ✓ |
| Burst-id filtering | Task 19 | ✓ |
| One-test-at-a-time UI invariant | Task 12 (cubit), Task 13 (TestCard widget) | ✓ |
| Visibility rule (button hidden when service absent) | Task 12 | ✓ |

No spec gaps identified.

## Out-of-scope (per spec)

- Proper logging framework (consumer sinks, levels API, structured events, native log routing) — separate spec.
- CSV export of results.
- Saved test presets.
- History of past runs (only last result per card shown).
- Automated test capturing `dev.log` output (no dedicated logging tests).
