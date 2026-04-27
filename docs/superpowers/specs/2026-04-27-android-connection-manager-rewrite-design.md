# Android `ConnectionManager` Rewrite — Threading + Disconnect Lifecycle Design

## Problem

`ConnectionManager.kt` accumulated four high/low-severity defects through the Phase 2a/2b iterations without ever getting a single coherent threading + lifecycle pass. The defects share the same file and overlap each other's fix logic, so piecemeal fixes risk introducing fresh races between the patches.

The four bundled issues:

- **I062 (high)** — `BluetoothGattCallback.onConnectionStateChange` mutates non-queue maps (`pendingConnectionTimeouts`, `queues`, `pendingConnections`, `connections`, the `pending*Timeouts` family) directly on the binder IPC thread. Those same maps are read and written from main-thread code paths. Classic JVM data race; symptoms include lost writes, stale reads, "device says it's connected but ops fail with `DeviceNotConnected`", and intermittent silent connect-failures.
- **I060 (high)** — `disconnect()` calls `gatt.disconnect()` and *immediately* invokes `callback(Result.success(Unit))`. The Dart-side `await connection.disconnect()` resolves before the link is actually down. Subsequent code that assumes "disconnect is complete" can see in-flight ops, an un-`close()`d gatt handle, and a state that's still `disconnecting`. iOS does this correctly via a disconnect slot; Android doesn't.
- **I061 (high)** — `cleanup()` (engine detach, activity destroy) clears `pendingConnections` without invoking the callbacks, and `clears queues` without draining them. Any `Future` waiting on an in-flight `connect()` / GATT op hangs forever.
- **I064 (low)** — The pre-Phase-2a `pendingReads`, `pendingWrites`, `pendingDescriptorReads`, `pendingDescriptorWrites`, `pendingMtuRequests`, `pendingRssiReads`, `pendingServiceDiscovery` maps and several of their corresponding `pending*Timeouts` maps have been dead since Phase 2a; the `cancelAllTimeouts` helper still iterates them on every disconnect.

A fifth concern, called out in I098 itself but not as a separate backlog ID: the existing concurrent-connect "idempotency" check at `ConnectionManager.kt:101` returns `success` as soon as `connections[deviceId]` is populated. That happens at line 135, *before* `STATE_CONNECTED` arrives — so a second `connect(deviceId)` while the first is still in flight gets a false-positive success.

## Goal

A single coherent rewrite of `ConnectionManager.kt` that establishes three invariants:

1. **Threading invariant** — every map mutation in `ConnectionManager` happens on the main looper thread. `BluetoothGattCallback` overrides marshal to `handler.post { … }` *before* touching any field. The only exception is `notifyConnectionState`, which already internally posts to main.
2. **Lifecycle contract** — `disconnect()` awaits `STATE_DISCONNECTED` (with a 5 s fallback that force-closes the gatt and synthesizes a `gatt-disconnected` error). `cleanup()` drains queues and fails pending connect callbacks before clearing maps. Concurrent `connect(deviceId)` calls are rejected when one is in flight (idempotent success only when the link is fully established).
3. **Code hygiene** — legacy `pending*` and `pending*Timeouts` maps removed, `cancelAllTimeouts` simplified or inlined, the file's surface area reduced to just the live state.

### In scope

- Wrap the body of every `when` branch in `onConnectionStateChange` (and any other `BluetoothGattCallback` override that mutates a map) in `handler.post { … }` (I062).
- Introduce `pendingDisconnects: MutableMap<String, (Result<Unit>) -> Unit>` and a 5 s fallback timer (`pendingDisconnectTimeouts`) (I060).
- Make `disconnect()` register the callback and return without invoking it; the callback fires from the `STATE_DISCONNECTED` branch or from the fallback timer.
- Drain queues and fail pending connect callbacks in `cleanup()` *before* clearing maps (I061). Pending disconnect callbacks complete with success in `cleanup()` — see Decisions below.
- Reject a second `connect(deviceId)` while the first is still in flight, returning a typed `BlueyAndroidError.ConnectInProgress(deviceId)` failure (I098 item 5).
- Remove dead legacy maps (`pendingReads`, `pendingWrites`, `pendingDescriptorReads`, `pendingDescriptorWrites`, `pendingMtuRequests`, `pendingRssiReads`, `pendingServiceDiscovery`, plus the `pendingReadTimeouts`, `pendingWriteTimeouts`, `pendingDescriptorReadTimeouts`, `pendingDescriptorWriteTimeouts` keyed-by-`deviceId:uuid` maps; verify and remove `pendingServiceDiscoveryTimeouts`, `pendingMtuTimeouts`, `pendingRssiTimeouts` if unused) (I064). Inline `cancelAllTimeouts` into the `STATE_DISCONNECTED` branch since after the cull it shrinks to a single line.
- New JVM unit tests in `ConnectionManagerLifecycleTest.kt` covering each of the new invariants (see *Testing*).
- Document the new threading + lifecycle contract in `ANDROID_BLE_NOTES.md`.

