---
id: I009
title: `BlueyServer.respondToRead`/`respondToWrite` leak internal platform-interface exception
category: bug
severity: medium
platform: domain
status: fixed
last_verified: 2026-04-26
fixed_in: a6bd217
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

Fixed in `a6bd217` by adding a new `ServerRespondFailedException` to the `BlueyException` sealed hierarchy (server bounded context) and wrapping `respondToRead` / `respondToWrite` in `BlueyServer` with a typed catch on `GattOperationStatusFailedException` that rethrows the new exception.

Decision: chose option B (new exception, not reuse of `GattOperationFailedException`). The client-side and server-side variants signal genuinely different domain events even though they carry the same platform status byte: the client-side means "peer rejected my write with a non-success ATT status," whereas the server-side means "the platform refused my reply, usually because the central is gone." Bounded contexts get their own vocabulary.

Payload (rich for debugging): `operation` (`'respondToRead'` or `'respondToWrite'`), `status` (native ATT byte, e.g. `0x0A` NoPendingRequest), `clientId` (the central's `Client.id`), `characteristicId` (the original request's target characteristic).

Related: I020, I021 (surfaced this; the new `NoPendingRequest → gatt-status-failed(0x0A)` path is a primary trigger).
