---
id: I077
title: Client appears to toggle connected/disconnected during heartbeat activity
category: bug
severity: medium
platform: both
status: fixed
last_verified: 2026-04-24
fixed_in: 0b97cc6
related: [I020, I021]
---

## Symptom

During manual verification of the I020+I021 fix (Android server + iOS client), the server-side log shows the client cycling connected/disconnected every ~1s during heartbeat activity:

```
I/flutter: [Bluey] [Server] Client connected: 6D:FE:B9...
D/GattServer: onCharacteristicWriteRequest: ... char=b1e70002-... requestId=N preparedWrite=false responseNeeded=true
I/flutter: [Bluey] [Server] Client disconnected: 6D:FE:B9...
I/flutter: [Bluey] [Server] Client connected: 6D:FE:B9...
D/GattServer: onCharacteristicWriteRequest: ... char=b1e70002-... requestId=N+1 ...
I/flutter: [Bluey] [Server] Client disconnected: 6D:FE:B9...
...
```

The iOS client logs do NOT show matching BLE-level disconnects. The storm is entirely at the Dart lifecycle layer — the BLE ATT connection stays up. Writes and reads to application characteristics still work during the storm (verified: `AA BB CC` write-then-read round-trip on the demo char succeeded).

## Location

- `bluey/lib/src/gatt_server/lifecycle_server.dart:68` — the check `req.value[0] == lifecycle.disconnectValue[0]` (where `disconnectValue = [0x00]`) is what fires `onClientGone`.
- `bluey/lib/src/lifecycle.dart:42-45` — `heartbeatValue` and `disconnectValue` constants.

## Root cause

Unknown — initial hypothesis was that the iOS lifecycle client was sending `[0x00]` accidentally as a heartbeat payload, but `heartbeatValue = [0x01]` makes that unlikely for a straight constant write. Other possibilities:

- Duplicate delivery of a single disconnect command (double-fires `onClientGone`).
- The iOS lifecycle client sending a legitimate disconnect command followed immediately by a new heartbeat (e.g. re-initialization across some event).
- An empty-payload write reaching the handler with `value.isEmpty == true`, short-circuiting the `value[0] == 0x00` check to `false` but then hitting some other code path that flips connection state.
- A race in `LifecycleServer.recordActivity` or `_resetTimer` that fires `onClientGone` spuriously.

The behaviour is pre-existing — the Kotlin-side fix doesn't change *what* Dart sees for a given wire-level write, only *when*. It became observable during manual verification because the full lifecycle request/response round-trip now actually flows (previously the Android side short-circuited with auto-respond, and the client may have retried less aggressively).

## Notes

Fix sketch: instrument `LifecycleServer.handleWriteRequest` temporarily to log every incoming write payload (byte-level) plus the result of the disconnect-value check, then reproduce the storm and match payloads against what the iOS client is sending. Once the trigger is identified:

- If the iOS client is sending `[0x00]` accidentally: fix the iOS lifecycle client.
- If a duplicate delivery is the cause: add idempotency on `onClientGone` (already tracked via timer state, but audit for races).
- If an empty payload is triggering something: tighten the early-return condition.

Reproduction: Android server (Pixel 6a) + iOS client (app on iPhone), connect, let the lifecycle heartbeat cycle run for ~30s, watch the Android log. Should see the connected/disconnected pair repeating. User-visible impact is low (application reads/writes still succeed) but indicates a broken invariant in the lifecycle protocol.

Not blocking I020/I021 since this behaviour pre-dates the fix and application-level reads/writes succeed regardless.