### Out of scope

- **No Pigeon changes.** The plugin's wire surface is unchanged; this is a Kotlin-internal rewrite.
- **No Dart-side changes.** No platform-interface changes, no domain-layer changes, no example-app changes.
- **No iOS changes.** CoreBluetooth's `disconnectPeripheral` already serializes correctly via the existing iOS implementation.
- **No new GATT op types.** `GattOpQueue` and the `GattOp` hierarchy are untouched.
- **No bond / PHY / connection-parameter plumbing.** That is I035 Stage B, separate work.
- **No reworking of the timeout-during-connect path.** The existing `pendingConnectionTimeouts` mechanism is preserved as-is, just relocated inside `handler.post { … }` for thread safety.
- **No changes to the connect-permission check** (`hasRequiredPermissions()`), the `BluetoothAdapter` null-check, or the `getRemoteDevice` / `connectGatt` fallback paths. Those work today.

## Architecture

### Threading model — the new invariant

> **All mutation of `ConnectionManager`'s state fields happens on the main looper thread.** `BluetoothGattCallback` methods, which fire on Binder IPC threads, marshal to `handler.post { … }` *before* touching any state. Public methods (`connect`, `disconnect`, GATT ops, `cleanup`) are dispatched on the main thread by Pigeon.

This extends the existing single-thread invariant from `GattOpQueue` (Phase 2a) to `ConnectionManager`'s own state. Phase 2a covered queue mutation; this rewrite covers the rest of the file. After this, no field in `ConnectionManager` requires synchronization — every read and write is on the main thread.

`notifyConnectionState` already internally posts to main via `handler.post { flutterApi.onConnectionStateChanged(event) {} }`, so it can stay outside the wrapper. Calls that *only* invoke `notifyConnectionState` and don't touch maps don't need to be wrapped a second time.

`Handler.post` and `Handler.removeCallbacks` are themselves thread-safe — fine to call from binder threads. Everything else (map access, completer invocation, queue creation) goes inside the post.

### Lifecycle contract

