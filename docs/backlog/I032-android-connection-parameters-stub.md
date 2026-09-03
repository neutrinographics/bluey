---
id: I032
title: Connection parameters API stubbed (hardcoded returns)
category: no-op
severity: medium
platform: android
status: open
last_verified: 2026-09-03
---

## Symptom

`connection.android?.connectionParameters` and
`requestConnectionParameters(...)` throw `UnsupportedOperationException` on
Android; `Capabilities.android.canRequestConnectionParameters` is `false`. The exception comes from the domain capability gate (action: "Check bluey.capabilities before calling"); the Android adapter's underlying stubs throw `UnimplementedError` (I035 Stage A) but are unreachable from the public API. This is honest — nothing silently succeeds any more — but the feature does not exist on any platform.

(Historical, pre-2026-04-26: the getter returned a fabricated
`(30 ms, 0, 5000 ms)` and the request resolved without calling the platform.)

## Location

Capability gate: `bluey/lib/src/connection/bluey_connection.dart`
(`_AndroidConnectionExtensionsImpl._requireCapability`). Flag:
`bluey_platform_interface/lib/src/capabilities.dart`. Adapter stubs:
`bluey_android/lib/src/android_connection_manager.dart`
(`getConnectionParameters`, `requestConnectionParameters` throw
`UnimplementedError`).

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

**Severity note (2026-06-02):** Downgraded high→medium — Stage A landed (methods now throw `UnimplementedError` and are capability-gated rather than silently succeeding); only Stage B (Pigeon + native impl) remains, and these are rarely-used APIs (bonding is legacy; PHY/conn-params niche).
