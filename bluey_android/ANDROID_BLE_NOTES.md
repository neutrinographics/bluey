# Android BLE Implementation Notes

This document captures Android BLE quirks, limitations, and corner cases discovered during development. It serves as operational knowledge for anyone maintaining or extending the Android implementation.

## App Lifecycle and Cleanup

### Force-Kill Behavior

When an Android app is force-killed (swipe away from recents, `kill` command, or Ctrl+C on `flutter run`), **no lifecycle callbacks are invoked**. The process terminates immediately.

This means:
- `onActivityDestroyed` is NOT called
- `onDetachedFromActivity` is NOT called
- Any cleanup code in these callbacks will not run

**Implication:** There is no reliable way to clean up BLE resources when the app is force-killed. The BLE connections may persist at the OS/Bluetooth stack level until they timeout (typically 20-30 seconds) or the remote device disconnects.

**Our approach:** We clean up on normal app close via `ActivityLifecycleCallbacks.onActivityDestroyed` and `onDetachedFromActivity`. For force-kills, we accept that connections may briefly persist and rely on the remote device eventually timing out.

### Activity Lifecycle Callbacks

We register `Application.ActivityLifecycleCallbacks` for more reliable cleanup detection. This is called even in some cases where Flutter's `onDetachedFromActivity` might not be.

```kotlin
application.registerActivityLifecycleCallbacks(object : Application.ActivityLifecycleCallbacks {
    override fun onActivityDestroyed(activity: Activity) {
        // Clean up BLE resources here
    }
    // ... other callbacks
})
```

## GATT Server

### Opening the GATT Server

`BluetoothManager.openGattServer()` can sometimes return `null` on the first attempt, especially right after Bluetooth is enabled. A retry with a short delay often succeeds.

```kotlin
var server = bluetoothManager?.openGattServer(context, callback)
if (server == null) {
    Thread.sleep(100)
    server = bluetoothManager?.openGattServer(context, callback)
}
```

### cancelConnection Limitations

`BluetoothGattServer.cancelConnection(device)` only works for connections that the GATT server initiated. It does **not** reliably disconnect connections initiated by a remote central (e.g., iOS connecting to us).

When a remote device (iOS) connects to our GATT server:
- The connection is initiated by iOS, not Android
- `cancelConnection` may not trigger a disconnection
- The `onConnectionStateChange` callback with `STATE_DISCONNECTED` may never fire

**Implication:** We cannot forcibly disconnect iOS devices that connect to us. We can only close the GATT server, which will eventually cause the connection to timeout on the iOS side.

### Callback Threading

GATT server callbacks (`onConnectionStateChange`, `onCharacteristicReadRequest`, etc.) are called on a Binder thread, not the main thread. Flutter platform channels require main thread access.

Always dispatch to the main thread before calling Flutter APIs:

```kotlin
handler.post {
    flutterApi.onCentralConnected(central) {}
}
```

## iOS Interoperability

### iOS Connection Caching

iOS aggressively caches BLE connections. When an iOS device connects to an Android peripheral:

1. iOS remembers the connection
2. If the Android app closes and reopens, iOS may still think it's connected
3. When Android opens a new GATT server, iOS's cached connection immediately "reconnects"

This manifests as:
- `onConnectionStateChange` with `STATE_CONNECTED` fires immediately when opening the GATT server
- The connection appears before we even start advertising

**Our approach:** We report all connections to Flutter immediately, regardless of whether advertising has started. This allows the app to handle these "inherited" connections rather than leaving them in a broken state.

### Connection Persistence After Server Close

When Android calls `gattServer.close()`:
- The Android side cleans up its resources
- iOS may still think it's connected for 20-30 seconds
- iOS will eventually timeout and show as disconnected

There's no way to force iOS to disconnect immediately from the Android side.

## Permissions

### Android 12+ (API 31+)

Requires new Bluetooth permissions:
- `BLUETOOTH_SCAN` - for scanning
- `BLUETOOTH_CONNECT` - for connecting and GATT operations
- `BLUETOOTH_ADVERTISE` - for advertising as a peripheral

