---
id: I001
title: Disconnect state double-emission
category: bug
severity: medium
platform: domain
status: open
last_verified: 2026-04-23
historical_ref: BUGS-ANALYSIS-#3
---

## Symptom

Listeners on `Connection.stateChanges` receive `ConnectionState.disconnected` twice when `disconnect()` is called: once from the manual emission inside `disconnect()`, and again from the platform state callback.

## Location

`bluey/lib/src/connection/bluey_connection.dart:381-410` — `disconnect()` manually emits `disconnecting` then `disconnected` via `_stateController.add()`.

`bluey/lib/src/connection/bluey_connection.dart:182-191` — the platform `connectionStateStream` listener also emits whatever state the platform reports, including `disconnected` after the native-side tear-down completes.

## Root cause

Two independent code paths drive the state stream with no deduplication. There's no sentinel that says "I've already emitted this terminal state, drop the callback echo."

## Notes

Two viable fixes:

1. Treat the platform callback as the source of truth. `disconnect()` sets local state but doesn't emit; it awaits `stateChanges.firstWhere(disconnected)` with a fallback timeout. Cleaner state machine but requires ordering discipline.
2. Cancel the platform subscription before the manual emission in `disconnect()`. Simple, but the subscription can no longer observe unexpected late-stage events.

Needs a test that asserts exactly one `disconnected` emission per disconnect call.
