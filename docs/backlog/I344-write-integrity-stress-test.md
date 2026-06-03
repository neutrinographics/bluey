---
id: I344
title: Add a write-integrity stress test (sequenced WriteNoResponse + server-side tally) as a repeatable repro/regression harness for I339 / I343
category: enhancement
severity: low
platform: domain
status: done
fixed_in: e5ca4e7
last_verified: 2026-06-03
related: [I339, I343, I050]
---

> **Done (2026-06-03, merge `e5ca4e7`).** Built *after* the I343 root cause was
> localized (the 512-octet attribute-value cap; iOS over-reports the
> WriteNoResponse max as MTU−3). Implemented by **extending the existing
> `mtuProbe` stress test** rather than adding a new `writeIntegrity` variant.
> On-device dogfood confirmed PASS in both directions (iPhone↔Pixel) at
> MTU 517 / payload 600.
>
> **What shipped (diverges from the sketch below):** a byte-exact transfer
> integrity check, not a seq-tally. `TransferData` (opcode `0x07`) streams a
> deterministic pattern as chunked writes sized to `maxWritePayload`;
> `ReadWindowCommand` (opcode `0x08`) pulls the server's reassembled buffer back
> in ≤`maxAttributeValueLength` (512) windows — necessary because a single
> `read()` cannot exceed the 512-octet attribute cap; the pure, unit-tested
> `evaluateTransfer` byte-compares the stitched read-back against the pattern.
> Runs both write types (the `withoutResponse` pass is the I343 path). Failures
> surface as a legible `TransferMismatch[<label>]: offset N: expected … got …`.
> A *symmetric* failure indicates a param/test issue; the real I343 signature is
> *asymmetric*. Spec: `docs/superpowers/specs/2026-06-03-write-integrity-stress-test-design.md`;
> plan: `docs/superpowers/plans/2026-06-03-write-integrity-stress-test.md`.
>
> The original deferred sketch is preserved below for history.

> **(Historical) Deferred — gated on the I343 bisect.** Do **not** build this
> until the I343 root cause is localized. See
> [I343](I343-ios-to-android-multi-chunk-writenoresponse-loses-2-bytes-per-frame.md).

## Motivation

The existing burst-write stress test (`stress_test_runner.dart`) can *exercise*
the iOS-central WriteNoResponse path (set `withResponse: false`) but cannot
*verdict* it: it records local `write()` success/latency, not whether the peer
received the bytes intact. Both I339 (saturation drops) and I343 (the 2-byte
multi-chunk boundary loss) are **silent at the writer**, so a writer-side test
reports success regardless. The gossip dogfood only catches the corruption
because gossip_bluey has a real frame decoder; the stress app has no equivalent
integrity layer on the write path.

A dedicated write-integrity test would give I339 (saturation, single-chunk) and
I343 (multi-chunk boundary) a **repeatable, self-verdicting on-device regression
harness** — replacing the finicky "induce a ≥10 s keyboard-XPC isolate hang"
trigger and the brittle native-log reading. (It still needs two real devices —
nothing escapes the no-Bluetooth-on-simulator constraint — but it removes the
contrived trigger and gives a one-tap pass/fail.)

## Design sketch (from the paused 2026-06-02 brainstorm — revisit post-bisect)

Mechanism **A** (recommended of A/B/C explored): sequenced writes + a pulled
tally over a reliable channel.

- Add a `SeqWrite(seq, payload)` command to `shared/stress_protocol.dart` (next
  free opcode `0x07`) and a `Report` command (`0x08`).
- Client (iOS central): `Reset` → fire a burst of `SeqWrite` **WriteNoResponse**
  writes, `seq = 0..N-1`, payload = deterministic pattern (the existing
  `_generatePattern`) — sized to force **multi-chunk** frames (to repro I343)
  and a **single-chunk** variant (to validate I339 saturation in isolation) →
  settle window → `Report` over a **reliable** (with-response) write.
- Server (`stress_service_handler.dart`): record received `seq`s + validate each
  payload's length/pattern (a coalesced write surfaces as an oversized/garbled
  payload → malformed; a dropped write surfaces as a seq gap). On `Report`,
  `notify` back the tally `{received, missingSeqs, malformed, maxSeq}`.
- Client computes a verdict: PASS iff `received == N` and no missing and no
  malformed; else FAIL with the missing/malformed diagnostics.

The **verdict logic is pure and unit-testable** (the self-monitoring core,
following the project's TDD mandate); only the BLE round-trip is on-device. Only
the burst-under-test uses WriteNoResponse — `Reset`/`Report` use the reliable
path so the control channel never confounds the result.

Integrate as a new `StressTest.writeIntegrity` variant reusing the existing
runner / cubit / config form / result-panel infrastructure.

## Scope notes

- The B (reuse `Echo` + count notifications) and C (read a server count)
  alternatives were considered and rejected: B is blunt (can't separate drop
  from coalesce, heavy reverse load) and C gives no per-seq diagnostics.
- Out of scope: this is example-app test tooling, **not** a bluey-library
  feature — same status as the existing `stress_protocol.dart` scaffolding.
- Brainstorm/spec/plan to be (re)done once I343 is localized, so the harness
  targets the confirmed locus.