### Android 11 and below

Uses legacy permissions:
- `BLUETOOTH`
- `BLUETOOTH_ADMIN`
- `ACCESS_FINE_LOCATION` - required for scanning

## Service Addition

### Asynchronous Service Addition

`BluetoothGattServer.addService()` is asynchronous. The method returns `true` if the request was initiated, but the service isn't actually added until `onServiceAdded` callback fires.

```kotlin
pendingServiceCallback = callback
if (!server.addService(gattService)) {
    // Failed to initiate
    pendingServiceCallback = null
    callback(Result.failure(...))
}
// Wait for onServiceAdded callback
```

## Advertising

### Advertising Modes

Android supports different advertising modes with tradeoffs:
- `ADVERTISE_MODE_LOW_POWER` - 1000ms interval, best battery
- `ADVERTISE_MODE_BALANCED` - 250ms interval
- `ADVERTISE_MODE_LOW_LATENCY` - 100ms interval, fastest discovery but highest power

### Connectable Advertising

For a GATT server, advertising must be connectable:
```kotlin
AdvertiseSettings.Builder()
    .setConnectable(true)
    .build()
```

## Known Limitations

1. **No reliable force-kill cleanup** - BLE resources may leak briefly when app is force-killed
2. **Cannot force-disconnect remote centrals** - `cancelConnection` doesn't work for inbound connections
3. **iOS connection caching** - Connections may persist across app restarts
4. **GATT server open may fail** - Retry logic needed
5. **MTU negotiation** - iOS typically requests MTU of 517, but the actual MTU depends on both devices

## GATT Operation Queue

Android's `BluetoothGatt` API enforces a strict **one-operation-in-flight** rule per connection. Calling `gatt.writeCharacteristic()` while another op is outstanding returns `false` synchronously and no `BluetoothGattCallback` fires for the rejected call. Concurrent GATT ops from application code (e.g. user write + lifecycle heartbeat + iOS Service Changed re-discovery) race unless the plugin serializes them.

**Solution (Phase 2a, 2026-04-21):** `ConnectionManager` owns one `GattOpQueue` instance per active GATT connection, keyed by `deviceId`. Every GATT op — read/write characteristic, read/write descriptor, discoverServices, requestMtu, readRssi, setNotification's CCCD write — is constructed as a `GattOp` (`internal abstract class`, Command pattern) and enqueued. The queue:

