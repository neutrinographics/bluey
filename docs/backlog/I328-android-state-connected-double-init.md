---
id: I328
title: Android per-device caches are reset to defaults if `STATE_CONNECTED` fires twice for the same device
category: bug
severity: low
platform: android
status: open
last_verified: 2026-05-05
related: [I325]
---

## Symptom

`ConnectionManager.kt`'s `BluetoothGattCallback.onConnectionStateChange` initializes per-device state inside the `STATE_CONNECTED` branch:

```kotlin
connections[deviceId] = gatt
queues[deviceId] = GattOpQueue(gatt, handler)
negotiatedMtu[deviceId] = 23  // I325
```

Android occasionally fires `STATE_CONNECTED` more than once for the same `deviceId` — particularly with certain chipsets after auto-reconnect, or if `BluetoothGatt.connect()` is invoked while a connection already exists. When that happens:

- `connections[deviceId] = gatt` overwrites the cached `BluetoothGatt` reference (probably fine — it's the same instance, or the new one supersedes the old).
- `queues[deviceId] = GattOpQueue(...)` **discards any in-flight ops** in the old queue and replaces it with an empty one. Pending callbacks are leaked.
- `negotiatedMtu[deviceId] = 23` **wipes a previously negotiated MTU back to 23**, so subsequent `getMaximumWriteLength(...)` returns `20` until the next `requestMtu` round-trip.

## Location

- `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/ConnectionManager.kt` — the `STATE_CONNECTED` branch in `onConnectionStateChange` (around line 660).

## Why low severity

- Pre-existing pattern; the `queues` map has had this issue since long before I325. The `negotiatedMtu` map is new with I325 but inherits the same shape.
- In practice, double-`STATE_CONNECTED` firings are rare and usually transient on the same connection lifecycle.
- The user-facing impact is mostly "MTU temporarily reads 23", which `requestMtu` corrects.

## Fix sketch

Two options:

1. **Guard each per-device map with a `containsKey` check** — only initialize if absent. Simplest, no behavior change for the common case. Downside: a *real* reconnection (where the previous disconnect wasn't cleanly observed) leaves stale entries.

2. **Clear all per-device maps on entering `STATE_CONNECTED`, reset to defaults, then init.** More defensive — guarantees a clean slate. Downside: if a reconnection ever fires `STATE_CONNECTED` while a previous connection is still partly alive, this throws away that state.

Option 1 is safer; option 2 is more correct but riskier without test coverage for the duplicate-event path.

## Notes

Discovered during the I325 audit (the `negotiatedMtu` cache is the first new use of this pattern). The pre-existing `queues` issue means a fix should also touch `queues` — bundle them.