```
connect(deviceId, config, callback)
  ┌─ on main thread (Pigeon dispatcher)
  ├─ if !hasRequiredPermissions(): callback(failure(PermissionDenied))
  ├─ if pendingConnections[deviceId] != null:
  │     callback(failure(ConnectInProgress(deviceId)))    // NEW: reject concurrent
  ├─ if connections[deviceId] != null:
  │     callback(success(deviceId))                       // already established (idempotent)
  ├─ get adapter / device (existing logic)
  ├─ notifyConnectionState(CONNECTING)
  ├─ gatt = device.connectGatt(...)
  ├─ if gatt == null: callback(failure(GattConnectionCreationFailed))
  ├─ connections[deviceId] = gatt
  ├─ pendingConnections[deviceId] = callback
  ├─ optionally schedule pendingConnectionTimeouts[deviceId] (existing logic, unchanged)
  └─ return; callback fires from STATE_CONNECTED or from the timeout

disconnect(deviceId, callback)
  ┌─ on main thread (Pigeon dispatcher)
  ├─ if connections[deviceId] == null: callback(success); return    // NEW: early-success
  ├─ if pendingDisconnects[deviceId] != null:
  │     [composed: see Decision 3]                                  // see below
  ├─ pendingDisconnects[deviceId] = callback
  ├─ notifyConnectionState(DISCONNECTING)
  ├─ try { gatt.disconnect() } catch (SecurityException) { … }
  ├─ schedule pendingDisconnectTimeouts[deviceId] = Runnable {
  │     if pendingDisconnects.remove(deviceId) is non-null:
  │         try { gatt.close() } catch (…) { }
  │         connections.remove(deviceId)?.also { it.close() }
  │         queues.remove(deviceId)?.drainAll(gatt-disconnected)
  │         notifyConnectionState(DISCONNECTED)
  │         callback(failure(gatt-disconnected, "disconnect timed out"))
  │   }, delay = 5_000ms
  └─ return; callback fires from STATE_DISCONNECTED or from the fallback

onConnectionStateChange(gatt, status, newState)         // binder thread
  ┌─ notifyConnectionState(<state>)                     // already main-posting
  └─ handler.post {                                     // ALL state mutation here
      when (newState):
        STATE_CONNECTING   → no-op
        STATE_CONNECTED    →
          pendingConnectionTimeouts.remove(deviceId)?.let { handler.removeCallbacks(it) }
          queues[deviceId] = GattOpQueue(gatt, handler)
          pendingConnections.remove(deviceId)?.invoke(success(deviceId))
        STATE_DISCONNECTING → no-op
        STATE_DISCONNECTED →
          pendingConnectionTimeouts.remove(deviceId)?.let { handler.removeCallbacks(it) }
          pendingDisconnectTimeouts.remove(deviceId)?.let { handler.removeCallbacks(it) }
          queues.remove(deviceId)?.drainAll(gatt-disconnected)
          // pending connect failed: surface status as gatt-status-failed or generic
          pendingConnections.remove(deviceId)?.invoke(failure(<connect-failed>))
          // pending disconnect succeeded: this is the expected path
          pendingDisconnects.remove(deviceId)?.invoke(success)
          connections.remove(deviceId)
          try { gatt.close() } catch (…) { }
    }

cleanup()                                                // engine detach / activity destroy
  ┌─ on main thread (lifecycle callback)
  ├─ for ((_, queue) in queues): queue.drainAll(gatt-disconnected, "cleanup in progress")
  ├─ queues.clear()
  ├─ for ((_, cb) in pendingConnections.toList()): cb(failure(<cleanup error>))
  ├─ pendingConnections.clear()
  ├─ for ((_, cb) in pendingDisconnects.toList()): cb(success)            // see Decision 2
  ├─ pendingDisconnects.clear()
  ├─ pendingConnectionTimeouts.values.forEach { handler.removeCallbacks(it) }
  ├─ pendingConnectionTimeouts.clear()
  ├─ pendingDisconnectTimeouts.values.forEach { handler.removeCallbacks(it) }
  ├─ pendingDisconnectTimeouts.clear()
  └─ for ((_, gatt) in connections.toList()): try { gatt.disconnect(); gatt.close() } catch (…) { }
     connections.clear()
```

### Why "drain queues *before* failing pending connects" in cleanup

The order matters because of binder-thread `STATE_DISCONNECTED` callbacks that may already be in flight when `cleanup()` runs. By the time `cleanup()` calls `gatt.disconnect()` on each connection, the OS may schedule a `STATE_DISCONNECTED` to fire later (potentially after `cleanup()` returns). That callback's posted runnable will hit empty maps and become a no-op — which is correct, because `cleanup()` already failed the callbacks. If we did it the other way (`gatt.disconnect()` first, then drain), `STATE_DISCONNECTED` could race with `cleanup()`'s drain and double-fire user callbacks.

### Connect-in-flight rejection: error type

A new `BlueyAndroidError`:

```kotlin
data class ConnectInProgress(val deviceId: String) :
    BlueyAndroidError("Connect already in progress for $deviceId")
```

Translated by `Errors.kt:toClientFlutterError()` to `FlutterError("bluey-unknown", message, null)` (the catch-all for `BlueyAndroidError` cases without a more specific code). That means the Dart-side surfaces it as `BlueyPlatformException` — which is the right shape for "you called the API wrong." If a future need arises for a dedicated Pigeon code, that's a follow-up; the minimal change here is one `data class` and a one-line addition to `Errors.kt`.

## Components

### Files modified

