---
id: I359
title: Correlate iOS op-slot pending drops with their timed-out op
category: bug
severity: medium
platform: ios
status: open
last_verified: 2026-11-17
related: [I350, I063]
---

## Symptom

`OpSlot.pendingDrops` is a bare counter: if a timed-out callback is
genuinely lost (never arrives), the counter stays at 1 and consumes the
*next* op's real completion as a "drop" — which times out and
re-poisons the slot, self-healing only on disconnect (audit DA-11,
latent). The Android sibling of this family is
[I063](I063-android-late-callback-misroute-after-timeout.md).

## Location

`bluey_ios/ios/Classes/OpSlot.swift` — `pendingDrops` count.

## Notes

Correlate each expected drop with the timed-out entry's identity
instead of counting. `OpSlotTests` already covers the happy drop path —
extend it with the lost-callback poison case.

## Audit 2026-11-17

The [2026-11-17 audit](../reviews/2026-11-17-correctness-and-test-rig-audit.md) (M1) shows this is reachable, not latent: it fires whenever a server answers after the 10 s client timeout. The `!slot.isEmpty` guards in `CentralManagerImpl` (`:803`, `:608`) keep the late response from consuming the drop, so it is forwarded as a notification and the next read's real response is dropped as late, and the cycle repeats. Service discovery has the same guard. The fix is therefore not only in `OpSlot`. Closed by slice 4 (native completions) of the architecture foundation ([design](../superpowers/specs/2026-11-17-architecture-foundation-design.md)), after the central seam of [I350](I350-ios-central-manager-delegate-seam.md).
