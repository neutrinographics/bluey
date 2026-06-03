# Write-Integrity Stress Test (I344) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the example app's `mtuProbe` stress test into a chunked, byte-exact, both-write-types transfer-integrity check that reproduces (and guards against a regression of) the I343 silent-truncation bug.

**Architecture:** Add one minimal wire command — `TransferData` (opcode `0x07`, layout `[0x07][data…]`, 1-byte overhead like every other stress command). The server appends each `TransferData` fragment to a reassembly buffer (BLE preserves write order on a single characteristic) and returns it on read; `ResetCommand` clears it. The client chunks a deterministic pattern (`byte[i] = i & 0xff`), sized so each on-wire write lands exactly at the connection's real `maxWritePayload`, sends each fragment in the round's write type, reads the reassembled buffer back, and byte-compares it via a pure, unit-tested `evaluateTransfer` verdict. The round runs once `withoutResponse` (the I343 path) and once `withResponse`. No `seq` / `totalLen` framing is needed — write ordering plus the byte-exact compare detect any drop or truncation. All of this is example-app test tooling — **no bluey-library changes**.

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

- **Modify** `bluey/example/lib/shared/stress_protocol.dart` — add the `TransferData` command (opcode `0x07`, `headerBytes = 1`) + its `case 0x07` in the `decode` dispatcher.
- **Modify** `bluey/example/test/shared/stress_protocol_test.dart` — encode/decode/equality tests for `TransferData`.
- **Modify** `bluey/example/lib/features/server/infrastructure/stress_service_handler.dart` — per-instance reassembly buffer, `TransferData` switch case, read-precedence, and buffer clearing in the `ResetCommand` case.
- **Modify** `bluey/example/test/server/infrastructure/stress_service_handler_test.dart` — reassembly tests (happy path, ResetCommand clears, responseNeeded).
- **Create** `bluey/example/lib/features/stress_tests/domain/transfer_verdict.dart` — pure `TransferVerdict` value object + `evaluateTransfer(...)` function.
- **Create** `bluey/example/test/stress_tests/domain/transfer_verdict_test.dart` — verdict unit tests.
- **Modify** `bluey/example/lib/features/stress_tests/infrastructure/stress_test_runner.dart` — rewrite the `runMtuProbe` round: reset per pass, query `maxWritePayload`, chunk, send both write types, read back, verify via `evaluateTransfer`; add a private `_sendChunked` helper.
- **Modify** `bluey/example/lib/features/stress_tests/presentation/widgets/stress_test_help_content.dart` — update the `mtuProbe` help text to describe the byte-exact chunked check.

No config-form or enum changes are needed: `MtuProbeConfig` already exposes `payloadBytes` as a free-form int field (the `_intField` has no upper cap, so values like `600` are already enterable), and the runner method signature `runMtuProbe(MtuProbeConfig, Connection)` is unchanged.

---

## Task 1: `TransferData` command (opcode 0x07)

**Files:**
- Modify: `bluey/example/lib/shared/stress_protocol.dart`
- Test: `bluey/example/test/shared/stress_protocol_test.dart`

- [ ] **Step 1: Write the failing tests**

