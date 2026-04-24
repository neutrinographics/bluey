---
id: I009
title: `BlueyServer.respondToRead`/`respondToWrite` leak internal platform-interface exception
category: bug
severity: medium
platform: domain
status: open
last_verified: 2026-04-24
related: [I020, I021]
---

## Symptom

When the platform implementation rejects a `respondToRead`/`respondToWrite` call (e.g. unknown `requestId` after a central-disconnect drain), the `GattOperationStatusFailedException` thrown by the adapter propagates out of `BlueyServer.respondToRead`/`respondToWrite` to user code without being wrapped in a user-facing `BlueyException` subtype.

`GattOperationStatusFailedException`'s own docstring at `bluey_platform_interface/lib/src/exceptions.dart:76-78` explicitly calls itself "Internal platform-interface signal. Not part of the `BlueyException` sealed hierarchy in the `bluey` package; `BlueyConnection` translates this into a user-facing exception at the public API boundary." The client-side (`BlueyConnection`) honours that contract. The server-side (`BlueyServer`) does not.

## Location

- `bluey/lib/src/gatt_server/bluey_server.dart:299-321` — `respondToRead`/`respondToWrite` call `_platform.respondTo{Read,Write}Request` directly with no `try/catch` and no translation.
- Compare with `bluey/lib/src/connection/bluey_connection.dart` — client-side path that correctly translates `GattOperationStatusFailedException` → `GattOperationFailedException` (a `BlueyException` subtype).
- `bluey_platform_interface/lib/src/exceptions.dart:64-103` — docstring that says this class is not meant to leak to user code.

## Root cause

Oversight when the server-side respond methods were first wired up. The client-side wrap existed when `GattOperationStatusFailedException` was introduced; the server-side calls were added later without the equivalent translation. Became newly relevant after the I020/I021 fix, because those error paths now actually fire (previously the server respond calls were no-ops and never raised).

## Notes

Fix sketch: add a `runGuarded`-style wrapper in `BlueyServer` mirroring the one in `BlueyConnection`. Needs a design decision about which user-facing `BlueyException` subtype is right:

- Reuse `GattOperationFailedException` (same class as client-side), OR
- Add a new `ServerRespondFailedException` — probably cleaner, since the semantics ("your pending request is gone") are different from the client-side ("the peer returned a non-success ATT status").

Out of scope for the I020+I021 PR because the fix for that PR can't leak what the old no-op paths didn't leak either. Track here for the next domain-layer pass.

Related: I020, I021 (surfaced this; the new `NoPendingRequest → gatt-status-failed(0x0A)` path is a primary trigger).