- `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/ConnectionManager.kt` — the rewrite.
- `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/BlueyAndroidError.kt` — add `ConnectInProgress(deviceId: String)`.
- `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/Errors.kt` — extend the `is BlueyAndroidError` catch-all path's pattern match implicitly (no edit if `bluey-unknown` is the right code; if we choose a dedicated code, one extra branch).
- `bluey_android/ANDROID_BLE_NOTES.md` — append a section documenting the threading invariant and the disconnect-with-fallback contract.

### Files created

- `bluey_android/android/src/test/kotlin/com/neutrinographics/bluey/ConnectionManagerLifecycleTest.kt` — JVM unit tests (see *Testing*).

### Field changes inside `ConnectionManager`

**Removed (I064):**
- `pendingReads`, `pendingWrites`, `pendingDescriptorReads`, `pendingDescriptorWrites` (deviceId:uuid keyed)
- `pendingMtuRequests`, `pendingRssiReads`, `pendingServiceDiscovery` (deviceId keyed)
- `pendingReadTimeouts`, `pendingWriteTimeouts`, `pendingDescriptorReadTimeouts`, `pendingDescriptorWriteTimeouts`
- `pendingServiceDiscoveryTimeouts`, `pendingMtuTimeouts`, `pendingRssiTimeouts` (verify dead before removing — these are keyed by `deviceId` only, never written by Phase 2a code, but the Phase 2a comment hedges; the rewrite confirms or removes)
- `cancelAllTimeouts()` helper and `cancelTimersWithPrefix()` helper

**Kept:**
- `connections: MutableMap<String, BluetoothGatt>`
- `queues: MutableMap<String, GattOpQueue>`
- `pendingConnections: MutableMap<String, (Result<String>) -> Unit>`
- `pendingConnectionTimeouts: MutableMap<String, Runnable>`
- `handler: Handler` (main looper)
- All configurable timeout fields (`discoverServicesTimeoutMs`, etc.)

**Added:**
- `pendingDisconnects: MutableMap<String, (Result<Unit>) -> Unit>`
- `pendingDisconnectTimeouts: MutableMap<String, Runnable>`
- `private companion object` constant `DISCONNECT_FALLBACK_MS = 5_000L`

### Method-by-method delta

| Method | Change |
|---|---|
| `connect()` | Add `pendingConnections[deviceId] != null` guard before the existing `connections.containsKey(deviceId)` check. |
| `disconnect()` | Replace the synchronous `callback(success)` with: register `pendingDisconnects[deviceId]`, call `gatt.disconnect()`, schedule fallback timer. Early-success when `connections[deviceId] == null`. |
| `cleanup()` | Drain queues, fail pending connects, succeed pending disconnects, cancel timers, then disconnect/close. (See data flow above.) |
| `onConnectionStateChange` | Wrap each `when`-branch body in `handler.post { … }`. Inline the now-trivial `cancelAllTimeouts(deviceId)` call. Remove the now-dead "Legacy map cleanup" comment + line. |
| `onServicesDiscovered`, `onCharacteristicRead/Write`, `onDescriptorRead/Write`, `onMtuChanged`, `onReadRemoteRssi` | Unchanged — these already correctly route through `handler.post { queueFor(deviceId)?.onComplete(...) }`. |
| `onCharacteristicChanged`, `onServiceChanged` | Unchanged — already use `handler.post`. |
| Other public methods (`discoverServices`, `read/writeCharacteristic`, `read/writeDescriptor`, `requestMtu`, `readRssi`, `setNotification`) | Unchanged — they validate, look up, then enqueue on the queue. The validation reads `connections[deviceId]` which is now guaranteed only mutated on main; since these methods themselves run on main, no race. |

### `Errors.kt`

If we choose `bluey-unknown` for `ConnectInProgress`, no edit is needed — the `is BlueyAndroidError` final branch handles it. The `data class` itself only requires:

```kotlin
data class ConnectInProgress(val deviceId: String) :
    BlueyAndroidError("Connect already in progress for $deviceId")
```

If we want a dedicated Pigeon code (`bluey-connect-in-progress`?), add one branch above the catch-all. **Default decision: use `bluey-unknown` for now**, since calling `connect()` twice is a programming error and a generic platform exception is the right shape. Easy to add a dedicated code later if real callers need to discriminate.

## Data flow

### Successful connect

