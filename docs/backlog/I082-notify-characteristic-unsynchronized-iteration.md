---
id: I082
title: "Android `notifyCharacteristic` iterates subscriptions without synchronization"
category: bug
severity: high
platform: android
status: fixed
last_verified: 2026-04-27
fixed_in: 80ef2ed
related: [I062, I086]
---

> **Fixed 2026-04-27.** Two-part fix: (1) defensive snapshot at iteration entry — `subscriptions[uuid]?.toList() ?: emptyList()` — prevents `ConcurrentModificationException` if mutation lands mid-fanout; (2) every binder-thread mutation of `subscriptions` (CCCD subscribe/unsubscribe in `onDescriptorWriteRequest`, central removal in `STATE_DISCONNECTED`) is now wrapped in `handler.post { … }`, applying the same single-threaded discipline established by the I098 `ConnectionManager` rewrite. 3 new JVM tests in `bluey_android/android/src/test/kotlin/com/neutrinographics/bluey/GattServerNotifyConcurrencyTest.kt`.


## Symptom

`GattServer.notifyCharacteristic(characteristicUuid, value, callback)` iterates `subscriptions[normalizedUuid]` — a plain `MutableSet<String>` — without any synchronization or defensive copy. If a central disconnects on the binder thread during the iteration, `onDescriptorWriteRequest` (for CCCD unsubscribe) or `onConnectionStateChange(DISCONNECTED)` can mutate the set concurrently. The iteration throws `ConcurrentModificationException` or silently skips centrals.

## Location

`bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/GattServer.kt:138-148` (the iteration site).

## Root cause

`subscriptions: MutableMap<String, MutableSet<String>>` is accessed from both Flutter-dispatcher (notify fanout) and binder-thread (callback handlers) without a lock. Same class of bug as I062 but in a different surface.

## Notes

Fix: wrap all mutation and iteration in a shared `ReentrantLock`, or switch to concurrent collections (`ConcurrentHashMap` of `CopyOnWriteArraySet`). Defensive copy at iteration entry (`val snapshot = subscriptions[uuid]?.toList() ?: return`) is the minimal fix.

Related: I062 is the same pattern at the connection level. Both should be fixed as part of a general "Phase 2c: thread-safety audit" pass.