Append this group inside `main()` in `bluey/example/test/shared/stress_protocol_test.dart`, immediately before the final closing `}` of `main()` (i.e. after the `ResetCommand` group's closing `});`):

```dart
  group('TransferData', () {
    test('headerBytes is 1 (just the opcode)', () {
      expect(TransferData.headerBytes, equals(1));
    });

    test('encode prepends opcode 0x07 to the data', () {
      final cmd = TransferData(Uint8List.fromList([0xAA, 0xBB, 0xCC]));
      expect(
        cmd.encode(),
        equals(Uint8List.fromList([0x07, 0xAA, 0xBB, 0xCC])),
      );
    });

    test('encode handles an empty data fragment', () {
      final cmd = TransferData(Uint8List(0));
      expect(cmd.encode(), equals(Uint8List.fromList([0x07])));
    });

    test('decode round-trips the data bytes', () {
      final original = TransferData(Uint8List.fromList([1, 2, 3, 4, 5]));
      final decoded = StressCommand.decode(original.encode());
      expect(decoded, isA<TransferData>());
      expect(
        (decoded as TransferData).data,
        equals(Uint8List.fromList([1, 2, 3, 4, 5])),
      );
    });

    test('TransferData instances with equal data are equal', () {
      expect(
        TransferData(Uint8List.fromList([7, 8, 9])),
        equals(TransferData(Uint8List.fromList([7, 8, 9]))),
      );
    });

    test('TransferData defensively copies its data', () {
      final mutable = Uint8List.fromList([1, 2, 3]);
      final cmd = TransferData(mutable);
      mutable[0] = 99;
      expect(cmd.data[0], equals(1));
    });
  });
```

- [ ] **Step 2: Run, verify it fails**

Run: `cd bluey/example && flutter test test/shared/stress_protocol_test.dart`
Expected: FAIL — `TransferData` is undefined and `decode` has no `0x07` case.

- [ ] **Step 3: Add the `TransferData` class**

In `bluey/example/lib/shared/stress_protocol.dart`, add this class after the `ResetCommand` class (after its closing `}` near line 217, before the `StressProtocolException` class):

```dart
/// TransferData: one fragment of a larger logical payload the client is
/// streaming to the server for byte-exact reassembly. The server appends
/// [data] to a reassembly buffer in arrival order (BLE preserves write
/// order on a single characteristic within a connection), and the buffer
/// becomes the value returned by the next read. Opcode 0x07.
///
/// Wire layout: `[0x07][data…]`. The 1-byte opcode ([headerBytes]) is the
/// only framing overhead; subtract it from the connection's max write
/// payload when sizing a fragment so each framed write fits in one ATT
/// packet. No sequence number or total length is carried — write ordering
/// plus the client's byte-exact compare detect any dropped or truncated
/// fragment.
class TransferData extends StressCommand {
  /// Framing overhead per fragment: just the 1-byte opcode.
  static const int headerBytes = 1;

  /// This fragment's bytes.
  final Uint8List data;

  TransferData(Uint8List data) : data = Uint8List.fromList(data);

  @override
  Uint8List encode() {
    final out = Uint8List(headerBytes + data.length);
    out[0] = 0x07;
    out.setRange(headerBytes, out.length, data);
    return out;
  }

  @override
  bool operator ==(Object other) =>
      other is TransferData &&
      const ListEquality<int>().equals(other.data, data);

  @override
  int get hashCode => Object.hashAll(data);
}
```

- [ ] **Step 4: Add the `decode` case**

In the same file, in `StressCommand.decode`, add a `case 0x07` immediately before the `default:` case in the `switch (opcode)` (after the `case 0x06: return const ResetCommand();` line):

```dart
      case 0x07:
        return TransferData(body);
```

- [ ] **Step 5: Run, verify it passes**

Run: `cd bluey/example && flutter test test/shared/stress_protocol_test.dart`
Expected: PASS (all groups).

- [ ] **Step 6: Commit**

```bash
cd /Users/joel/git/neutrinographics/bluey
git add bluey/example/lib/shared/stress_protocol.dart bluey/example/test/shared/stress_protocol_test.dart
git commit -m "feat(example): add TransferData stress command for chunked transfers (I344)"
```

---

## Task 2: Server-side reassembly

**Files:**
- Modify: `bluey/example/lib/features/server/infrastructure/stress_service_handler.dart`
- Test: `bluey/example/test/server/infrastructure/stress_service_handler_test.dart`

- [ ] **Step 1: Write the failing tests**

Append these two groups inside `main()` in `bluey/example/test/server/infrastructure/stress_service_handler_test.dart`, immediately before the final closing `}` of `main()` (after the `Reset` group's closing `});`):

```dart
  group('StressServiceHandler — TransferData reassembly', () {
    WriteRequest dataWrite(Uint8List data) => WriteRequest(
      client: mockClient,
      characteristicId: UUID(StressProtocol.charUuid),
      value: TransferData(data).encode(),
      responseNeeded: true,
      offset: 0,
      internalRequestId: 0,
    );

    test('appends fragments in order and reads back the whole payload', () async {
      final handler = StressServiceHandler();
      final full = Uint8List.fromList(List<int>.generate(10, (i) => i & 0xff));

      await handler.onWrite(dataWrite(full.sublist(0, 4)), mockServer);
      await handler.onWrite(dataWrite(full.sublist(4, 7)), mockServer);
      await handler.onWrite(dataWrite(full.sublist(7, 10)), mockServer);

      expect(handler.onRead(), equals(full));
    });

    test('the reassembly buffer takes precedence over a prior echo', () async {
      final handler = StressServiceHandler();
      // Prior echo sets _lastEcho.
      await handler.onWrite(
        WriteRequest(
          client: mockClient,
          characteristicId: UUID(StressProtocol.charUuid),
          value: EchoCommand(Uint8List.fromList([0xDE, 0xAD])).encode(),
          responseNeeded: true,
          offset: 0,
          internalRequestId: 0,
        ),
        mockServer,
      );
      // A transfer fragment now shadows it.
      await handler.onWrite(dataWrite(Uint8List.fromList([0x01, 0x02])), mockServer);

      expect(handler.onRead(), equals(Uint8List.fromList([0x01, 0x02])));
    });

    test('TransferData honors responseNeeded', () async {
      final handler = StressServiceHandler();
      await handler.onWrite(dataWrite(Uint8List.fromList([0x00])), mockServer);
      verify(
        () =>
            mockServer.respondToWrite(any(), status: GattResponseStatus.success),
      ).called(1);
    });
  });

  group('StressServiceHandler — Reset clears reassembly', () {
    test('ResetCommand discards the transfer buffer', () async {
      final handler = StressServiceHandler();

      WriteRequest writeOf(Uint8List value) => WriteRequest(
        client: mockClient,
        characteristicId: UUID(StressProtocol.charUuid),
        value: value,
        responseNeeded: true,
        offset: 0,
        internalRequestId: 0,
      );

      // Accumulate some transfer data.
      await handler.onWrite(
        writeOf(TransferData(Uint8List.fromList([0x00, 0x01])).encode()),
        mockServer,
      );

      await handler.onWrite(writeOf(const ResetCommand().encode()), mockServer);

      // After reset the buffer is empty, so reads fall back to the default
      // 20-byte pattern rather than stale transfer state.
      expect(handler.onRead(), hasLength(20));
    });
  });
```

- [ ] **Step 2: Run, verify it fails**

Run: `cd bluey/example && flutter test test/server/infrastructure/stress_service_handler_test.dart`
Expected: FAIL — the switch has no `TransferData` case (the file won't compile, because the sealed switch becomes non-exhaustive once `TransferData` exists), and `onRead` has no buffer-precedence path.

- [ ] **Step 3: Add the reassembly buffer field**

In `bluey/example/lib/features/server/infrastructure/stress_service_handler.dart`, add the field after the existing `bool _abortBurst = false;` line (line 19):

```dart
  // Reassembly buffer for chunked TransferData writes. Per-instance and
  // shared across centrals, like the other stress state. Cleared by
  // ResetCommand. Takes precedence over _lastEcho on read so a transfer
  // round reads back exactly what was streamed.
  final BytesBuilder _transfer = BytesBuilder();
```

- [ ] **Step 4: Add the `TransferData` switch case**

In the `switch (cmd)` inside `onWrite`, add this case immediately before the `case ResetCommand():` line (after the `SetPayloadSizeCommand` case's body):

```dart
      case TransferData(:final data):
        _transfer.add(data);
        if (req.responseNeeded) {
          await server.respondToWrite(req, status: GattResponseStatus.success);
        }
```

- [ ] **Step 5: Clear the buffer in the `ResetCommand` case**

In the existing `case ResetCommand():`, add the buffer reset. Change it from:

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
        _transfer.clear();
        if (req.responseNeeded) {
          await server.respondToWrite(req, status: GattResponseStatus.success);
        }
```

- [ ] **Step 6: Give the reassembly buffer read precedence**

Change `onRead` from:

```dart
  Uint8List onRead() {
    if (_lastEcho.isNotEmpty) return _lastEcho;
    return _generatePattern(_payloadSize);
  }
```

to:

```dart
  Uint8List onRead() {
    if (_transfer.length > 0) return _transfer.toBytes();
    if (_lastEcho.isNotEmpty) return _lastEcho;
    return _generatePattern(_payloadSize);
  }
```

(`BytesBuilder.toBytes()` returns a copy and does not clear the builder, so repeated reads are stable.)

- [ ] **Step 7: Run, verify it passes**

Run: `cd bluey/example && flutter test test/server/infrastructure/stress_service_handler_test.dart`
Expected: PASS (all groups, including the pre-existing ones).

- [ ] **Step 8: Commit**

```bash
cd /Users/joel/git/neutrinographics/bluey
git add bluey/example/lib/features/server/infrastructure/stress_service_handler.dart bluey/example/test/server/infrastructure/stress_service_handler_test.dart
git commit -m "feat(example): reassemble TransferData fragments server-side (I344)"
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
    // resets the server buffer, sizes its chunks to the connection's real
    // maxWritePayload (minus the 1-byte TransferData opcode), streams
    // config.payloadBytes of deterministic pattern, reads the reassembled
    // buffer back, and byte-compares it.
    for (final withResponse in [false, true]) {
      final label = withResponse ? 'withResponse' : 'withoutResponse';
      final start = stopwatch.elapsedMicroseconds;
      try {
        // Fresh server buffer for this pass.
        await stressChar.write(
          const ResetCommand().encode(),
          withResponse: true,
        );

        final limit = await connection.maxWritePayload(
          withResponse: withResponse,
        );
        final chunkSize = limit.value;
        if (chunkSize <= TransferData.headerBytes) {
          throw StateError(
            '$label: maxWritePayload ($chunkSize) too small to frame a chunk',
          );
        }

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
  /// [TransferData] fragments. Each on-wire write is sized to fit within
  /// [chunkSize] including the 1-byte [TransferData.headerBytes] opcode, so
  /// the data carried per fragment is `chunkSize - headerBytes` and the
  /// framed write lands exactly at [chunkSize]. Sends each fragment using
  /// [withResponse].
  Future<void> _sendChunked(
    RemoteCharacteristic stressChar,
    Uint8List payload, {
    required int chunkSize,
    required bool withResponse,
  }) async {
    final dataPerChunk = chunkSize - TransferData.headerBytes;
    final totalLen = payload.length;
    for (var offset = 0; offset < totalLen; offset += dataPerChunk) {
      final end =
          (offset + dataPerChunk < totalLen) ? offset + dataPerChunk : totalLen;
      final fragment = Uint8List.sublistView(payload, offset, end);
      await stressChar.write(
        TransferData(fragment).encode(),
        withResponse: withResponse,
      );
    }
  }
```

- [ ] **Step 4: Run the runner test suite — confirm no regression**

Run: `cd bluey/example && flutter test test/stress_tests/infrastructure/stress_test_runner_test.dart`
Expected: PASS. If any test asserted the old 3-cycle / SetPayloadSize behavior of `runMtuProbe` specifically, update it to expect the two-pass shape (2 transfer attempts), keeping the assertions about MTU-request success unchanged. (Read the failing test, match it to the new flow; do not weaken unrelated assertions.)

- [ ] **Step 5: Analyze**

Run: `cd bluey/example && flutter analyze`
Expected: no new issues. (`SetPayloadSizeCommand` is still used elsewhere — it remains a valid command; only this call site dropped it. If the analyzer flags an unused import, remove only the now-unused symbol, not the whole `stress_protocol.dart` import which `TransferData`/`EchoCommand`/`ResetCommand` still need.)

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
- One chunked-transfer command (the spec's `TransferChunk`, here simplified to `TransferData` — `seq`/`totalLen` dropped because write ordering + byte-exact compare make them redundant; see the "design call" discussion) → Task 1. ✅
- Server reassembly: append in arrival order, read-back, ResetCommand clears → Task 2. ✅
- Pure `evaluateTransfer({required int expectedLen, required Uint8List readBack}) → TransferVerdict` (ok | divergence detail) → Task 3. ✅
- Chunk sizing from real `maxWritePayload` (opcode-adjusted so the on-wire write lands exactly at the cap), both write types, read-back, byte-compare → Task 4. ✅
- Result surfacing via existing `recordSuccess`/`recordFailure` + divergence detail in the failure message → Task 4 (`StateError('label: ...describe()')`). ✅
- Unit tests for verdict + TransferData encode/decode + reassembly → Tasks 1–3. ✅
- On-device guard (PASS on main, FAIL un-clamped) → Task 5 Step 5. ✅
- No bluey-library changes (example-app only) → every task touches only `bluey/example/`. ✅

**Placeholder scan:** every code step shows complete code; every run step states expected output; no TBD/"handle edge cases". ✅

**Type consistency:**
- `TransferData(Uint8List data)`, `TransferData.headerBytes` (int const = 1), `.data` (Uint8List) — defined Task 1, used Tasks 2/4. ✅
- `evaluateTransfer({required int expectedLen, required Uint8List readBack}) → TransferVerdict`; `TransferVerdict.ok`/`.describe()`/`.firstDivergenceOffset`/`.expectedByte`/`.gotByte`/`.expectedLen`/`.gotLen` — defined Task 3, used Tasks 3/4. ✅
- `Connection.maxWritePayload({required bool withResponse}) → Future<WritePayloadLimit>`, `.value` (int) — matches `bluey_connection.dart:731`. ✅
- `RemoteCharacteristic.write(Uint8List, {required bool withResponse})` / `.read() → Future<Uint8List>` — matches existing runner call sites. ✅
- `_sendChunked(RemoteCharacteristic, Uint8List, {required int chunkSize, required bool withResponse})` — defined and called in Task 4. ✅
- `BytesBuilder` `.add` / `.length` / `.clear` / `.toBytes()` — standard `dart:typed_data`. ✅

---

# Revision: windowed reads (post-dogfood correction)

The first on-device run (iPhone↔Pixel, `payloadBytes = 600`, both directions)
failed *symmetrically* with two opaque `StateError`s. Root cause: a single
characteristic `read()` cannot return more than the **512-octet maximum
attribute-value length**, so reading a 600-byte reassembled buffer back as one
value is impossible — the verdict failed on length regardless of write
integrity. (Confirmed: `payloadBytes = 500` passes both directions; `600`
fails.) Fix: chunk the *reads* like the writes, surface the verdict detail, and
fix the MTU guidance. Tasks 1–3 stand; the byte-exact `evaluateTransfer`
(Task 3) is reused unchanged.

## Task R1: `ReadWindowCommand` (opcode 0x08)

**Files:**
- Modify: `bluey/example/lib/shared/stress_protocol.dart`
- Test: `bluey/example/test/shared/stress_protocol_test.dart`

- [ ] **Step 1: Failing tests** — append inside `main()` before its final `}`:

```dart
  group('ReadWindowCommand', () {
    test('encode is [0x08, offset u32 LE, len u16 LE]', () {
      const cmd = ReadWindowCommand(offset: 0x01020304, len: 0x0506);
      expect(
        cmd.encode(),
        equals(Uint8List.fromList([0x08, 0x04, 0x03, 0x02, 0x01, 0x06, 0x05])),
      );
    });

    test('decode round-trips offset and len', () {
      const original = ReadWindowCommand(offset: 600, len: 244);
      final decoded = StressCommand.decode(original.encode());
      expect(decoded, isA<ReadWindowCommand>());
      final c = decoded as ReadWindowCommand;
      expect(c.offset, equals(600));
      expect(c.len, equals(244));
    });

    test('decode throws when the body is shorter than 6 bytes', () {
      expect(
        () => StressCommand.decode(Uint8List.fromList([0x08, 0, 0, 0, 0])),
        throwsA(
          isA<StressProtocolException>().having((e) => e.opcode, 'opcode', 0x08),
        ),
      );
    });

    test('ReadWindowCommand instances with equal fields are equal', () {
      expect(
        const ReadWindowCommand(offset: 5, len: 9),
        equals(const ReadWindowCommand(offset: 5, len: 9)),
      );
    });
  });
```

- [ ] **Step 2: Run, verify it fails** — `cd bluey/example && flutter test test/shared/stress_protocol_test.dart` → FAIL.

- [ ] **Step 3: Add the class** — after `TransferData`, before `StressProtocolException`:

```dart
/// ReadWindowCommand: sets the server's read cursor so the client can pull a
/// reassembled buffer larger than the 512-octet attribute cap back in slices.
/// The next read returns `buffer[offset : offset+len]` (clamped to the buffer
/// end). Opcode 0x08. Wire: `[0x08][offset u32 LE][len u16 LE]`.
class ReadWindowCommand extends StressCommand {
  final int offset;
  final int len;
  const ReadWindowCommand({required this.offset, required this.len});

  @override
  Uint8List encode() {
    final out = Uint8List(7);
    out[0] = 0x08;
    final bd = out.buffer.asByteData();
    bd.setUint32(1, offset, Endian.little);
    bd.setUint16(5, len, Endian.little);
    return out;
  }

  @override
  bool operator ==(Object other) =>
      other is ReadWindowCommand && other.offset == offset && other.len == len;

  @override
  int get hashCode => Object.hash(offset, len);
}
```

- [ ] **Step 4: Add the decode case** — before `default:` in `switch (opcode)`:

```dart
      case 0x08:
        if (body.length < 6) {
          throw StressProtocolException(
            opcode: opcode,
            message: 'ReadWindow payload too short (${body.length}, need 6)',
          );
        }
        final bd = body.buffer.asByteData(body.offsetInBytes, 6);
        return ReadWindowCommand(
          offset: bd.getUint32(0, Endian.little),
          len: bd.getUint16(4, Endian.little),
        );
```

- [ ] **Step 5: Run green**, then commit `feat(example): add ReadWindowCommand for chunked read-back (I344)`.

## Task R2: server `onRead` honors the read window

**Files:**
- Modify: `bluey/example/lib/features/server/infrastructure/stress_service_handler.dart`
- Test: `bluey/example/test/server/infrastructure/stress_service_handler_test.dart`

- [ ] **Step 1: Failing tests** — append a group:

```dart
  group('StressServiceHandler — ReadWindow', () {
    WriteRequest writeOf(Uint8List value) => WriteRequest(
      client: mockClient,
      characteristicId: UUID(StressProtocol.charUuid),
      value: value,
      responseNeeded: true,
      offset: 0,
      internalRequestId: 0,
    );

    test('returns the requested slice of a reassembled buffer', () async {
      final handler = StressServiceHandler();
      final full = Uint8List.fromList(List<int>.generate(10, (i) => i & 0xff));
      await handler.onWrite(writeOf(TransferData(full).encode()), mockServer);

      await handler.onWrite(
        writeOf(const ReadWindowCommand(offset: 3, len: 4).encode()),
        mockServer,
      );
      expect(handler.onRead(), equals(Uint8List.fromList([3, 4, 5, 6])));
    });

    test('clamps a window past the buffer end and yields empty past it', () async {
      final handler = StressServiceHandler();
      final full = Uint8List.fromList(List<int>.generate(10, (i) => i & 0xff));
      await handler.onWrite(writeOf(TransferData(full).encode()), mockServer);

      await handler.onWrite(
        writeOf(const ReadWindowCommand(offset: 8, len: 100).encode()),
        mockServer,
      );
      expect(handler.onRead(), equals(Uint8List.fromList([8, 9])));

      await handler.onWrite(
        writeOf(const ReadWindowCommand(offset: 50, len: 4).encode()),
        mockServer,
      );
      expect(handler.onRead(), isEmpty);
    });

    test('ResetCommand restores the default full-buffer window', () async {
      final handler = StressServiceHandler();
      final full = Uint8List.fromList(List<int>.generate(10, (i) => i & 0xff));
      await handler.onWrite(writeOf(TransferData(full).encode()), mockServer);
      await handler.onWrite(
        writeOf(const ReadWindowCommand(offset: 5, len: 2).encode()),
        mockServer,
      );
      await handler.onWrite(writeOf(const ResetCommand().encode()), mockServer);

      // Window reset; a fresh transfer reads back whole.
      await handler.onWrite(writeOf(TransferData(full).encode()), mockServer);
      expect(handler.onRead(), equals(full));
    });
  });
```

- [ ] **Step 2: Run, verify it fails** (compile error: no `ReadWindowCommand` case).

- [ ] **Step 3: Add the window fields** — after the `_transfer` field. The
default window is `maxAttributeValueLength` (the I343 512-octet constant,
already imported via `package:bluey/bluey.dart`) — the spec cap that bounds any
single read, not a write concept:

```dart
  // Read cursor for windowed reads of the reassembly buffer (so a buffer larger
  // than the 512-octet attribute cap can be pulled back in slices). Defaults to
  // a full attribute-value-sized window; set by ReadWindowCommand, reset by
  // ResetCommand.
  int _readOffset = 0;
  int _readLen = maxAttributeValueLength;
```

- [ ] **Step 4: Add the `ReadWindowCommand` case** — before `case ResetCommand():`:

```dart
      case ReadWindowCommand(:final offset, :final len):
        _readOffset = offset;
        _readLen = len;
        if (req.responseNeeded) {
          await server.respondToWrite(req, status: GattResponseStatus.success);
        }
```

- [ ] **Step 5: Reset the window in `ResetCommand`** — add after `_transfer.clear();`:

```dart
        _readOffset = 0;
        _readLen = maxAttributeValueLength;
```

- [ ] **Step 6: Window the buffer in `onRead`** — change the `_transfer` branch:

```dart
  Uint8List onRead() {
    if (_transfer.length > 0) {
      final bytes = _transfer.toBytes();
      if (_readOffset >= bytes.length) return Uint8List(0);
      final end = (_readOffset + _readLen < bytes.length)
          ? _readOffset + _readLen
          : bytes.length;
      return Uint8List.sublistView(bytes, _readOffset, end);
    }
    if (_lastEcho.isNotEmpty) return _lastEcho;
    return _generatePattern(_payloadSize);
  }
```

(The pre-existing Task 2 reassembly tests read buffers ≤512 with the default
window, so they still return the whole buffer and stay green.)

- [ ] **Step 7: Run green**, then commit `feat(example): window the reassembly read-back server-side (I344)`.

## Task R3: runner windowed read-back loop + legible failures

**Files:**
- Modify: `bluey/example/lib/features/stress_tests/infrastructure/stress_test_runner.dart`
- Test: `bluey/example/test/stress_tests/infrastructure/stress_test_runner_test.dart`

- [ ] **Step 1:** In `runMtuProbe`, replace the read-back + verdict portion of each
pass (the `final readBack = await stressChar.read();` line through the
`if (!verdict.ok) { throw StateError(...); }` block) with:

```dart
        final readBack = await _readBackWindowed(
          stressChar,
          expectedLen: config.payloadBytes,
        );
        final verdict = evaluateTransfer(
          expectedLen: config.payloadBytes,
          readBack: readBack,
        );
        if (!verdict.ok) {
          // Record the divergence detail directly (not a bare StateError) so
          // the result panel shows what actually went wrong.
          result = result.recordFailure(
            typeName: 'TransferMismatch[$label]: ${verdict.describe()}',
          );
          yield result;
          continue;
        }
```

(The existing `result = result.recordSuccess(...)` that followed stays as the
success path; the existing `catch`/`yield result` at the end of the pass still
handle genuine exceptions. Ensure exactly one `yield result` per pass on each
path — the `continue` above yields then advances to the next write type.)

- [ ] **Step 2:** Add the helper after `_sendChunked`:

```dart
  /// Reads the server's reassembled buffer back in slices via [ReadWindowCommand]
  /// and stitches them, because a single characteristic read cannot return more
  /// than the 512-octet attribute cap ([maxAttributeValueLength]) — the same cap
  /// that necessitates the windowing. Advances by the bytes actually returned
  /// (never assuming a read delivered the full window), so it is robust to how
  /// the platform sizes read PDUs. Stops once [expectedLen] bytes are gathered,
  /// or when a slice comes back empty (the server has no more — itself the
  /// truncation signal the verdict then reports).
  Future<Uint8List> _readBackWindowed(
    RemoteCharacteristic stressChar, {
    required int expectedLen,
  }) async {
    final acc = BytesBuilder();
    var offset = 0;
    while (offset < expectedLen) {
      await stressChar.write(
        ReadWindowCommand(offset: offset, len: maxAttributeValueLength).encode(),
        withResponse: true,
      );
      final slice = await stressChar.read();
      if (slice.isEmpty) break;
      acc.add(slice);
      offset += slice.length;
    }
    return acc.toBytes();
  }
```

- [ ] **Step 3:** Update the `runMtuProbe` unit test's fake hooks to honor
`ReadWindowCommand`: the write hook decodes commands (already does for
`TransferData`/`ResetCommand`) and, on `ReadWindowCommand`, records `offset`/`len`;
the read hook returns the reassembly sliced to `[offset : offset + min(len,
pduCap)]` (clamped, empty past the end), where `pduCap` is a small fixed value
(e.g. `99`) that **simulates a single read PDU**. Capping the slice forces the
tolerant read loop to iterate (proving it advances by bytes-actually-returned,
not by the requested window). Set `payloadBytes = 250` so the buffer spans
multiple write chunks AND multiple read PDUs (250 → 99 + 99 + 52 → 3 reads).
Assertions stay `succeeded == 3`, `failed == 0`. Sanity: a fake that ignored
`offset` (always returning bytes from 0) would make the stitched read-back
diverge from the pattern, failing the verdict — so the assertion genuinely
exercises the windowed-read path.

- [ ] **Step 4:** `cd bluey/example && flutter test test/stress_tests/infrastructure/stress_test_runner_test.dart` green; `flutter analyze` clean. Commit `feat(example): chunked windowed read-back + legible verdict failures (I344)`.

## Task R4: MTU/payload guidance + full verify

**Files:**
- Modify: `bluey/example/lib/features/stress_tests/domain/stress_test_config.dart`
- Modify: `bluey/example/lib/features/stress_tests/presentation/widgets/stress_test_help_content.dart`

- [ ] **Step 1:** Change `MtuProbeConfig` defaults so the out-of-box probe can
actually exercise I343: `const MtuProbeConfig({this.requestedMtu = 517, this.payloadBytes = 600});`.

- [ ] **Step 2:** Update the mtuProbe help `whatItDoes`/`readingResults` to note:
request a **high MTU (~517)** so a single write chunk reaches 513–514 (Android
client can request it; iOS auto-negotiates and you can't set it); the read-back
is pulled in ≤512 windows; a *symmetric* failure usually means a test/param
issue, an *asymmetric* one (one direction only) is the real I343 signature.

- [ ] **Step 3:** `cd bluey/example && flutter test && flutter analyze` — all green/clean. Commit `docs(example): high-MTU guidance + windowed read-back help (I344)`.

- [ ] **Step 4 (manual):** Re-dogfood iPhone↔Pixel at MTU 517 / payload 600. Expect PASS both directions on `main`; revert the I343 clamp → the iOS→Android `withoutResponse` pass FAILs with a tail divergence (now visible in the panel).
