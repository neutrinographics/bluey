# Write-Integrity Stress Test (I344) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the example app's `mtuProbe` stress test into a chunked, byte-exact, both-write-types transfer-integrity check that reproduces (and guards against a regression of) the I343 silent-truncation bug.

**Architecture:** Add one wire command (`TransferChunk`, opcode `0x07`) carrying a fragment of a larger logical payload. The server reassembles fragments into a per-instance buffer and exposes the result on read. The client chunks a deterministic pattern (`byte[i] = i & 0xff`) sized to the connection's real `maxWritePayload` (minus the chunk header), sends each fragment in the round's write type, reads the reassembled buffer back, and byte-compares it via a pure, unit-tested `evaluateTransfer` verdict function. The round runs once `withoutResponse` (the I343 path) and once `withResponse`. All of this is example-app test tooling — **no bluey-library changes**.

**Tech Stack:** Dart / Flutter (`bluey/example`), `flutter test`, `mocktail`.

**Spec:** `docs/superpowers/specs/2026-06-03-write-integrity-stress-test-design.md`

---

## Pre-step: branch

- [ ] Create the branch off `main`:

```bash
cd /Users/joel/git/neutrinographics/bluey
git checkout main && git checkout -b i344-write-integrity-stress-test
```

---

## File Structure

- **Modify** `bluey/example/lib/shared/stress_protocol.dart` — add the `TransferChunk` command (opcode `0x07`, `headerBytes = 7`) + its `case 0x07` in the `decode` dispatcher.
- **Modify** `bluey/example/test/shared/stress_protocol_test.dart` — encode/decode/equality/too-short tests for `TransferChunk`.
- **Modify** `bluey/example/lib/features/server/infrastructure/stress_service_handler.dart` — per-instance reassembly buffer, `TransferChunk` switch case, and reassembly clearing in the `ResetCommand` case.
- **Modify** `bluey/example/test/server/infrastructure/stress_service_handler_test.dart` — reassembly tests (happy path, reset-on-seq-0, gap fault, ResetCommand clears).
- **Create** `bluey/example/lib/features/stress_tests/domain/transfer_verdict.dart` — pure `TransferVerdict` value object + `evaluateTransfer(...)` function.
- **Create** `bluey/example/test/stress_tests/domain/transfer_verdict_test.dart` — verdict unit tests.
- **Modify** `bluey/example/lib/features/stress_tests/infrastructure/stress_test_runner.dart` — rewrite the `runMtuProbe` round: query `maxWritePayload`, chunk, send both write types, read back, verify via `evaluateTransfer`; add a private `_sendChunked` helper.
- **Modify** `bluey/example/lib/features/stress_tests/presentation/widgets/stress_test_help_content.dart` — update the `mtuProbe` help text to describe the byte-exact chunked check.

No config-form or enum changes are needed: `MtuProbeConfig` already exposes `payloadBytes` as a free-form int field (the `_intField` has no upper cap, so values like `600` are already enterable), and the runner method signature `runMtuProbe(MtuProbeConfig, Connection)` is unchanged.

---

## Task 1: `TransferChunk` command (opcode 0x07)

**Files:**
- Modify: `bluey/example/lib/shared/stress_protocol.dart`
- Test: `bluey/example/test/shared/stress_protocol_test.dart`

- [ ] **Step 1: Write the failing tests**

