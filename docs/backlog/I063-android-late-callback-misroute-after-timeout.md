---
id: I063
title: Android late GATT callback can be misrouted after app-level timeout
category: bug
severity: medium
platform: android
status: open
last_verified: 2026-04-23
---

## Symptom

When `GattOpQueue` times out an op at the app level (say 10s for `writeCharacteristic`), the op's entry is cleared from `current`. The native layer may still be holding op1 in flight — Android typically rejects subsequent op enqueues until op1's callback is delivered. When the user enqueues op2 after the timeout:

- If Android rejects op2 synchronously (returns `false` from `gatt.writeCharacteristic`), `startNext` handles it: op2 fails with a generic "Failed to write characteristic" error. User sees a confusing error until op1's native callback finally arrives.
- **If Android accepts op2 while op1 is still pending internally** (unclear from docs whether this can happen), op1's eventual callback fires `onCharacteristicWrite` → `handler.post { queue.onComplete(...) }` → but `current` is op2 now, so op2 receives op1's result.

## Location

`bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/GattOpQueue.kt:47-60` — `onComplete` has no mechanism to distinguish "callback for the current op" from "late callback for a previously-timed-out op". Compare with iOS `OpSlot.pendingDrops` which explicitly expects one late callback per timed-out op and discards it (`OpSlot.swift:58, 115-118, 156-159`).

## Root cause

The Android queue relies on Android's native layer rejecting concurrent ops. If that invariant is violated, there's no app-level safety net. Even without invariant violation, the UX after a timeout is poor: a window of several seconds where every op fails with "Failed to write", without explaining why.

## Notes

Two concerns:

1. **Correctness** (uncertain): if Android's native layer ever delivers the callback for op1 while op2 is current, op2 gets op1's result. This depends entirely on Android BLE stack behavior. The safer design is iOS-style: count expected late callbacks and consume them. Worth empirically testing: force a peer-side delay (the stress-test `DelayAckCommand` could be used) on Android, verify the queue's behavior on the next op after timeout.

2. **UX** (certain): the "post-timeout fail window" is confusing. When `startNext`'s `execute()` returns false, the error is a generic `IllegalStateException`. Could be richer — when we timed out recently, include context: *"Previous op may still be pending in the native layer; retrying"*. Or pause the queue after a timeout until the late callback arrives, then resume.

Option 1 (iOS-parity) is the most robust. Option 2 (queue pause) is simpler but relies on the assumption that a late callback does arrive. If the native stack never delivers it (e.g., connection dropped silently), the queue is permanently stuck — worse than today.

Implement option 1: add an `expectedDrops: Int` counter on the queue. On timeout, `expectedDrops += 1`. In `onComplete`, if `expectedDrops > 0`, decrement and return without touching `current`. Reset on `drainAll`. Same shape as OpSlot's `pendingDrops`.
