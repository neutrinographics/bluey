---
id: I087
title: Connection doesn't auto-reconnect after failure-injection-style disconnect
category: bug
severity: medium
platform: ios
status: wontfix
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

**Resolution 2026-04-25 (wontfix).** This entry's premise — "the connection should auto-reconnect after failure-injection-style disconnect" — was inherited from a comparison to the **timeout-probe** test that no longer applies post-I079. Pre-I079, both tests caused a disconnect (because of I079's starvation false-positive), and the timeout-probe's "auto-reconnect after disconnect" was the visible recovery path. Post-I079, the timeout-probe **no longer disconnects at all** — there's no longer a "compare to timeout-probe reconnecting" example. The expectation that failure-injection should also auto-reconnect was carried forward incorrectly.

Re-examining the failure-injection chain post-I079 / post-I096:

1. Server drops a response (deliberate).
2. Client times out cleanly → `GattTimeoutException`.
3. `LifecycleClient` correctly counts the failed heartbeat and (with default `maxFailedHeartbeats=1`) declares the peer unreachable.
4. Client tears down via `cancelPeripheralConnection` — correct policy given the information available.
5. Queued ops drain as typed `GattOperationDisconnectedException` (post-I096 — no more `bluey-unknown`).
6. Connection ends in `disconnected` state; example-app dialog offers a manual "Reconnect" button.

**Every step is correct, deliberate library behaviour.** The disconnect *is* the expected outcome of injecting a failure that crosses the dead-peer threshold. The cubit's lack of auto-reconnect is a deliberate UX choice (manual control via the existing dialog), not a bug.

What's actually open here is a **descriptive** issue: the failure-injection test's help text claims "writeCount − 1 successes" as the healthy outcome, which never matches the post-I079 reality. That is being addressed separately as a stress-test description audit, plus exposing `maxFailedHeartbeats` as a tunable in the example app so users can demonstrate both the disconnect-cascade scenario (low tolerance) and the recovery scenario (higher tolerance).

I096 remains correctly closed — it was a real bug (semantically wrong error mapping) and its fix stands on its own merits regardless of this entry's resolution.

I091 remains open for the original `CBATTError` allowlist concern (no production evidence it fires; low priority).
