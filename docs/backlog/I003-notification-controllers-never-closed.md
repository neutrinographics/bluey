---
id: I003
title: "Memory leak: notification controllers never closed"
category: bug
severity: high
platform: domain
status: fixed
last_verified: 2026-04-27
fixed_in: f69dafa
historical_ref: BUGS-ANALYSIS-#5
---

> **Fixed 2026-04-27.** `BlueyRemoteCharacteristic` and `BlueyRemoteService` now expose `dispose()`; `BlueyConnection._cleanup()` walks `_cachedServices` and disposes each before nulling the cache. 3 new tests in `bluey/test/connection/bluey_connection_disposal_test.dart`. Out of scope (deferred): the autonomous link-loss path (platform reports `DISCONNECTED` without the user calling `disconnect()`) does not flow through `_cleanup()` and still leaks. Per the original fix-sketch's recommendation, reconnect-creates-fresh-BlueyConnection makes this acceptable for now.


## Symptom

Each `BlueyRemoteCharacteristic` lazily creates a broadcast `StreamController<Uint8List>` the first time `notifications` is accessed. On disconnect, `BlueyConnection._cleanup()` closes the connection-level controllers (state, bond, PHY) but never walks the cached service/characteristic tree to close these per-characteristic controllers. Over many connect/disconnect cycles, memory grows monotonically.

## Location

Leak origin: `bluey/lib/src/connection/bluey_connection.dart:764` (controller created lazily inside `BlueyRemoteCharacteristic`).

Missing cleanup: `bluey/lib/src/connection/bluey_connection.dart:531-543` (`_cleanup()`).

## Root cause

No disposal contract on `BlueyRemoteCharacteristic` / `BlueyRemoteService`. `_cachedServices` is set to `null` but the controllers it referenced are still alive because the platform `notificationStream` subscription inside each characteristic holds them.

## Notes

Fix sketch: give `BlueyRemoteCharacteristic` a `dispose()` that cancels `_notificationSubscription` and closes `_notificationController`; give `BlueyRemoteService` a `dispose()` that iterates its characteristics. Call service `dispose()` from `BlueyConnection._cleanup()` before nulling `_cachedServices`.

Also worth considering whether disposing on `disconnect()` is the right trigger vs a separate `Connection.dispose()` — currently a reconnect creates a fresh `BlueyConnection`, so tying cleanup to disconnect is fine.
