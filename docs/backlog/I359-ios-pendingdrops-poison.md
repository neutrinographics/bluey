---
id: I359
title: Correlate iOS op-slot pending drops with their timed-out op
category: bug
severity: medium
platform: ios
status: open
last_verified: 2026-07-10
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