```
caller → connect(addr, config, cb)
       → main: pendingConnections[addr] = cb
       → main: device.connectGatt(...) returns gatt
       → main: connections[addr] = gatt
       → main: maybe pendingConnectionTimeouts[addr] = Runnable
       → return
   …radio link establishes…
   onConnectionStateChange(STATE_CONNECTED)  [binder thread]
       → notifyConnectionState(CONNECTED)    [posts itself]
       → handler.post {
            pendingConnectionTimeouts.remove(addr)?.let { removeCallbacks(it) }
            queues[addr] = GattOpQueue(gatt, handler)
            pendingConnections.remove(addr)?.invoke(success(addr))    ← fires user cb
         }
```

### Successful disconnect

```
caller → disconnect(addr, cb)
       → main: pendingDisconnects[addr] = cb
       → main: notifyConnectionState(DISCONNECTING)
       → main: gatt.disconnect()
       → main: pendingDisconnectTimeouts[addr] = Runnable {fallback}
       → return
   …radio link tears down…
   onConnectionStateChange(STATE_DISCONNECTED)  [binder thread]
       → notifyConnectionState(DISCONNECTED)    [posts itself]
       → handler.post {
            pendingDisconnectTimeouts.remove(addr)?.let { removeCallbacks(it) }
            queues.remove(addr)?.drainAll(gatt-disconnected)        ← drain any in-flight ops
            pendingConnections.remove(addr)?.invoke(failure(...))   ← unlikely path here
            pendingDisconnects.remove(addr)?.invoke(success)        ← fires user cb
            connections.remove(addr)
            gatt.close()
         }
```

### Disconnect with fallback

```
caller → disconnect(addr, cb)        … same as above through gatt.disconnect() …
       → return
   …5 seconds elapse, STATE_DISCONNECTED never arrives…
   pendingDisconnectTimeouts[addr].run()     [main thread; handler.postDelayed callback]
       → if pendingDisconnects.remove(addr) returned non-null:
          gatt.close()                                              ← force-close
          connections.remove(addr)
          queues.remove(addr)?.drainAll(gatt-disconnected)
          notifyConnectionState(DISCONNECTED)                       ← synthesize state event
          cb(failure(FlutterError("gatt-disconnected", "disconnect timed out", null)))
```

If `STATE_DISCONNECTED` *does* arrive after the fallback fired, the `pendingDisconnects.remove(addr)` inside the binder-thread post returns `null` (the fallback already removed it) — the late callback is a no-op. Same for the queue and connections maps; they're already cleared.

## Error handling

| Scenario | Outcome |
|---|---|
| `connect()` while another connect to same addr is in flight | `BlueyAndroidError.ConnectInProgress(addr)` → `bluey-unknown` Pigeon code → `BlueyPlatformException` Dart-side |
| `connect()` while addr is already connected | `Result.success(addr)` (idempotent) |
| `disconnect()` while addr is not connected | `Result.success(Unit)` (idempotent / no-op) |
| `disconnect()` while another disconnect to same addr is in flight | See Decision 3 below |
| `disconnect()` STATE_DISCONNECTED arrives within 5 s | `Result.success(Unit)` |
| `disconnect()` STATE_DISCONNECTED never arrives | After 5 s: `gatt.close()` called, `gatt-disconnected` failure to caller, `notifyConnectionState(DISCONNECTED)` synthesized |
| `cleanup()` with pending connect | `Result.failure(…)` — see Decision 2 |
| `cleanup()` with pending disconnect | `Result.success(Unit)` — see Decision 2 |
| `cleanup()` with in-flight GATT op | Existing `queue.drainAll(gatt-disconnected)` — unchanged |

## Testing

The bundled issues' fixes manipulate timing-sensitive state. JVM unit tests using mockk + the existing `ConnectionManagerQueueTest.kt` pattern can validate logic & ordering, but they **cannot prove** the threading races are fixed — `handler.post { run immediately }` flattens threading. Tests are necessary but not sufficient. **Manual on-device verification with the example app's stress-test scenarios is the load-bearing gate** before declaring I098 done.

### New test file: `ConnectionManagerLifecycleTest.kt`

Same setup pattern as `ConnectionManagerQueueTest.kt`: reflective `SDK_INT` pin to TIRAMISU, `mockkStatic(ContextCompat)` for permission grant, `mockkConstructor(Handler)` to run posts immediately and capture `postDelayed` runnables, `mockk(relaxed = true)` for `BluetoothGatt` / `BluetoothDevice` / `BlueyFlutterApi`, capturing the `BluetoothGattCallback` from `connectGatt`.

