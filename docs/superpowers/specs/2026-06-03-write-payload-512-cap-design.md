# Clamp the write-payload limit to the BLE 512-octet attribute cap (I343)

- **Date:** 2026-06-03
- **Status:** Approved (design)
- **Backlog:** [I343](../../../docs/backlog/I343-ios-to-android-multi-chunk-writenoresponse-loses-2-bytes-per-frame.md)
- **Related:** I046 / I325 (`maxWritePayload` + `WritePayloadLimit`), I339 (WnR flow control), I344 (regression stress test)

## Problem

An iOS central writing a `WriteNoResponse` payload sized at
`maximumWriteValueLength(for: .withoutResponse)` = **514** (ATT_MTU − 3 @ MTU 517)
to an Android peripheral loses the last **2 bytes** — the peripheral's
`onCharacteristicWriteRequest` receives only **512**. Because a Write Command
carries no response, the loss is silent; every multi-chunk frame's first
(max-size) chunk corrupts, which breaks the consumer's frame decoder and kills
iOS→Android delivery for the GATT session. (Full evidence + bisect in I343.)

**Root cause (confirmed by simultaneous capture + spec research):** the
Bluetooth Core Spec (Vol 3, Part F §3.2.9) caps an attribute value at **512
octets**, independent of ATT/L2CAP framing. Two compounding defects:
1. iOS's `maximumWriteValueLength(for: .withoutResponse)` returns `ATT_MTU − 3`
   **without applying the 512 cap** → over-reports 514 at MTU 517.
2. The Android (Bluedroid/Fluoride) GATT server has a fixed 512-byte
   `GATT_MAX_ATTR_LEN` receive buffer and **silently discards** bytes beyond it.

The true safe maximum is **`min(ATT_MTU − 3, 512)`**. The earlier empirical
`−2` / "MTU − 5" framing was a coincidence that holds *only* at MTU 517
(517 − 5 = 512); at smaller MTUs the real maximum is `MTU − 3` and a `−2` would
wrongly shave 2 usable bytes. Clamping to 512 is what RxAndroidBle, Nordic's
Android-BLE-Library, and flutter_blue_plus converged on after Android 13/14
began always negotiating MTU 517.

## Decision: clamp in the `WritePayloadLimit` value object

`maxWritePayload` (both platforms) funnels its platform-reported value through
one factory: `WritePayloadLimit.fromPlatform(int value)`
(`bluey/lib/src/connection/value_objects/write_payload_limit.dart`). Enforce the
spec cap there:

```dart
/// Bluetooth Core Spec Vol 3, Part F §3.2.9 — "the maximum length of an
/// attribute value shall be 512 octets." A central must not write a single
/// attribute value larger than this regardless of the negotiated MTU; doing so
/// is silently truncated by spec-conforming peripherals (e.g. Android's fixed
/// GATT_MAX_ATTR_LEN buffer). iOS's maximumWriteValueLength(.withoutResponse)
/// over-reports (returns MTU-3 without the cap), so we clamp here.
const int maxAttributeValueLength = 512;

factory WritePayloadLimit.fromPlatform(int value) =>
    WritePayloadLimit._raw(value > maxAttributeValueLength
        ? maxAttributeValueLength
        : value);
```

(`fromPlatform` keeps its existing leniency for the `0` / `−1` "unavailable"
sentinels — the clamp only ever lowers values **above** 512, so sub-512 and
sentinel values pass through unchanged.)

**Why here:**
- The 512-octet limit is a **protocol invariant**, so the domain value object is
  its correct owner — one clamp covers iOS (514→512) *and* Android-central
  (`mtu−3`=514→512), with **no native changes**.
- It is **pure, Dart-unit-testable** logic — no XCTest / native magic number.
- `min(reported, 512)` is correct at every MTU (no needless throughput loss at
  small MTUs, unlike a fixed `−2`).
- Applies uniformly to **both write types**: the cap is on attribute-value
  length, so `withResponse` (already ≤512 on iOS) is a no-op and
  `withoutResponse` (the broken path) is corrected.

## Testing

- **Unit tests** on `WritePayloadLimit.fromPlatform`: `514 → 512`, `512 → 512`,
  `513 → 512`, `200 → 200`, `0 → 0`, `-1 → -1` (sentinels preserved). TDD
  red→green entirely in Dart.
- **Update** the existing `write_payload_limit_test.dart` and
  `max_write_payload_test.dart` for the clamped expectation.
- **I344 stress test** remains the on-device regression guard (send at the
  reported max; verify un-truncated arrival).

## Out of scope / cleanup

- **No native changes.** iOS `getMaximumWriteLength` and Android's `mtu − 3`
  stay as-is (they report the raw platform value); the domain clamps. (A future
  refinement could also clamp natively for defense-in-depth, but it's redundant
  given the single domain funnel — YAGNI.)
- **Mechanism investigation: closed.** The research fully explains it (spec cap
  + Android `GATT_MAX_ATTR_LEN` + iOS over-report); the Android→Android probe
  and air-sniffer idea are dropped.
- **Revert the verification hack.** Delete branch `i343-bisect-instrumentation`
  (the `−2` cap + native length logging) — throwaway, never on `main`.

## Docs

- One-line note in `bluey/docs/cross-platform-quirks.md`: max single-attribute
  write is 512 octets regardless of MTU; bluey clamps `maxWritePayload`
  accordingly (cite the spec).
- Flip **I343** to `status: fixed` with the `fixed_in` SHA once it lands.

## Implementation footprint

- `bluey/lib/src/connection/value_objects/write_payload_limit.dart` — add
  `maxAttributeValueLength` const + clamp in `fromPlatform`.
- `bluey/test/connection/value_objects/write_payload_limit_test.dart` — clamp
  cases.
- `bluey/test/connection/max_write_payload_test.dart` — adjust expectation if it
  asserts an unclamped value.
- `bluey/docs/cross-platform-quirks.md` — the note.
- `docs/backlog/I343-*.md` — status → fixed.
