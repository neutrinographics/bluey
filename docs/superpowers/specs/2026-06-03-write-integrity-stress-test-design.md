# Write-integrity stress test — chunked, both write types, byte-exact (I344)

- **Date:** 2026-06-03
- **Status:** Approved (design)
- **Backlog:** [I344](../../../docs/backlog/I344-write-integrity-stress-test.md)
- **Guards:** [I343](../../../docs/backlog/I343-ios-to-android-multi-chunk-writenoresponse-loses-2-bytes-per-frame.md) (max-write truncation, fixed by the 512-octet clamp)

## Purpose

A repeatable on-device regression guard proving that a central writes **byte-exact**
to a peripheral — especially at / above `maxWritePayload`, the size that silently
truncated in I343. It must reproduce the real-world failure (a logical payload
larger than one write, **chunked** by the consumer) and verify the reassembled
bytes match exactly, on **both** write types.

This is example-app test tooling (the `stress_tests` feature), not a bluey-library
change.

## Decision: extend the existing `mtuProbe` stress test

`mtuProbe` ("MTU negotiation and large-payload writes") already has the
scaffolding: the `requestedMtu` + `payloadBytes` config, the
`requestMtu → write → read-back → verify` round, and the result panel. We extend
it rather than add a new variant — it is the semantically correct home.

### What changes in `mtuProbe` (`stress_test_runner.dart`)

Replace the single-write round with a **chunked byte-exact transfer**, run for
**both write types**:

1. (Android-central only, unchanged) `requestMtu(config.requestedMtu)`.
2. Query the real limit: `chunk = await connection.maxWritePayload(withResponse: …)`.
   `config.payloadBytes` is the **logical** transfer size and may exceed `chunk`
   (e.g. 600) — that is the point.
3. Generate a deterministic payload of `payloadBytes` (`byte[i] = i & 0xff`).
4. **Chunk** it into writes sized so each on-wire `TransferData` write (data +
   1-byte opcode) lands exactly at `chunk`; send each in order using the
   round's write type.
5. **Read back** the server's reassembled buffer **in windows** (see below):
   loop `ReadWindowCommand(offset, window)` → `stressChar.read()` → append,
   until `payloadBytes` bytes are retrieved (or a short slice signals the
   server has fewer — itself a truncation signal). A single `read()` cannot
   return more than the 512-octet attribute cap, so a >512 payload **must** be
   pulled back in slices.
6. **Byte-compare** the stitched read-back vs the regenerated pattern → verdict.
7. Run steps 2–6 **twice**: once `withResponse: false` (the I343 path), once
   `withResponse: true` (settles the unverified "with-response is capped at 512"
   question empirically). Record each as its own labelled outcome — on failure,
   record `verdict.describe()` so the divergence is visible in the result panel
   (not a bare `StateError`).

#### Read-back must be chunked too (post-dogfood correction)

The first on-device run (iPhone↔Pixel, `payloadBytes = 600`, both directions)
failed *symmetrically* with two opaque `StateError`s. Root cause: a single
characteristic `read()` cannot return more than the **512-octet maximum
attribute-value length** (the same cap I343 is about), so reading a 600-byte
reassembled buffer back as one value is impossible — the verdict failed on
length regardless of write integrity. A symmetric failure (not the asymmetric
signature of a real I343 truncation) is the tell. The fix: chunk the *reads*
the way we chunk the writes.