Test cases:

#### Connect mutex (I098 item 5)

1. `connect when no in-flight or established connection succeeds normally` — already covered by setup in existing tests; restate as explicit lifecycle test.
2. `second connect to same deviceId while first is in-flight returns ConnectInProgress` — call `connect(addr)` twice without firing `STATE_CONNECTED` between; second callback receives `BlueyAndroidError.ConnectInProgress`.
3. `second connect after first established returns idempotent success` — fire `STATE_CONNECTED` for the first; second `connect(addr)` returns `Result.success(addr)` immediately without invoking `connectGatt` again.
4. `connect to a different deviceId while first is in-flight succeeds independently` — verify the mutex is per-deviceId, not global.

#### Disconnect lifecycle (I060)

5. `disconnect does not invoke callback synchronously` — register a callback; verify it has NOT fired immediately after `disconnect()` returns. Then fire `STATE_DISCONNECTED`; verify callback fires now with success.
6. `disconnect with no connection invokes callback immediately with success` — call `disconnect(addr)` for an `addr` not in `connections`; callback fires synchronously with `Result.success(Unit)`.
7. `disconnect fallback fires gatt-disconnected after 5s if STATE_DISCONNECTED never arrives` — capture the postDelayed runnable, run it manually; verify `gatt.close()` called, callback receives `FlutterError("gatt-disconnected", …)`, `connections.remove(addr)` happened, queue drained.
8. `late STATE_DISCONNECTED after fallback is a no-op` — fire the fallback runnable, then fire `STATE_DISCONNECTED`; the user callback fires only once.
9. `STATE_DISCONNECTED cancels the disconnect fallback timer` — verify `handler.removeCallbacks` called on the fallback runnable when the OS callback arrives within the window.

#### Cleanup (I061)

10. `cleanup fails pending connect callbacks with a typed error` — start a connect, do not fire `STATE_CONNECTED`, call `cleanup()`; verify the connect callback fires with a failure.
11. `cleanup completes pending disconnect callbacks with success` — start a disconnect, do not fire `STATE_DISCONNECTED`, call `cleanup()`; verify the disconnect callback fires with `Result.success(Unit)`.
12. `cleanup drains queue ops with gatt-disconnected before clearing connections` — enqueue a write while connected, call `cleanup()`; verify the write's callback receives `FlutterError("gatt-disconnected", "cleanup in progress", null)`.
13. `cleanup cancels pending connection and disconnect timeout runnables` — pre-populate both timeout maps, call `cleanup()`; verify `handler.removeCallbacks` was called for each.

#### Threading (I062)

14. `STATE_CONNECTED state mutations occur inside handler.post` — verify the queue creation, pendingConnectionTimeouts removal, and pendingConnections invocation all happen via `handler.post` (visible because the mocked `Handler.post` runs synchronously, so before the mock-post is called, the maps are unchanged; after, they are). Use a custom `mockHandler.post` that defers execution to assert this.
15. `STATE_DISCONNECTED state mutations occur inside handler.post` — same pattern.

#### Dead-code removal (I064)

