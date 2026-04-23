---
id: I008
title: Notification subscription race (mitigated, not prevented)
category: bug
severity: low
platform: domain
status: open
last_verified: 2026-04-23
historical_ref: BUGS-ANALYSIS-#2
---

## Symptom

When the first listener subscribes to a characteristic's `notifications` stream, `_onFirstListen` kicks off `setNotification(enable: true)` without awaiting it and immediately subscribes to the platform's `notificationStream`. In theory, a notification that arrives between the CCCD write reaching the server and the subscription being attached could be missed. In practice, errors are now surfaced via `.catchError` on the CCCD write, which fixes the silent-failure half of the original bug.

## Location

`bluey/lib/src/connection/bluey_connection.dart:773-805` — the lazy enable path inside `BlueyRemoteCharacteristic`.

## Root cause

The subscription attaches synchronously but the CCCD write is async. Ordering is "subscribe then write" which on paper is correct, but the implementation doesn't await the write before returning the stream handle, so callers may observe `setNotification` failures only via the stream's error channel instead of a thrown exception on the first `await characteristic.notifications.first` call.

## Notes

Low priority because in practice BLE stacks buffer the first few notifications after CCCD write, and errors do reach the stream. Proper fix: switch to an `await`-gated pattern guarded by a mutex, as outlined in BUGS_ANALYSIS #2. Also useful for distinguishing "notifications failed to enable" from "device sent no notifications."
