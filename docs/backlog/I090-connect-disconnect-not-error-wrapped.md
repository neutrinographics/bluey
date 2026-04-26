---
id: I090
title: "`Bluey.connect()` and `BlueyConnection.disconnect()` bypass error translation"
category: bug
severity: high
platform: domain
status: open
last_verified: 2026-04-26
related: [I092, I099]
---

## Symptom

Every GATT op on `BlueyConnection` routes through `_runGattOp` which translates platform-interface exceptions into the `BlueyException` sealed hierarchy. But two entry points don't:

- `Bluey.connect(device, ...)` calls `_platform.connect(...)` directly. Platform failures (`BluetoothAdapterUnavailable`, `GattConnectionCreationFailed`, `ConnectionTimeout`, permission-denied, etc.) surface as raw `PlatformException` / `PigeonError`.
- `BlueyConnection.disconnect()` calls `_platform.disconnect(...)` directly. Same issue.

Callers pattern-matching on Bluey's typed exceptions miss these paths.

## Location

- `bluey/lib/src/bluey.dart:~328` (the `connect` call).
- `bluey/lib/src/connection/bluey_connection.dart:402` (`disconnect`).
- `bluey/lib/src/connection/bluey_connection.dart:443` (`bond`).
- `bluey/lib/src/connection/bluey_connection.dart:448` (`removeBond`).
- `bluey/lib/src/connection/bluey_connection.dart:464` (`requestPhy`).
- `bluey/lib/src/connection/bluey_connection.dart:478` (`requestConnectionParameters`).

Each of these can throw typed platform-interface exceptions (`GattOperationTimeoutException`, etc.) that leak unwrapped to the caller.

## Root cause

These paths pre-date the `_runGattOp` convention or were never retrofitted.

## Notes

Fix: wrap both calls through `_runGattOp` (or a variant that doesn't assume an `onSuccess` activity signal — connect/disconnect aren't GATT ops in the activity-tracking sense). Translate platform exceptions using the existing `_translateGattPlatformError` on the adapter side.

Ensure the translated exceptions for these paths are distinct from GATT-op exceptions — `ConnectionException` or similar domain types rather than `GattOperationFailedException`. The domain's `exceptions.dart` already has `ConnectionException` for this purpose — just needs wiring.

Fix bundled into I099 (typed-error-translation rewrite spec) — the bypass pattern is uniform across `connect`, `disconnect`, `bond`, `removeBond`, `requestPhy`, `requestConnectionParameters`, and a unified `translateGattErrors` helper covers all of them.