Append this group inside `main()` in `bluey/example/test/shared/stress_protocol_test.dart`, immediately before the final closing `}` of `main()` (i.e. after the `ResetCommand` group's closing `});`):

```dart
  group('TransferChunk', () {
    test('headerBytes is 7 (opcode + seq u16 + totalLen u32)', () {
      expect(TransferChunk.headerBytes, equals(7));
    });

    test('encode layout is [0x07, seq_lo, seq_hi, len0..len3 LE, ...data]', () {
      final cmd = TransferChunk(
        seq: 0x0102,
        totalLen: 0x03040506,
        data: Uint8List.fromList([0xAA, 0xBB]),
      );
      expect(
        cmd.encode(),
        equals(
          Uint8List.fromList([
            0x07, // opcode
            0x02, 0x01, // seq = 0x0102, little-endian
            0x06, 0x05, 0x04, 0x03, // totalLen = 0x03040506, little-endian
            0xAA, 0xBB, // data
          ]),
        ),
      );
    });

    test('encode supports an empty data fragment', () {
      final cmd = TransferChunk(seq: 0, totalLen: 0, data: Uint8List(0));
      expect(cmd.encode(), hasLength(TransferChunk.headerBytes));
      expect(cmd.encode()[0], equals(0x07));
    });

    test('decode round-trips seq, totalLen, and data', () {
      final original = TransferChunk(
        seq: 700,
        totalLen: 100000,
        data: Uint8List.fromList([1, 2, 3, 4, 5]),
      );
      final decoded = StressCommand.decode(original.encode());
      expect(decoded, isA<TransferChunk>());
      final t = decoded as TransferChunk;
      expect(t.seq, equals(700));
      expect(t.totalLen, equals(100000));
      expect(t.data, equals(Uint8List.fromList([1, 2, 3, 4, 5])));
    });

    test('decode throws when the header is shorter than 6 body bytes', () {
      // opcode + 3 body bytes = needs at least 6 body bytes for the header.
      expect(
        () => StressCommand.decode(Uint8List.fromList([0x07, 0x00, 0x00, 0x00])),
        throwsA(
          isA<StressProtocolException>().having((e) => e.opcode, 'opcode', 0x07),
        ),
      );
    });

    test('TransferChunk instances with equal fields are equal', () {
      expect(
        TransferChunk(seq: 1, totalLen: 9, data: Uint8List.fromList([7, 8])),
        equals(
          TransferChunk(seq: 1, totalLen: 9, data: Uint8List.fromList([7, 8])),
        ),
      );
    });

    test('TransferChunk defensively copies its data', () {
      final mutable = Uint8List.fromList([1, 2, 3]);
      final cmd = TransferChunk(seq: 0, totalLen: 3, data: mutable);
      mutable[0] = 99;
      expect(cmd.data[0], equals(1));
    });
  });
```

- [ ] **Step 2: Run, verify it fails**

Run: `cd bluey/example && flutter test test/shared/stress_protocol_test.dart`
Expected: FAIL — `TransferChunk` is undefined and `decode` has no `0x07` case.

- [ ] **Step 3: Add the `TransferChunk` class**

In `bluey/example/lib/shared/stress_protocol.dart`, add this class after the `ResetCommand` class (after its closing `}` near line 217, before the `StressProtocolException` class):

```dart
/// TransferChunk: one fragment of a larger logical payload the client is
/// streaming to the server for byte-exact reassembly. The server appends
/// [data] in ascending [seq] order; once the reassembled length reaches
/// [totalLen] the result becomes the value returned by the next read.
/// Opcode 0x07.
///
/// Wire layout: `[0x07][seq u16 LE][totalLen u32 LE][data…]`. The 7-byte
/// header ([headerBytes]) must be subtracted from the connection's max
/// write payload when sizing each fragment, so the framed write stays
/// within a single ATT packet.
class TransferChunk extends StressCommand {
  /// Framing overhead per chunk: 1 opcode + 2 seq + 4 totalLen = 7 bytes.
  static const int headerBytes = 7;

  /// Zero-based fragment index. `seq == 0` resets the server's buffer.
  final int seq;

  /// Total length of the complete logical payload, repeated in every
  /// fragment so the server knows when reassembly is complete.
  final int totalLen;

  /// This fragment's bytes.
  final Uint8List data;

  TransferChunk({
    required this.seq,
    required this.totalLen,
    required Uint8List data,
  }) : data = Uint8List.fromList(data);

  @override
  Uint8List encode() {
    final out = Uint8List(headerBytes + data.length);
    out[0] = 0x07;
    final header = out.buffer.asByteData();
    header.setUint16(1, seq, Endian.little);
    header.setUint32(3, totalLen, Endian.little);
    out.setRange(headerBytes, out.length, data);
    return out;
  }

  @override
  bool operator ==(Object other) =>
      other is TransferChunk &&
      other.seq == seq &&
      other.totalLen == totalLen &&
      const ListEquality<int>().equals(other.data, data);

  @override
  int get hashCode => Object.hash(seq, totalLen, Object.hashAll(data));
}
```

- [ ] **Step 4: Add the `decode` case**

In the same file, in `StressCommand.decode`, add a `case 0x07` immediately before the `default:` case in the `switch (opcode)` (after the `case 0x06: return const ResetCommand();` line):

```dart
      case 0x07:
        if (body.length < 6) {
          throw StressProtocolException(
            opcode: opcode,
            message: 'TransferChunk header too short (${body.length}, need 6)',
          );
        }
        final header = body.buffer.asByteData(body.offsetInBytes, 6);
        return TransferChunk(
          seq: header.getUint16(0, Endian.little),
          totalLen: header.getUint32(2, Endian.little),
          data: body.sublist(6),
        );
```

- [ ] **Step 5: Run, verify it passes**

Run: `cd bluey/example && flutter test test/shared/stress_protocol_test.dart`
Expected: PASS (all groups).

- [ ] **Step 6: Commit**

```bash
cd /Users/joel/git/neutrinographics/bluey
git add bluey/example/lib/shared/stress_protocol.dart bluey/example/test/shared/stress_protocol_test.dart
git commit -m "feat(example): add TransferChunk stress command for chunked transfers (I344)"
```

---

## Task 2: Server-side reassembly

**Files:**
- Modify: `bluey/example/lib/features/server/infrastructure/stress_service_handler.dart`
- Test: `bluey/example/test/server/infrastructure/stress_service_handler_test.dart`

- [ ] **Step 1: Write the failing tests**

Append these two groups inside `main()` in `bluey/example/test/server/infrastructure/stress_service_handler_test.dart`, immediately before the final closing `}` of `main()` (after the `Reset` group's closing `});`):

```dart
  group('StressServiceHandler — TransferChunk reassembly', () {
    WriteRequest chunkWrite(StressServiceHandler _, TransferChunk chunk) =>
        WriteRequest(
          client: mockClient,
          characteristicId: UUID(StressProtocol.charUuid),
          value: chunk.encode(),
          responseNeeded: true,
          offset: 0,
          internalRequestId: 0,
        );

    test('reassembles ordered fragments into the original payload', () async {
      final handler = StressServiceHandler();
      // Logical payload of 10 bytes split into [0..3], [4..6], [7..9].
      final full = Uint8List.fromList(
        List<int>.generate(10, (i) => i & 0xff),
      );
      await handler.onWrite(
        chunkWrite(
          handler,
          TransferChunk(seq: 0, totalLen: 10, data: full.sublist(0, 4)),
        ),
        mockServer,
      );
      await handler.onWrite(
        chunkWrite(
          handler,
          TransferChunk(seq: 1, totalLen: 10, data: full.sublist(4, 7)),
        ),
        mockServer,
      );
      await handler.onWrite(
        chunkWrite(
          handler,
          TransferChunk(seq: 2, totalLen: 10, data: full.sublist(7, 10)),
        ),
        mockServer,
      );

      expect(handler.onRead(), equals(full));
    });

    test('seq 0 resets the buffer, discarding a prior partial transfer', () async {
      final handler = StressServiceHandler();
      // Start a transfer, then abandon it with a fresh seq-0 fragment.
      await handler.onWrite(
        chunkWrite(
          handler,
          TransferChunk(
            seq: 0,
            totalLen: 10,
            data: Uint8List.fromList([0xDE, 0xAD]),
          ),
        ),
        mockServer,
      );
      // New transfer of 3 bytes [0x00, 0x01, 0x02], single fragment.
      await handler.onWrite(
        chunkWrite(
          handler,
          TransferChunk(
            seq: 0,
            totalLen: 3,
            data: Uint8List.fromList([0x00, 0x01, 0x02]),
          ),
        ),
        mockServer,
      );

      expect(handler.onRead(), equals(Uint8List.fromList([0x00, 0x01, 0x02])));
    });

    test('a gap (out-of-order seq) yields a fault sentinel on read', () async {
      final handler = StressServiceHandler();
      await handler.onWrite(
        chunkWrite(
          handler,
          TransferChunk(
            seq: 0,
            totalLen: 6,
            data: Uint8List.fromList([0x00, 0x01, 0x02]),
          ),
        ),
        mockServer,
      );
      // Skip seq 1 — jump straight to seq 2. This is a gap.
      await handler.onWrite(
        chunkWrite(
          handler,
          TransferChunk(
            seq: 2,
            totalLen: 6,
            data: Uint8List.fromList([0x04, 0x05]),
          ),
        ),
        mockServer,
      );

      final read = handler.onRead();
      expect(read, equals(Uint8List.fromList([0xEE])));
    });

    test('TransferChunk honors responseNeeded', () async {
      final handler = StressServiceHandler();
      final ackWrite = WriteRequest(
        client: mockClient,
        characteristicId: UUID(StressProtocol.charUuid),
        value: TransferChunk(
          seq: 0,
          totalLen: 1,
          data: Uint8List.fromList([0x00]),
        ).encode(),
        responseNeeded: true,
        offset: 0,
        internalRequestId: 0,
      );
      await handler.onWrite(ackWrite, mockServer);
      verify(
        () =>
            mockServer.respondToWrite(any(), status: GattResponseStatus.success),
      ).called(1);
    });
  });

  group('StressServiceHandler — Reset clears reassembly', () {
    test('ResetCommand discards an in-progress transfer', () async {
      final handler = StressServiceHandler();

      WriteRequest writeOf(Uint8List value) => WriteRequest(
        client: mockClient,
        characteristicId: UUID(StressProtocol.charUuid),
        value: value,
        responseNeeded: true,
        offset: 0,
        internalRequestId: 0,
      );

      // Partial transfer: 1 of an expected 10 bytes.
      await handler.onWrite(
        writeOf(
          TransferChunk(
            seq: 0,
            totalLen: 10,
            data: Uint8List.fromList([0x00]),
          ).encode(),
        ),
        mockServer,
      );

      await handler.onWrite(writeOf(const ResetCommand().encode()), mockServer);

      // After reset, _lastEcho is empty so reads return the default
      // 20-byte pattern, not stale reassembly state.
      expect(handler.onRead(), hasLength(20));
    });
  });
```

- [ ] **Step 2: Run, verify it fails**

Run: `cd bluey/example && flutter test test/server/infrastructure/stress_service_handler_test.dart`
Expected: FAIL — the switch has no `TransferChunk` case (and the file won't compile because the sealed switch is non-exhaustive), and the `0xEE` fault sentinel doesn't exist.

- [ ] **Step 3: Add the reassembly fields**

In `bluey/example/lib/features/server/infrastructure/stress_service_handler.dart`, add the fields and the sentinel after the existing `bool _abortBurst = false;` line (line 19):

```dart
  // Reassembly state for chunked TransferChunk writes. Per-instance and
  // shared across centrals, like the other stress state.
  final BytesBuilder _reassembly = BytesBuilder();
  int _expectedTotalLen = 0;
  int _nextSeq = 0;
  bool _reassemblyFault = false;

  /// Returned on read after a reassembly fault (gap / out-of-order /
  /// overflow). A distinct 1-byte value so any non-trivial expected
  /// payload diverges from it immediately, failing the client's verdict.
  static final Uint8List _reassemblyFaultSentinel = Uint8List.fromList(
    <int>[0xEE],
  );
```

- [ ] **Step 4: Add the `TransferChunk` switch case**

In the `switch (cmd)` inside `onWrite`, add this case immediately before the `case ResetCommand():` line (after the `SetPayloadSizeCommand` case's body):

```dart
      case TransferChunk(:final seq, :final totalLen, :final data):
        if (seq == 0) {
          _reassembly.clear();
          _expectedTotalLen = totalLen;
          _nextSeq = 0;
          _reassemblyFault = false;
          _lastEcho = Uint8List(0);
        }
        if (_reassemblyFault || seq != _nextSeq) {
          // A fragment arrived out of order, after a gap, or after a
          // prior fault — the transfer is unrecoverable.
          _reassemblyFault = true;
          _lastEcho = _reassemblyFaultSentinel;
        } else {
          _reassembly.add(data);
          _nextSeq++;
          if (_reassembly.length > _expectedTotalLen) {
            _reassemblyFault = true;
            _lastEcho = _reassemblyFaultSentinel;
          } else if (_reassembly.length == _expectedTotalLen) {
            _lastEcho = _reassembly.toBytes();
          }
        }
        if (req.responseNeeded) {
          await server.respondToWrite(req, status: GattResponseStatus.success);
        }
```

- [ ] **Step 5: Clear reassembly in the `ResetCommand` case**

In the existing `case ResetCommand():`, add the reassembly resets. Change it from:

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

to:

```dart
      case ResetCommand():
        _lastEcho = Uint8List(0);
        _dropNextWrite = false;
        _payloadSize = 20;
        _abortBurst = true; // interrupts any in-flight burstMe loop
        _reassembly.clear();
        _expectedTotalLen = 0;
        _nextSeq = 0;
        _reassemblyFault = false;
        if (req.responseNeeded) {
          await server.respondToWrite(req, status: GattResponseStatus.success);
        }
```

- [ ] **Step 6: Run, verify it passes**

Run: `cd bluey/example && flutter test test/server/infrastructure/stress_service_handler_test.dart`
Expected: PASS (all groups, including the pre-existing ones).

- [ ] **Step 7: Commit**

```bash
cd /Users/joel/git/neutrinographics/bluey
git add bluey/example/lib/features/server/infrastructure/stress_service_handler.dart bluey/example/test/server/infrastructure/stress_service_handler_test.dart
git commit -m "feat(example): reassemble TransferChunk fragments server-side (I344)"
```

---

## Task 3: Pure `evaluateTransfer` verdict

**Files:**
- Create: `bluey/example/lib/features/stress_tests/domain/transfer_verdict.dart`
- Test: `bluey/example/test/stress_tests/domain/transfer_verdict_test.dart`

- [ ] **Step 1: Write the failing tests**

Create `bluey/example/test/stress_tests/domain/transfer_verdict_test.dart`:

```dart
import 'dart:typed_data';

import 'package:bluey_example/features/stress_tests/domain/transfer_verdict.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List pattern(int n) =>
    Uint8List.fromList(List<int>.generate(n, (i) => i & 0xff));

void main() {
  group('evaluateTransfer', () {
    test('exact match returns ok', () {
      final v = evaluateTransfer(expectedLen: 600, readBack: pattern(600));
      expect(v.ok, isTrue);
      expect(v.expectedLen, equals(600));
      expect(v.gotLen, equals(600));
    });

    test('truncated read-back diverges at the cut, with no gotByte', () {
      // Client expected 514 bytes; only 512 arrived (the I343 symptom).
      final v = evaluateTransfer(expectedLen: 514, readBack: pattern(512));
      expect(v.ok, isFalse);
      expect(v.firstDivergenceOffset, equals(512));
      expect(v.expectedByte, equals(512 & 0xff));
      expect(v.gotByte, isNull);
      expect(v.expectedLen, equals(514));
      expect(v.gotLen, equals(512));
    });

    test('a wrong byte mid-stream diverges at that offset', () {
      final corrupted = pattern(100);
      corrupted[42] = 0xFF; // pattern[42] would be 42
      final v = evaluateTransfer(expectedLen: 100, readBack: corrupted);
      expect(v.ok, isFalse);
      expect(v.firstDivergenceOffset, equals(42));
      expect(v.expectedByte, equals(42));
      expect(v.gotByte, equals(0xFF));
    });

    test('empty read-back against a non-empty expectation diverges at 0', () {
      final v = evaluateTransfer(expectedLen: 8, readBack: Uint8List(0));
      expect(v.ok, isFalse);
      expect(v.firstDivergenceOffset, equals(0));
      expect(v.expectedByte, equals(0));
      expect(v.gotByte, isNull);
      expect(v.gotLen, equals(0));
    });

    test('overrun (read-back longer) diverges at expectedLen, no expectedByte', () {
      final v = evaluateTransfer(expectedLen: 4, readBack: pattern(6));
      expect(v.ok, isFalse);
      expect(v.firstDivergenceOffset, equals(4));
      expect(v.expectedByte, isNull);
      expect(v.gotByte, equals(4 & 0xff));
      expect(v.gotLen, equals(6));
    });

    test('zero-length expectation with empty read-back is ok', () {
      final v = evaluateTransfer(expectedLen: 0, readBack: Uint8List(0));
      expect(v.ok, isTrue);
    });

    test('describe() summarizes a divergence as offset/bytes/lengths', () {
      final v = evaluateTransfer(expectedLen: 514, readBack: pattern(512));
      expect(
        v.describe(),
        equals('offset 512: expected 0x00 got -- (len 514 vs 512)'),
      );
    });
  });
}
```

- [ ] **Step 2: Run, verify it fails**

Run: `cd bluey/example && flutter test test/stress_tests/domain/transfer_verdict_test.dart`
Expected: FAIL — `transfer_verdict.dart` does not exist.

- [ ] **Step 3: Create the verdict + function**

Create `bluey/example/lib/features/stress_tests/domain/transfer_verdict.dart`:

```dart
import 'dart:typed_data';

/// Outcome of comparing a chunked transfer's reassembled read-back bytes
/// against the deterministic pattern (`byte[i] = i & 0xff`) the client
/// sent. Pure value object — no I/O, fully unit-testable.
class TransferVerdict {
  /// True when every byte matched and the lengths were equal.
  final bool ok;

  /// Offset of the first mismatch (a differing byte, or the truncation /
  /// overrun point when one side ran out first). Null when [ok].
  final int? firstDivergenceOffset;

  /// The pattern byte expected at [firstDivergenceOffset], or null when
  /// the read-back overran the expected length (nothing was expected
  /// there).
  final int? expectedByte;

  /// The byte actually present at [firstDivergenceOffset], or null when
  /// the read-back was truncated (nothing arrived there).
  final int? gotByte;

  /// The logical payload length the client sent.
  final int expectedLen;

  /// The length actually read back from the server.
  final int gotLen;

  const TransferVerdict._({
    required this.ok,
    required this.expectedLen,
    required this.gotLen,
    this.firstDivergenceOffset,
    this.expectedByte,
    this.gotByte,
  });

  factory TransferVerdict.ok({required int len}) =>
      TransferVerdict._(ok: true, expectedLen: len, gotLen: len);

  factory TransferVerdict.diverged({
    required int offset,
    required int? expectedByte,
    required int? gotByte,
    required int expectedLen,
    required int gotLen,
  }) => TransferVerdict._(
    ok: false,
    firstDivergenceOffset: offset,
    expectedByte: expectedByte,
    gotByte: gotByte,
    expectedLen: expectedLen,
    gotLen: gotLen,
  );

  /// Human-readable one-liner for the result panel / failure messages.
  String describe() {
    if (ok) return 'OK ($expectedLen bytes)';
    String hex(int? b) =>
        b == null ? '--' : '0x${b.toRadixString(16).padLeft(2, '0')}';
    return 'offset $firstDivergenceOffset: expected ${hex(expectedByte)} '
        'got ${hex(gotByte)} (len $expectedLen vs $gotLen)';
  }
}

/// Compares [readBack] against the deterministic pattern `byte[i] = i & 0xff`
/// of length [expectedLen]. Returns [TransferVerdict.ok] when every byte
/// matches and the lengths are equal; otherwise the first point of
/// divergence — a differing byte, or (if the bytes matched up to the
/// shorter length) the truncation / overrun offset.
TransferVerdict evaluateTransfer({
  required int expectedLen,
  required Uint8List readBack,
}) {
  final common = expectedLen < readBack.length ? expectedLen : readBack.length;
  for (var i = 0; i < common; i++) {
    final expected = i & 0xff;
    if (readBack[i] != expected) {
      return TransferVerdict.diverged(
        offset: i,
        expectedByte: expected,
        gotByte: readBack[i],
        expectedLen: expectedLen,
        gotLen: readBack.length,
      );
    }
  }
  if (readBack.length != expectedLen) {
    return TransferVerdict.diverged(
      offset: common,
      expectedByte: common < expectedLen ? (common & 0xff) : null,
      gotByte: common < readBack.length ? readBack[common] : null,
      expectedLen: expectedLen,
      gotLen: readBack.length,
    );
  }
  return TransferVerdict.ok(len: expectedLen);
}
```

- [ ] **Step 4: Run, verify it passes**

Run: `cd bluey/example && flutter test test/stress_tests/domain/transfer_verdict_test.dart`
Expected: PASS (all cases).

- [ ] **Step 5: Commit**

```bash
cd /Users/joel/git/neutrinographics/bluey
git add bluey/example/lib/features/stress_tests/domain/transfer_verdict.dart bluey/example/test/stress_tests/domain/transfer_verdict_test.dart
git commit -m "feat(example): add pure evaluateTransfer byte-exact verdict (I344)"
```

---

## Task 4: Rewrite the `runMtuProbe` round (chunked, both write types)

**Files:**
- Modify: `bluey/example/lib/features/stress_tests/infrastructure/stress_test_runner.dart`
- Test: `bluey/example/test/stress_tests/infrastructure/stress_test_runner_test.dart`

This round is driven by a real `Connection` (`maxWritePayload`, `write`, `read`). The existing runner test suite exercises other methods against the example's `FakeConnection`; this task changes behavior that only fully exercises on real hardware. So: keep the existing runner tests green (no regression), and rely on the pure `evaluateTransfer` unit tests (Task 3) plus the on-device dogfood (Task 5) for the new logic. Do **not** invent a fake that returns 514-then-512 — that would be testing the fake, not the stack.

- [ ] **Step 1: Add the `transfer_verdict` import**

In `bluey/example/lib/features/stress_tests/infrastructure/stress_test_runner.dart`, add this import alongside the existing `../domain/...` imports (after `import '../domain/stress_test_result.dart';`):

```dart
import '../domain/transfer_verdict.dart';
```

- [ ] **Step 2: Replace the SetPayloadSize block and the 3-round loop**

In `runMtuProbe`, replace this entire block (the `// Tell server to return payloadBytes-sized reads.` comment through the closing `}` of the `for (var i = 0; i < 3; i++)` loop — currently lines 403–444):

```dart
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
```

with:

```dart
    // Byte-exact chunked transfer, once per write type. withoutResponse
    // first — that is the path that silently truncated in I343. Each pass
    // sizes its chunks to the connection's real maxWritePayload (minus the
    // TransferChunk header), streams config.payloadBytes of deterministic
    // pattern, reads the reassembled buffer back, and byte-compares it.
    for (final withResponse in [false, true]) {
      final label = withResponse ? 'withResponse' : 'withoutResponse';
      final start = stopwatch.elapsedMicroseconds;
      try {
        final limit = await connection.maxWritePayload(
          withResponse: withResponse,
        );
        final chunkSize = limit.value;
        if (chunkSize <= TransferChunk.headerBytes) {
          throw StateError(
            '$label: maxWritePayload ($chunkSize) too small to frame a chunk',
          );
        }

        // Fresh transfer each pass: seq 0 resets the server buffer.
        final payload = _generatePattern(config.payloadBytes);
        await _sendChunked(
          stressChar,
          payload,
          chunkSize: chunkSize,
          withResponse: withResponse,
        );

        final readBack = await stressChar.read();
        final verdict = evaluateTransfer(
          expectedLen: config.payloadBytes,
          readBack: readBack,
        );
        if (!verdict.ok) {
          throw StateError('$label: ${verdict.describe()}');
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
```

- [ ] **Step 3: Add the `_sendChunked` helper**

In the same class, add this method immediately after `_resolveStressChar` (before the `static Uint8List _generatePattern(int size)` method near line 602):

```dart
  /// Streams [payload] to the stress characteristic as ordered
  /// [TransferChunk] fragments. Each on-wire write is sized to fit within
  /// [chunkSize] including the [TransferChunk.headerBytes] framing, so the
  /// data carried per fragment is `chunkSize - headerBytes`. Sends each
  /// fragment using [withResponse].
  Future<void> _sendChunked(
    RemoteCharacteristic stressChar,
    Uint8List payload, {
    required int chunkSize,
    required bool withResponse,
  }) async {
    final dataPerChunk = chunkSize - TransferChunk.headerBytes;
    final totalLen = payload.length;
    var seq = 0;
    for (var offset = 0; offset < totalLen; offset += dataPerChunk) {
      final end =
          (offset + dataPerChunk < totalLen) ? offset + dataPerChunk : totalLen;
      final fragment = Uint8List.sublistView(payload, offset, end);
      await stressChar.write(
        TransferChunk(seq: seq, totalLen: totalLen, data: fragment).encode(),
        withResponse: withResponse,
      );
      seq++;
    }
  }
```

Note: a zero-length `payload` sends no fragments, so the server's buffer is never reset for that pass — but `config.payloadBytes` defaults to 244 and the test is meaningless at 0, so this is acceptable. The `ResetCommand` at the top of `runMtuProbe` already zeroed the server state.

- [ ] **Step 4: Run the runner test suite — confirm no regression**

Run: `cd bluey/example && flutter test test/stress_tests/infrastructure/stress_test_runner_test.dart`
Expected: PASS. If any test asserted the old 3-cycle / SetPayloadSize behavior of `runMtuProbe` specifically, update it to expect the two-pass shape (2 transfer attempts), keeping the assertions about MTU-request success unchanged. (Read the failing test, match it to the new flow; do not weaken unrelated assertions.)

- [ ] **Step 5: Analyze**

Run: `cd bluey/example && flutter analyze`
Expected: no new issues. (`SetPayloadSizeCommand` is still used elsewhere — it remains a valid command; only this call site dropped it. If analyzer flags an unused import, remove only the now-unused symbol, not the whole `stress_protocol.dart` import which `TransferChunk`/`EchoCommand`/`ResetCommand` still need.)

- [ ] **Step 6: Commit**

```bash
cd /Users/joel/git/neutrinographics/bluey
git add bluey/example/lib/features/stress_tests/infrastructure/stress_test_runner.dart bluey/example/test/stress_tests/infrastructure/stress_test_runner_test.dart
git commit -m "feat(example): mtuProbe does byte-exact chunked transfer on both write types (I344)"
```

---

## Task 5: Help text, full verify, dogfood handoff

**Files:**
- Modify: `bluey/example/lib/features/stress_tests/presentation/widgets/stress_test_help_content.dart`

- [ ] **Step 1: Update the mtuProbe help content**

In `bluey/example/lib/features/stress_tests/presentation/widgets/stress_test_help_content.dart`, replace the `StressTest.mtuProbe => const StressTestHelpContent(...)` entry's `whatItDoes` and `readingResults` strings (currently lines 162–178) with:

```dart
      whatItDoes:
          'Requests requestedMtu as the ATT MTU (Android only — iOS '
          'auto-negotiates), then streams a payloadBytes-long '
          'deterministic pattern to the server in chunks sized to the '
          'connection\'s real max write payload, and reads the '
          'reassembled bytes back for an exact comparison. Runs the '
          'whole transfer twice: once write-without-response (the I343 '
          'path that silently truncated above 512 bytes) and once '
          'write-with-response.\n\n'
          'Set payloadBytes ABOVE the single-write limit (e.g. 600) to '
          'force multi-chunk fragmentation — that is the case I343 '
          'corrupted. requestedMtu is the value passed to the platform '
          'MTU request API; the negotiated result may be lower.',
      readingResults:
          'Each write type is one attempt (2 transfer attempts total, '
          'plus the MTU request on Android). SUCCEEDED means the bytes '
          'read back matched the pattern exactly, byte-for-byte.\n\n'
          'A failure reports the first divergence as '
          '"offset N: expected 0xNN got 0xMM (len A vs B)", labelled '
          'with the write type. A tail divergence on the '
          'withoutResponse pass is the I343 truncation signature — it '
          'should NOT occur with the 512-octet clamp in place.',
```

- [ ] **Step 2: Verify the help-content test still passes**

Run: `cd bluey/example && flutter test test/stress_tests/presentation/widgets/stress_test_help_sheet_test.dart`
Expected: PASS. (If a test asserts a specific old help substring for mtuProbe, update it to match the new copy.)

- [ ] **Step 3: Full example suite + analyze**

```bash
cd /Users/joel/git/neutrinographics/bluey/bluey/example && flutter test && flutter analyze
```
Expected: all green, analyze clean.

- [ ] **Step 4: Commit**

```bash
cd /Users/joel/git/neutrinographics/bluey
git add bluey/example/lib/features/stress_tests/presentation/widgets/stress_test_help_content.dart
git commit -m "docs(example): describe byte-exact chunked mtuProbe in help (I344)"
```

- [ ] **Step 5: On-device dogfood (manual gate — not automatable here)**

Two real devices required (iOS simulators have no Bluetooth). iPhone as central, Pixel as peripheral:
1. Run the example server on the Pixel; advertise the stress service.
2. On the iPhone, connect and open the stress-tests screen; select the MTU probe; set **PAYLOAD BYTES = 600**.
3. On `main` (512 clamp present): both passes PASS — read-back matches 600 bytes exactly.
4. Temporarily revert the I343 clamp (`bluey/lib/src/connection/value_objects/write_payload_limit.dart`: make `fromPlatform` return the raw value), rebuild, rerun: the **withoutResponse** pass FAILs with a tail/length divergence (proves the guard bites). Restore the clamp afterward.

Record the outcome in `docs/backlog/I344-write-integrity-stress-test.md` (and flip it to `status: fixed` / done once the on-device run confirms both directions).

---

## Self-Review

**Spec coverage:**
- Extend `mtuProbe` (not a new variant) → Task 4. ✅
- `TransferChunk` opcode 0x07, wire `[0x07][seq u16 LE][totalLen u32 LE][data…]` → Task 1. ✅
- Server reassembly: seq-0 reset, in-order append, gap/overflow fault → sentinel, completion sets `_lastEcho` → Task 2. ✅
- `ResetCommand` clears reassembly → Task 2 Step 5. ✅
- Pure `evaluateTransfer({required int expectedLen, required Uint8List readBack}) → TransferVerdict` (ok | divergence detail) → Task 3. ✅
- Chunk sizing from real `maxWritePayload` (header-adjusted), both write types, read-back, byte-compare → Task 4. ✅
- Result surfacing via existing `recordSuccess`/`recordFailure` + divergence detail in the failure `typeName`/message → Task 4 (uses `StateError('label: ...describe()')`). ✅
- Unit tests for verdict + TransferChunk encode/decode + reassembly → Tasks 1–3. ✅
- On-device guard (PASS on main, FAIL un-clamped) → Task 5 Step 5. ✅
- No bluey-library changes (example-app only) → every task touches only `bluey/example/`. ✅

**Placeholder scan:** every code step shows complete code; every run step states expected output; no TBD/"handle edge cases". ✅

**Type consistency:**
- `TransferChunk({required int seq, required int totalLen, required Uint8List data})`, `TransferChunk.headerBytes` (int const = 7) — defined Task 1, used Tasks 2/4. ✅
- `evaluateTransfer({required int expectedLen, required Uint8List readBack}) → TransferVerdict`; `TransferVerdict.ok`/`.describe()`/`.firstDivergenceOffset`/`.expectedByte`/`.gotByte`/`.expectedLen`/`.gotLen` — defined Task 3, used Tasks 3/4. ✅
- `Connection.maxWritePayload({required bool withResponse}) → Future<WritePayloadLimit>`, `.value` (int) — matches `bluey_connection.dart:731`. ✅
- `RemoteCharacteristic.write(Uint8List, {required bool withResponse})` / `.read() → Future<Uint8List>` — matches existing runner call sites. ✅
- `_sendChunked(RemoteCharacteristic, Uint8List, {required int chunkSize, required bool withResponse})` — defined and called in Task 4. ✅
- `BytesBuilder` `.add` / `.length` / `.clear` / `.toBytes()` — standard `dart:typed_data`. ✅
