---
id: I087
title: Connection doesn't auto-reconnect after failure-injection-style disconnect with unmapped platform error
category: bug
severity: medium
platform: ios
status: open
last_verified: 2026-04-24
related: [I079, I091, I090]
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

Step 1 is to reproduce and instrument: add logging to the iOS disconnect callback and the connection-state stream to see which events actually fire in this sequence. Specifically: does `ConnectionState.disconnected` emit? If yes → example app bug. If no → iOS library bug (missing state emission on this error path).

Blocks: would benefit from having I079 fixed first, because I079's starvation is what triggers this disconnect sequence in the first place. Once I079 is fixed, reproducing I087 may require a different trigger (some other way to surface an unmapped CBATTError during teardown) — or I087 may simply not reproduce without the artificial starvation.

Medium severity: the failure mode is narrow (requires both a long-blocked op AND an unmapped CBATTError at disconnect time) but the outcome is severe (permanent connection loss requiring user intervention).
