---
id: I087
title: Connection doesn't auto-reconnect after failure-injection-style disconnect
category: bug
severity: medium
platform: ios
status: open
last_verified: 2026-04-25
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

**Update 2026-04-25:** [I096](I096-ios-nil-disconnect-error-to-unknown.md) was a *necessary* sub-fix — it eliminated the `bluey-unknown` exception from the disconnect cascade, which was hypothesised in this entry's original Notes as the likely root cause. After landing I096, on-device verification shows the cascade is now well-typed (`1 GattTimeoutException + 9 GattOperationDisconnectedException`, no `bluey-unknown`) — but **the connection still does not reconnect.**

That confirms hypothesis #2 from this entry's original "Root cause" section: the **example-app reconnect cubit** is the actual blocker. The cubit isn't reacting to `GattOperationDisconnectedException` either. I087 stays open until the cubit fix lands.

Refined location: `bluey/example/lib/features/connection/presentation/connection_cubit.dart` — needs investigation of how the cubit observes disconnects, what triggers reconnect, and what (if anything) gates reconnect from firing in this scenario.

Symptom updated post-I096: the cascade is now `1 GattTimeoutException + N-1 GattOperationDisconnectedException` (no `bluey-unknown`). The "no reconnect" outcome remains. Tagged `platform: ios` because the failure-injection scenario only reproduces on iOS-client → Android-server today (the OpSlot serialization on iOS is what shapes this exact sequence) — but the cubit code at fault is shared Dart, not iOS-specific.

I091 remains open for the original CBATTError allowlist concern (no production evidence it fires; low priority).
