---
id: I087
title: Connection doesn't auto-reconnect after failure-injection-style disconnect with unmapped platform error
category: bug
severity: medium
platform: ios
status: fixed
last_verified: 2026-04-25
fixed_in: c145209
related: [I079, I091, I090, I096]
---

## Symptom

Running the **failure-injection** stress test (iOS client → Android server):

1. Client writes `DropNextCommand` — accepted by the server.
2. Client writes 9 echo commands; the first is silently dropped by the server.
3. Client hits its 10s per-op timeout on the dropped write → `GattTimeoutException`.
4. Heartbeat had been queued behind the dropped write (I079), server tears the link down.
5. The disconnect surfaces on the Dart side as `BlueyPlatformException(bluey-unknown)` (an iOS `CBATTError` code that isn't in the mapping allowlist — see I091).
6. The remaining 8 queued echo writes fail with `DisconnectedException`.
7. **The connection cubit never attempts to reconnect.** The stress-test UI shows a "connection lost" banner and the test run ends.

Compare to the **timeout-probe** test (same underlying starvation path but cleaner error shape): the connection *does* auto-reconnect. Only the failure-injection sequence — which layers an unmapped `CBATTError` into the mix — fails to recover.

## Location

Unconfirmed. Candidates:

- `bluey_ios/ios/Classes/NSError+Pigeon.swift` — the unmapped error that becomes `bluey-unknown` (I091) may be masking a disconnect signal the reconnect logic normally keys off.
- `bluey/example/lib/features/connection/presentation/connection_cubit.dart` — the example app's reconnect trigger may gate on specific exception types and reject `BlueyPlatformException(bluey-unknown)`.
- `bluey_ios/ios/Classes/CentralManagerImpl.swift` — the disconnect-path state teardown; if it doesn't emit a `ConnectionState.disconnected` event in this error path, no downstream subscriber would know to reconnect.

## Root cause

**Needs investigation.** The two most plausible root causes:

1. **I091 cascade.** The unmapped `CBATTError` returning `bluey-unknown` breaks an assumption somewhere in the disconnect → reconnect pipeline. Fixing I091 (mapping the missing CBATTError code) may fix this as a side effect.

2. **Example-app reconnect policy.** The `ConnectionCubit` may only auto-reconnect on `DisconnectedException` paths and ignore `BlueyPlatformException`-flavored disconnects. If so, the bug is in the example app, not the library — but the library should still emit a normal `ConnectionState.disconnected` for every disconnect flavor, regardless of which exception bubbled up to the caller of the in-flight op.

## Notes

Fixed in `c145209` by [I096](I096-ios-nil-disconnect-error-to-unknown.md).

The hypothesis in this entry's original Notes ("fixing I091 may fix this
as a side effect") was directionally right — the bluey-unknown was
indeed the cascade trigger — but pointed at the wrong code path.
Diagnostic instrumentation revealed the bluey-unknown comes from
`CentralManagerImpl.didDisconnectPeripheral` falling through on
`error: nil`, **not** from `NSError.toPigeonError()`'s `CBATTError`
allowlist gap.

I091 remains open for the original CBATTError allowlist concern (no
production evidence it fires; low priority).
