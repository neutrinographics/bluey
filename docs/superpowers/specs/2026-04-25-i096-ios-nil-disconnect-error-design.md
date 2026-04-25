# iOS: `didDisconnectPeripheral` with `error: nil` produces `bluey-unknown`

**Status:** proposed
**Date:** 2026-04-25
**Scope:** `bluey_ios` only — `CentralManagerImpl.swift` translation of disconnect callbacks. No Dart-side changes, no platform-interface changes, no protocol changes.
**Backlog entry:** to be filed as **I096**. Supersedes the originally-suspected scope of [I091](../../backlog/I091-ios-unmapped-cbatt-error-to-unknown.md) for this specific symptom; partially closes [I087](../../backlog/I087-failure-injection-no-auto-reconnect.md).

## Problem

In the failure-injection stress test (iOS client → Android server, post-I079), when the connection is torn down:

- The user observes `BlueyPlatformException(bluey-unknown) × 1` immediately followed by `DisconnectedException × 7` as queued ops drain.
- The example app's reconnect cubit fails to recover because it keys off `GattOperationDisconnectedException` (the Dart shape of `gatt-disconnected`) and doesn't recognize `BlueyPlatformException(bluey-unknown)` as a disconnect.

Diagnostic instrumentation (commits `170b1cb` / `0aceb8a` / `b746d98` on `investigate/i091-cbatt-error-instrumentation`) confirmed:

```
[I091-DIAG] didDisconnectPeripheral with error=nil — pending ops will drain as bluey-unknown
```

The `bluey-unknown` is **not** coming from `NSError.toPigeonError()` (the original I091 hypothesis). It comes from `CentralManagerImpl.didDisconnectPeripheral` falling through to `BlueyError.unknown.toClientPigeonError()` when CoreBluetooth's `error` parameter is `nil`.

## Root cause

`CentralManagerImpl.swift:494-495`:

```swift
let pigeonError: Error = (error as NSError?)?.toPigeonError()
    ?? BlueyError.unknown.toClientPigeonError()
clearPendingCompletions(for: deviceId, error: pigeonError)
```

Per Apple's CoreBluetooth docs, `peripheral(_:didDisconnectPeripheral:error:)` is called with `error: nil` for *graceful* disconnects: either we ourselves called `cancelPeripheralConnection`, or the peer initiated a clean shutdown. `error: nil` does **not** mean "an unknown error occurred"; it means "no metadata, but the link is gone."

Mapping nil error to `BlueyError.unknown` (which translates to `bluey-unknown`) is semantically wrong. The link being gone is itself the meaningful signal — it should produce `gatt-disconnected`, the same shape every other dead-peer signal in this codebase uses.

## Why this surfaces post-I079

Pre-I079, the *server* tore down the link in failure injection (heartbeat starvation false-positive). iOS observed an externally-initiated disconnect, which typically arrives with a non-nil `CBError` (e.g., `peripheralDisconnected`) — handled correctly by `nsError.toPigeonError()`.

Post-I079, the server stays patient. The client's own `LifecycleClient.onServerUnreachable` instead calls `cancelPeripheralConnection` when its heartbeat probe fails. iOS reports that *self-initiated* disconnect with `error: nil` — taking the broken nil-error branch.

So the bug existed before I079 too, but I079's fix is what shifted the disconnect cause from external (with NSError) to self-initiated (without NSError), making this code path routine.

## Non-goals

- **Not changing `didFailToConnect`'s nil-error branch.** No diagnostic evidence that path fires in the wild. Connect-failure semantics differ subtly from disconnect (no established `gatt-connection-failed` code, broader changes needed). Leave it alone.
- **Not changing `LifecycleClient`'s disconnect-on-heartbeat-failure policy.** That policy is correct given current information — heartbeat timeout looks identical to peer-dead. Tuning `maxFailedHeartbeats` is a separate conversation.
- **Not changing `OpSlot` per-op timeout.** Separate tuning conversation.
- **Not extending `NSError+Pigeon.swift`'s `CBATTError` allowlist.** That's I091's actual scope; we have no evidence those gaps are firing in production. Leave I091 open as a low-priority item.
- **Not closing I091.** Different bug, different code path, different evidence. Add a cross-reference note to I091 pointing to I096.

## Decisions locked

1. **The fix is one site.** Only `CentralManagerImpl.didDisconnectPeripheral`'s `?? BlueyError.unknown.toClientPigeonError()` changes.
2. **Replacement shape is `gatt-disconnected`.** Same Dart-side type (`GattOperationDisconnectedException`) every other dead-peer path produces. No new error code, no behavioural divergence between "iOS gave us a CBError disconnect" and "iOS gave us a nil-error disconnect" — both mean "peer is gone."
3. **Construct the `PigeonError` directly, not via a `BlueyError` enum case.** `BlueyError.notConnected` would also map to `gatt-disconnected`, but its `errorDescription` is "Device not connected" — wrong tense and wrong subject for a disconnect callback. Direct construction with a clear message is the right shape for this site.
4. **Diagnostic instrumentation is reverted in the same branch.** The three `[I091-DIAG]` log calls (in `NSError+Pigeon.swift` and `CentralManagerImpl.swift`) are temporary; the fix branch starts from a fresh worktree off `main` (no diagnostic commits inherited).

## Architecture

One file changes. One block of code in that file changes.

