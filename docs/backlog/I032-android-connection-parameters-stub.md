---
id: I032
title: Connection parameters API stubbed (hardcoded returns)
category: no-op
severity: high
platform: android
status: open
last_verified: 2026-04-23
---

## Symptom

`Connection.getConnectionParameters()` always returns `(intervalMs: 30, latency: 0, timeoutMs: 5000)` — a fabricated default, not what the radio negotiated. `Connection.requestConnectionParameters()` returns success without calling the platform.

Domain API: `bluey/lib/src/connection/connection.dart:286`.

## Location

`bluey_android/lib/src/android_connection_manager.dart:264-281` — two stubs with `// TODO: Implement when Android Pigeon API supports connection parameters`.

## Root cause

Android exposes `BluetoothGatt.requestConnectionPriority(CONNECTION_PRIORITY_HIGH|BALANCED|LOW_POWER|DCK)` — note it's *priority*, not raw parameters. Android does not expose the actual negotiated interval/latency/timeout to apps; you get a high-level priority knob.

So "getConnectionParameters" is a lie on Android — there's no way to read the truth. Options:

- Remove the getter.
- Return `null` / throw `UnsupportedOperationException` on Android.
- Echo the last-requested priority as a symbolic value.

## Notes

Fix direction: rename / reshape the API to `requestConnectionPriority(ConnectionPriority)` with an enum matching Android's four values. Drop `getConnectionParameters()` or document it as "best-effort estimate" returning the last-requested priority.

iOS exposes `requestConnectionParameters(MinInterval, MaxInterval, SlaveLatency, Timeout)` only when advertising as a peripheral, and only on macOS (CBPeripheralManager). Not on iOS for centrals. So this is essentially Android-only.

See also I033 (the connection-priority regression called out in ANDROID_IMPLEMENTATION_COMPARISON).