- **`ReadWindowCommand(offset u32, len u16)`** (next free opcode `0x08`): sets
  the server's read cursor; the next `read()` returns `buffer[offset :
  offset+len]` (clamped to the buffer end; empty when `offset >= length`).
- **Window size** = **`maxAttributeValueLength`** (512), the existing I343
  domain constant (public via `package:bluey/bluey.dart`). This is the *correct*
  ubiquitous-language term: the same 512-octet attribute-value cap that bounds a
  single read is what makes the windowing necessary in the first place — one
  concept, used consistently. **Not** `maxWritePayload` (a write concept doing a
  read's job — a UL smell), and **not** a new `maxReadPayload` (a fictitious
  concept — the read/write asymmetry is real: an app must size *writes* but the
  platform long-reads and reassembles *reads* transparently up to the 512 cap,
  so there is no consumer-facing read-size limit to name).
- **The read loop advances by the bytes actually returned**, stopping only on an
  empty slice (server has no more — the truncation signal) or once
  `payloadBytes` is gathered. It never assumes a read returned the full window,
  so it is robust to however the platform sizes read PDUs — no MTU-derived
  window needed.
- To actually **trigger I343** you also need a **high MTU (~517)** so a single
  *write* chunk reaches 513–514; at `requestedMtu = 247` (`maxWritePayload ≈
  244`) the over-report cannot occur. With chunked reads in place,
  `payloadBytes = 600` is correct again *when paired with a high MTU*.

### Protocol: one new command + server reassembly (`stress_protocol.dart` + `stress_service_handler.dart`)

Add `TransferData` (next free opcode `0x07`):
- Wire: `[0x07][data…]` — a single 1-byte opcode of framing overhead, like
  every other stress command.
- Server (`StressServiceHandler`): maintains a per-instance reassembly buffer.
  - Each `TransferData` write appends `data` to the buffer in arrival order.
    BLE preserves write ordering on a single characteristic within a
    connection (and I339 fixed WriteNoResponse flow control), so no `seq` is
    needed.
  - `read` returns the buffer window set by the last `ReadWindowCommand`
    (default: the whole buffer), taking precedence over `_lastEcho`.
- `ReadWindowCommand(offset, len)` (opcode `0x08`) sets the read window so the
  client can pull a >512 buffer back in ≤512 slices.
- `ResetCommand` clears the reassembly buffer **and** resets the read window at
  the start of each pass.

No `seq` / `totalLen` framing is carried: write ordering plus the client's
byte-exact compare detect any dropped or truncated fragment. (The earlier
draft's per-chunk `seq`+`totalLen` header was redundant with the byte-exact
verdict — dropped to keep the on-wire write at exactly `maxWritePayload` with
the minimum 1-byte opcode.)

Chunks are WriteNoResponse-capable: `onWrite` already handles `responseNeeded
== false`. The control/read-back path (`read`) is reliable, so only the
chunked-write leg under test uses the configured write type.

### Verdict: pure, unit-testable

A pure function `evaluateTransfer({required int expectedLen, required Uint8List readBack})`
→ `TransferVerdict` (`ok` | `{firstDivergenceOffset, expectedByte, gotByte, expectedLen, gotLen}`).
A truncated max-size chunk → read-back is short → first-divergence at the
truncation point → FAIL. The BLE round-trip is the only on-device part; the
verdict is plain Dart.

### Result surfacing

Reuse the existing stress result model/panel: per-pass success/failure +, on
failure, the divergence detail (`offset N: expected 0xNN got 0xMM, len A vs B`)
and the write type. The MTU-probe round currently records 3 cycles; keep that
shape (e.g. cycles × {withResponse, withoutResponse}).

## Testing

- **Unit tests** (`bluey/example/.../stress_tests/.../*_test.dart` style, or the
  example's existing test dir) for:
  - `evaluateTransfer`: exact match → ok; truncated (short readBack) → divergence
    at the cut; wrong byte mid-stream → divergence offset; empty → handled.
  - `TransferChunk` encode/decode round-trips; server reassembly across N chunks
    yields the original; out-of-order/gap → fault.
- **On-device**: run the extended `mtuProbe` (iPhone central ↔ Pixel peripheral)
  with `payloadBytes` set above `maxWritePayload` (e.g. 600) → PASS on `main`
  (the 512 clamp is in); temporarily un-clamp `WritePayloadLimit` → the
  WriteNoResponse pass FAILs with a tail divergence (proves the guard bites).

## Out of scope

- No bluey-library changes (example-app tooling only).
- No automatic CI hook — it needs two real devices; it's a manual dogfood guard.
- The drop-vs-coalesce *classification* from the original I344 sketch is dropped
  (the cause is known; byte-exact compare is sufficient).

## Implementation footprint

- `bluey/example/lib/shared/stress_protocol.dart` — `TransferData` command (0x07).
- `bluey/example/lib/features/server/infrastructure/stress_service_handler.dart` —
  reassembly buffer + `TransferData` case + read-precedence + reset extension.
- `bluey/example/lib/features/stress_tests/infrastructure/stress_test_runner.dart` —
  rewrite the `mtuProbe` round: chunked transfer, both write types, byte-exact
  verify via `evaluateTransfer`.
- `bluey/example/lib/features/stress_tests/.../` — the pure `evaluateTransfer`
  + `TransferVerdict` (new small file) and its unit tests.
- `bluey/example/lib/features/stress_tests/.../stress_test_help_content.dart` —
  update the `mtuProbe` help text to describe the byte-exact chunked check.
