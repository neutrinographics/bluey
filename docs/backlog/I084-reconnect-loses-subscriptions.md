---
id: I084
title: Reconnected central loses subscriptions silently
category: bug
severity: medium
platform: both
status: open
last_verified: 2026-04-23
---

## Symptom

When a central disconnects and reconnects (same address on Android; same `CBCentral` identifier on iOS), Bluey clears its subscription tracking on disconnect (for cleanup correctness). On reconnect, subscriptions are NOT restored — the server treats the central as "connected but not subscribed to anything." The central's app thinks it's subscribed (it wrote CCCD bytes earlier in the previous session). Notifications the server tries to send are silently skipped because the central isn't in the subscription set.

BLE spec says subscriptions persist across reconnections for *bonded* devices; for unbonded centrals, they must re-subscribe explicitly. Bluey doesn't make this distinction.

## Location

`bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/GattServer.kt:~380` (disconnect clears subscriptions).

`bluey_ios/ios/Classes/PeripheralManagerImpl.swift` — `didUnsubscribeFrom` clears subscriptions; bonded vs unbonded state not tracked.

`bluey/lib/src/gatt_server/bluey_server.dart:348-369` — reconnect flow doesn't attempt to restore.

## Root cause

No bond-state awareness in subscription tracking. The choice "always clear" is safe for the unbonded case but incorrect for bonded centrals that the spec says should keep their subscriptions.

## Notes

Fix has two parts:

1. Track bond state per central; on bonded-central reconnect, preserve subscriptions.
2. Surface a domain-level signal so apps can either explicitly re-subscribe or be notified that subscriptions were lost.

Simpler compromise: always treat a reconnect as "re-subscribe required" and document it clearly. The client's BLE library will typically re-enable notifications on reconnect as part of its own flow, so a documented convention is enough for most cases.

Downgraded to `medium` because the Bluey client (which is what most Bluey servers talk to) re-subscribes on reconnect as part of its own logic, so the cross-Bluey case works. Bites when the peer is a non-Bluey client.