- Executes ops in strict FIFO order; at most one op in flight at a time per connection
- Per-op timeout via `handler.postDelayed` (values sourced from `ConnectionManager`'s existing timeout config)
- Drain-on-disconnect: `onConnectionStateChange(STATE_DISCONNECTED)` fires `queue.drainAll(FlutterError("gatt-disconnected", ...))` so pending callbacks resolve promptly instead of dangling until `cleanup()`

### Threading model

The queue is **not thread-safe**. All state mutation happens on the main thread. `BluetoothGattCallback` methods fire on Binder IPC threads; every callback override in `ConnectionManager` posts its `queue.onComplete(...)` / `queue.drainAll(...)` invocation via `handler.post { ... }` before touching the queue. User-initiated `enqueue` calls arrive on the Pigeon dispatcher thread (main). Timeout `Runnables` fire on the `Handler`'s looper (main). Net result: the queue sees a single-threaded access pattern and needs no locks.

### What is NOT queued

- **Incoming notifications (`onCharacteristicChanged`).** Pure arrivals; they don't occupy the single-op slot at the GATT layer and must not be delayed behind user-initiated ops.
- **Connect / disconnect (`BluetoothDevice.connectGatt`, `BluetoothGatt.disconnect`).** Connection-level, not GATT.
- **Bonding (`BluetoothDevice.createBond`).** Separate Android API; does not go through `BluetoothGatt`.
- **The synchronous `gatt.setCharacteristicNotification()` call inside `setNotification`.** Purely local; doesn't hit the wire. Runs inline in `ConnectionManager.setNotification` before the CCCD descriptor write is enqueued.
- **Unsolicited `BluetoothGattCallback` events (`onConnectionStateChange`, `onServiceChanged`, `onMtuChanged` when initiated by the peer).** Not responses to our ops.

### Cross-connection concurrency

The single-op rule is **per `BluetoothGatt` instance**, not global. Two connections may process GATT ops concurrently at the HCI / link-layer level. `ConnectionManager.queues: Map<String, GattOpQueue>` assigns one queue per connection; concurrent connections' queues do not share state or interfere.

### Limitations (Phase 2a)

- **Write-without-response is serialized.** The link layer actually permits many write-without-response packets back-to-back via the credit flow-control system. Phase 2a serializes them anyway for simplicity; Phase 2c revisits this for burst-throughput workloads.
- **Discovery / MTU are queued as regular ops.** On some Android versions the OS briefly serializes these across connections at a lower level; our per-connection queue does not coordinate with the OS-level serialization, which is fine because the OS handles it transparently via the callbacks we're already awaiting.

## Activity-Aware Liveness (2026-04-22)

`LifecycleClient` no longer sends a heartbeat on every interval tick if it has recently observed other activity on the connection. Any successful GATT op (read, write, discoverServices, requestMtu, readRssi, setNotification) or incoming notification counts as activity and:

1. Resets the consecutive-failure counter.
2. Refreshes the activity-window timestamp so the next tick's `shouldSendProbe` check returns false.

Symmetric change on the server: `LifecycleServer` accepts any incoming request from a client (not just heartbeat writes) as liveness evidence via `recordActivity(clientId)`. `BlueyServer` calls this on the fallthrough path of its read/write listeners.

The heartbeat write still fires as a fallback when the connection is genuinely idle. The control service, heartbeat characteristic, and wire protocol are unchanged.

Motivation: burst workloads (e.g. the example app's stress-test suite) were starving the heartbeat into a queue-wait timeout, tripping `onServerUnreachable` mid-burst even though every preceding write had succeeded. Treating user-op success as activity prevents this false positive.

Implementation reference: `bluey/lib/src/connection/liveness_monitor.dart` owns the state machine; `LifecycleClient` delegates all policy decisions to it.

## ConnectionManager Threading + Lifecycle Contract (2026-04-27, I098)

A coherent rewrite of `ConnectionManager.kt` that bundles four previously-separate fixes into one pass: I060 (fire-and-forget disconnect), I061 (cleanup orphans pending callbacks), I062 (binder-thread map mutation), I064 (legacy dead pending-op maps). The rewrite is documented in `docs/superpowers/specs/2026-04-27-android-connection-manager-rewrite-design.md`.

### Threading invariant

> All mutation of `ConnectionManager`'s state fields happens on the main looper thread.

`BluetoothGattCallback` methods fire on Binder IPC threads. Before this fix, `onConnectionStateChange` mutated `connections`, `queues`, `pendingConnections`, and `pendingConnectionTimeouts` directly on the binder thread, while those same maps were read and written from main-thread code paths in the public op methods. Classic JVM data race; symptoms included intermittent `DeviceNotConnected` errors after a successful connect, lost connect callbacks, and inexplicable hangs.

Fix: every state-mutating branch body in `onConnectionStateChange` is wrapped in `handler.post { … }` so all mutations marshal to main. `notifyConnectionState` already internally posts; it stays outside the wrapper. The other `BluetoothGattCallback` overrides (`onCharacteristicWrite`, `onMtuChanged`, etc.) already correctly route through `handler.post { queueFor(deviceId)?.onComplete(...) }` — unchanged.

### Disconnect lifecycle

`disconnect(deviceId, callback)` no longer fires `success` synchronously. It registers the callback in `pendingDisconnects[deviceId]`, calls `gatt.disconnect()`, and schedules a 5 s fallback Runnable. The callback fires from one of three paths:

1. **`STATE_DISCONNECTED` arrives within 5 s** — expected. Cancels the fallback timer, drains the queue with `gatt-disconnected`, removes from `connections`, calls `gatt.close()`, invokes every registered callback with `Result.success(Unit)`.
2. **5 s fallback fires** — the OS callback genuinely didn't arrive. Force-closes the gatt, drains the queue, synthesizes `notifyConnectionState(DISCONNECTED)`, invokes every registered callback with `FlutterError("gatt-disconnected", "disconnect timed out…")`.
3. **`STATE_DISCONNECTED` arrives after the fallback fired** — no-op (the binder-thread post finds empty maps).

Multiple concurrent `disconnect()` calls to the same `deviceId` share-the-future: every registered callback fires when the link comes down. `disconnect(deviceId)` for an address with no entry in `connections` fires `success` synchronously (idempotent / matches iOS I044).

### Concurrent connect rejection

`connect(deviceId, …)` checks `pendingConnections.containsKey(deviceId)` BEFORE the established-connection idempotency check. A second `connect()` to the same address while the first is still in flight fires `failure(BlueyAndroidError.ConnectInProgress(deviceId))` — surfacing Dart-side as `BlueyPlatformException` (`bluey-unknown` Pigeon code).

Pre-fix, the existing `connections.containsKey(deviceId)` check fired success() as soon as `device.connectGatt()` returned and populated `connections[deviceId]`, before `STATE_CONNECTED` arrived — a false-positive success during the connecting → connected window.

### Cleanup contract

`cleanup()` (engine detach / activity destroy) now does, in order:

1. Drain `queues` with `FlutterError("gatt-disconnected", "cleanup in progress")`.
2. Fail `pendingConnections` callbacks with `BlueyAndroidError.GattConnectionCreationFailed`.
3. Succeed `pendingDisconnects` callbacks (the user asked for the link to come down; cleanup made that happen).
4. `handler.removeCallbacks` for every entry in `pendingConnectionTimeouts` and `pendingDisconnectTimeouts`.
5. `gatt.disconnect()` then `gatt.close()` for every entry in `connections`.
6. Clear all maps.

The completion-then-disconnect order matters: completing the user-facing callbacks BEFORE issuing `gatt.disconnect()` means a binder-thread `STATE_DISCONNECTED` that arrives later finds empty maps and is a no-op, rather than racing with `cleanup()` and double-firing user callbacks.

### What can and can't be unit-tested

JVM unit tests (`ConnectionManagerLifecycleTest.kt`, 15 cases) validate the lifecycle contract end-to-end with mockk. They cover: handler.post deferral of map mutations (I062), connect-mutex semantics (I098), disconnect-await + fallback paths (I060), cleanup ordering (I061).

What unit tests **cannot** prove: `mockkConstructor(Handler).post { runImmediately() }` flattens threading, so race conditions across binder ↔ main are observably absent in tests but may still be present at runtime. Manual stress-test verification on real Android (the example app's `runSoak` and `runFailureInjection` scenarios) remains the load-bearing gate for the threading invariant.

## Handle lifetime (2026-04-28, I088)

GATT attribute identity on the wire is a per-connection opaque `int handle` (`AttributeHandle` on the Dart side). UUIDs are kept on DTOs for navigation/display only.

- **Characteristic handles** come from `BluetoothGattCharacteristic.getInstanceId()`. This is the canonical identity Android exposes for a discovered characteristic and is stable across the connection.
- **Descriptor handles** are minted client-side via a per-device monotonic counter. `BluetoothGattDescriptor.getInstanceId()` exists in AOSP but is `@hide` and not part of the public SDK; we cannot rely on it. The same minting strategy is used on iOS for symmetry.
- The handle table is populated in `onServicesDiscovered`, gated on `status == GATT_SUCCESS`. Each characteristic's `getInstanceId()` and each descriptor's freshly minted id are inserted before the discovery callback resolves.
- The handle table is cleared in the `STATE_DISCONNECTED` branch of `onConnectionStateChange` AND in `onServiceChanged` (before re-discovery is kicked off). Any handle issued before either event is permanently invalid.
- Stale-handle lookup (handle non-null in the call but absent from the table) returns Pigeon error `gatt-handle-invalidated`, which the Dart side translates to `AttributeHandleInvalidatedException`. Callers must re-discover services to obtain fresh handles.