16. (No new test — verified by deletion. The existing `ConnectionManagerQueueTest`'s drain test still passes after the legacy maps are removed.)

### Existing tests must continue to pass

- All `ConnectionManagerQueueTest.kt` tests (six) remain unmodified and pass.
- All `bluey_android` Dart-side tests (69) remain unmodified and pass.
- All `bluey_platform_interface` tests (32) remain unmodified and pass.
- All `bluey` tests (638) remain unmodified and pass.
- All `bluey_ios` tests (83) remain unmodified and pass.

### Manual verification (load-bearing)

Run the example app on a real Android device with the known stress-test scenarios:

1. **Soak (`runSoak`)** — connect/disconnect cycles; verify no `"Failed to <op>"` transient errors that would indicate a torn-down callback raced with an OS callback.
2. **Failure injection (`runFailureInjection`)** — tear down the iOS server mid-op; Android client should observe `gatt-disconnected` callbacks for in-flight ops, the `connection.disconnect()` future should resolve cleanly within 5 s.
3. **Multi-connect race** — start two `bluey.connect(addr)` calls to the same address from the example app's debug menu (or a small synthetic test driver); verify the second observes a typed `BlueyPlatformException` or `Future` failure, not a silent success.
4. **App backgrounding mid-connect** — initiate `bluey.connect()`, immediately background the app; verify the resolution doesn't hang past `cleanup()`'s execution. Confirm the `Future` resolves with a failure.

The user (Joel) will run these manually after the JVM tests pass; this is the contract that the rewrite is correct in production. Until those pass, I098 remains open even if `./gradlew test` is green.

## Migration plan (commit sequence)

Each commit leaves the suite green and follows TDD. Commits are sized for review.

1. **`refactor(bluey_android): inline cancelAllTimeouts; remove dead pending-op maps (I064)`**
   *Pure cleanup.* No behavioural change. Delete the seven legacy maps, the four keyed-by-`deviceId:uuid` timeout maps, the `cancelAllTimeouts` and `cancelTimersWithPrefix` helpers. Replace the `cancelAllTimeouts(deviceId)` call inside `STATE_DISCONNECTED` with the single `pendingConnectionTimeouts.remove(deviceId)?.let { handler.removeCallbacks(it) }` line. Verify `pendingServiceDiscoveryTimeouts`, `pendingMtuTimeouts`, `pendingRssiTimeouts` are unused before removing them. Existing tests pass unchanged.

2. **`test(bluey_android): add ConnectionManagerLifecycleTest with failing threading tests (I062)`**
   *RED.* Tests for "STATE_CONNECTED state mutations occur inside handler.post" and "STATE_DISCONNECTED state mutations occur inside handler.post". Fails because the current code mutates outside the post.

3. **`refactor(bluey_android): wrap onConnectionStateChange branches in handler.post (I062)`**
   *GREEN for #2.* Wrap each non-no-op branch body in `handler.post`. Existing `ConnectionManagerQueueTest` tests still pass (the mocked `handler.post` runs synchronously, so observable order is the same; the threading invariant is now correct under real execution).

4. **`test(bluey_android): add failing connect-mutex tests (I098 item 5)`**
   *RED.* The four "connect mutex" tests above. Fails because the current `connect()` returns false-success on the second call.

5. **`feat(bluey_android): reject concurrent connect with ConnectInProgress (I098)`**
   *GREEN for #4.* Add `BlueyAndroidError.ConnectInProgress(deviceId: String)` to `BlueyAndroidError.kt`. Add the `pendingConnections.containsKey(deviceId)` guard in `connect()`. Existing tests pass; new tests pass.

6. **`test(bluey_android): add failing disconnect-lifecycle tests (I060)`**
   *RED.* The five "disconnect lifecycle" tests above. Fails because the current `disconnect()` invokes the callback synchronously and has no fallback.

7. **`feat(bluey_android): make disconnect() await STATE_DISCONNECTED with 5s fallback (I060)`**
   *GREEN for #6.* Add `pendingDisconnects` and `pendingDisconnectTimeouts` fields. Rewrite `disconnect()` per the lifecycle contract above. Update `STATE_DISCONNECTED` to invoke `pendingDisconnects.remove(deviceId)?.invoke(success)` and to cancel the disconnect fallback timer. Existing tests pass; new tests pass.

8. **`test(bluey_android): add failing cleanup-orphan tests (I061)`**
   *RED.* The four "cleanup" tests above. Fails because current `cleanup()` clears maps without invoking callbacks or draining queues.

9. **`feat(bluey_android): drain queues and fail pending callbacks in cleanup (I061)`**
   *GREEN for #8.* Rewrite `cleanup()` per the lifecycle contract above. Existing tests pass; new tests pass.

10. **`docs(bluey_android): document threading invariant + disconnect fallback in ANDROID_BLE_NOTES.md`**
    Append a section: "ConnectionManager threading + lifecycle contract" — single-thread invariant, what runs on which thread, the 5 s disconnect fallback contract, the connect-mutex semantics. Reference `docs/superpowers/specs/2026-04-27-android-connection-manager-rewrite-design.md` and the four backlog IDs (I060, I061, I062, I064, I098).

11. **`chore(backlog): mark I060 / I061 / I062 / I064 / I098 fixed`**
    Update `docs/backlog/I060.md`, `I061.md`, `I062.md`, `I064.md`, `I098.md` — set `status: fixed`, fill `fixed_in: <commit-sha>`, update `last_verified`. Update `docs/backlog/README.md` Tier 2 ordering to reflect the closure (move the Tier 2 list to start at I003).

The order — **threading first, mutex second, disconnect third, cleanup fourth** — is deliberate. Threading is the invariant the others rely on (mutex check reads `pendingConnections`; disconnect adds new map; cleanup iterates all maps). Doing it last would risk fixing a race in dead state and missing a real one.

## Decisions

### Decision 1: disconnect fallback duration

**Decided: 5 seconds.** Confirmed by user.

### Decision 2: cleanup() outcome for pending disconnect callbacks

When `cleanup()` runs and a `disconnect(addr)` is in flight, what does the user's awaiting `Future` see?

- **Option A — success.** The user asked for the link to come down; cleanup forced the link down; they got what they asked for.
- **Option B — failure with a typed error.** The disconnect didn't complete via the normal path; surface that.

**Recommendation: Option A (success).** Rationale: the user's intent (`disconnect()`) was satisfied semantically. A `Future` that completes with success when the link is verified down is contract-honest. Failing it would force callers to write `try / catch` around every `disconnect()` to handle a case that's a no-op for them. Pending *connect* callbacks correctly fail because the connect didn't happen; pending *disconnect* callbacks correctly succeed because the disconnect did happen, just by force.

### Decision 3: disconnect() while another disconnect is in flight

What does a second `disconnect(addr)` call do when `pendingDisconnects[addr]` is non-null?

- **Option A — idempotent share-the-future.** Both callbacks fire when `STATE_DISCONNECTED` arrives (or the fallback fires).
- **Option B — reject with a typed error.** Mirrors connect-in-progress.
- **Option C — no-op success on the second call.** Returns success immediately for the duplicate.

**Recommendation: Option A (idempotent).** Rationale: unlike `connect()`, double-`disconnect()` is benign — both callers want the same outcome. Surfacing it as an error is unhelpful. The implementation: when `pendingDisconnects[addr]` is non-null, *append* the second callback to a list (or wrap as a multi-callback) so `STATE_DISCONNECTED` fires both. Simplest impl: store `pendingDisconnects[addr]: MutableList<(Result<Unit>) -> Unit>`. Slight complication; weighed against the alternative of failing benign duplicates, it's worth it.

If the user prefers Option C (simpler, just-return-success on duplicate), say so and the spec changes a few lines.

### Decision 4: `ConnectInProgress` Pigeon code

**Decided: `bluey-unknown` (the catch-all).** Rationale: calling `connect()` twice on the same device while the first is in flight is a calling-code bug; surfacing it as a generic platform exception is the right shape, and adding a dedicated Pigeon code is premature until a real consumer needs to discriminate.

## Success criteria

- All 638 + 69 + 83 + 32 = 822 existing tests pass unchanged.
- ~15 new JVM tests in `ConnectionManagerLifecycleTest.kt`, all passing.
- `flutter analyze` clean across all four packages.
- `./gradlew test` clean for `bluey_android/android`.
- Manual verification on real Android device against the four scenarios above passes (load-bearing gate; not satisfied by JVM tests alone).
- `docs/backlog/I060.md`, `I061.md`, `I062.md`, `I064.md`, `I098.md` all marked `status: fixed`.
- `docs/backlog/README.md` Tier 2 list updated.

## Open questions

- **Decision 2** (cleanup with pending disconnect): user confirmation that Option A (success) is preferred over Option B (typed failure).
- **Decision 3** (concurrent disconnect): user confirmation that Option A (idempotent share-the-future) is preferred over Option C (just-return-success on duplicate). Option A costs a `MutableList` per `pendingDisconnects` entry; Option C is simpler but discards the second callback's existence.
- **Pigeon code for `ConnectInProgress`**: confirmation that `bluey-unknown` is acceptable, vs. a new dedicated code.
- **`pendingServiceDiscoveryTimeouts` / `pendingMtuTimeouts` / `pendingRssiTimeouts` removal**: these are flagged by the I064 entry as "actually dead too, double-check before deleting." Verification is part of step 1 of the migration plan; if any of them turns out to be live, document why and keep it.
