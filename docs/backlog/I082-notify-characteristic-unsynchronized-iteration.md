---
id: I082
title: "Android `notifyCharacteristic` iterates subscriptions without synchronization"
category: bug
severity: high
platform: android
status: open
last_verified: 2026-04-23
---

## Symptom

`GattServer.notifyCharacteristic(characteristicUuid, value, callback)` iterates `subscriptions[normalizedUuid]` — a plain `MutableSet<String>` — without any synchronization or defensive copy. If a central disconnects on the binder thread during the iteration, `onDescriptorWriteRequest` (for CCCD unsubscribe) or `onConnectionStateChange(DISCONNECTED)` can mutate the set concurrently. The iteration throws `ConcurrentModificationException` or silently skips centrals.

## Location

`bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/GattServer.kt:138-148` (the iteration site).

## Root cause

`subscriptions: MutableMap<String, MutableSet<String>>` is accessed from both Flutter-dispatcher (notify fanout) and binder-thread (callback handlers) without a lock. Same class of bug as I062 but in a different surface.

## Notes

Fix: wrap all mutation and iteration in a shared `ReentrantLock`, or switch to concurrent collections (`ConcurrentHashMap` of `CopyOnWriteArraySet`). Defensive copy at iteration entry (`val snapshot = subscriptions[uuid]?.toList() ?: return`) is the minimal fix.

Related: I062 is the same pattern at the connection level. Both should be fixed as part of a general "Phase 2c: thread-safety audit" pass.