### Before

```swift
// Drain all remaining pending completions with the disconnect error.
let pigeonError: Error = (error as NSError?)?.toPigeonError()
    ?? BlueyError.unknown.toClientPigeonError()
clearPendingCompletions(for: deviceId, error: pigeonError)
```

### After

```swift
// Drain all remaining pending completions with the disconnect error.
// iOS reports nil error for graceful disconnects (peer-initiated clean
// shutdown, or our own cancelPeripheralConnection — e.g. LifecycleClient
// declared the peer unreachable). The link is gone either way; map to
// gatt-disconnected so callers recognise the dead-peer signal.
let pigeonError: Error
if let nsError = error as? NSError {
    pigeonError = nsError.toPigeonError()
} else {
    pigeonError = PigeonError(code: "gatt-disconnected",
                              message: "Peripheral disconnected",
                              details: nil)
}
clearPendingCompletions(for: deviceId, error: pigeonError)
```

That's it. No other code changes.

## TDD — being honest about the boundary

The bug lives in Swift (`CentralManagerImpl.swift`). `bluey_ios` does **not currently have native Swift unit tests** — its testability is at the Dart level via `FakeBlueyPlatform`. So a strict Red→Green cycle on the actual bug isn't possible without building a Swift test target (out of scope for a one-line semantic fix).

We have three test boundaries to consider, only one of which is truly meaningful for this bug:

| Boundary | Catches the bug? | Cost |
|---|---|---|
| Swift unit test on `CentralManagerImpl` | Yes (directly) | High — no test target exists |
| Dart-side `FakeBlueyPlatform` test asserting a contract | No (fake replaces real platform) | Medium — fake doesn't currently drain pending ops on disconnect at all |
| On-device failure-injection stress test | Yes (end-to-end) | Already in place; manual to run |

### The honest call

**Skip the Dart-side fake-extension test.** It would assert a contract the fake doesn't currently model (pending ops draining on `simulateDisconnection`), and even if extended, it would not catch a regression in the actual Swift code — it would only catch a regression in the fake. That's contract-documentation value, not bug-prevention value, and it's not worth the fake-extension cost for this fix.

**Verification is on-device.** Re-run the failure-injection stress test after applying the Swift change; confirm:

1. No more `BlueyPlatformException(bluey-unknown)` in the disconnect cascade — only `GattOperationDisconnectedException`.
2. The example app's reconnect cubit fires (closing the I087 follow-up question).

This is the same verification pattern previously used for iOS-only fixes in this codebase (e.g. the I077 manual verification on real Android-server / iOS-client).

### What still gets a code-level guard

The Swift change includes an explanatory comment at the call site documenting *why* nil-error maps to `gatt-disconnected`. A future maintainer reading the code will see the rationale; that's the regression guard for a fix this small.

### When we'd revisit

If `bluey_ios` ever gets a Swift test target (worth doing eventually for this whole class of translation logic — `BlueyError`, `NSError+Pigeon`, `OpSlot`), a unit test for this specific call path would be a natural early test to add. Filed as a follow-up note in I096's "future work."

## Caveats

### iOS-only, but the contract is universal

The fix lives in iOS code, but `gatt-disconnected` is platform-neutral. Android's `Errors.kt` already returns `gatt-disconnected` for disconnect-class status codes; this change makes iOS symmetric with Android for the "no further error info" case.

### Ripple to the example app

The example app's reconnect cubit currently doesn't reconnect on `BlueyPlatformException(bluey-unknown)`. After this fix, every disconnect surfaces as `GattOperationDisconnectedException`, which the cubit *should* already handle. **If after the fix the reconnect still doesn't fire, the bug is in the cubit, not the library** — investigate separately under I087's umbrella.

### `didFailToConnect` parallel left alone

`didFailToConnect` has the same nil-error fall-through. No diagnostic evidence it's firing. If it ever does, file a follow-up — likely the right answer there is a new `gatt-connection-failed` code, broader change, separate decision.

## Risks and rollback

**Risks:**

- A caller somewhere actually relies on `bluey-unknown` reaching it on disconnect. Searched: nothing in the codebase keys off `bluey-unknown` semantically — it's the catch-all "we don't know" error. Risk effectively zero.
- The new error message ("Peripheral disconnected") differs from what NSError-driven paths produce ("The connection has timed out unexpectedly", etc.). Acceptable: the message is now *more* accurate for the nil-error case.

**Rollback:** revert the one-block change. No state, no migration, no schema.

## Backlog hygiene

1. **File `docs/backlog/I096-ios-nil-disconnect-error-to-unknown.md`** with the symptom, location, root cause, and fix-in once landed.
2. **I091 cross-reference:** add a note at the top of I091's symptom section: "Distinct from I096 — see that entry for the disconnect-callback nil-error path. I091 remains open for `CBATTError` allowlist gaps proper."
3. **I087 close-out:** update I087 to set `status: fixed` once on-device verification confirms the example app reconnects after the fix. Add `fixed_in: <sha>` and a one-line note: "Closed by I096 (nil-error disconnect → gatt-disconnected). The hypothesis in this entry's Notes was directionally right but pointed at the wrong code path."
4. **Backlog README:** move I087 to Fixed table; I091 stays in Open.
5. **Suggested order of attack** — drop the I087+I091 line item (no longer top-of-list).
