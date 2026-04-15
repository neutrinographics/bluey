# Client-Side Server Disconnect Detection

## Problem

When an iOS client is connected to an Android server and the Android app restarts, the iOS client never detects the disconnection. The UI continues showing "connected" and GATT operations (e.g., characteristic reads) time out.

The root cause is that the existing lifecycle heartbeat mechanism only enables **server-side** client disconnect detection. The client sends periodic write-without-response heartbeats; the server monitors for timeouts. There is no client-side mechanism for detecting a dead server because write-without-response provides no GATT-level acknowledgment — writes appear to succeed even when the server is gone.

The BLE link-layer supervision timeout should eventually trigger a CoreBluetooth `didDisconnectPeripheral` callback, but this can take 20-30+ seconds and some Android BLE stacks don't properly terminate connections on process death.

## Solution

Switch the client heartbeat from write-without-response to write-with-response. A failed write indicates the server is gone, and the client triggers a local disconnect.

## Design

### 1. Control Service Characteristic Change

The heartbeat characteristic (`b1e70002-...`) changes properties:

| Property | Before | After |
|---|---|---|
| `canWrite` | `false` | `true` |
| `canWriteWithoutResponse` | `true` | `false` |

Changed in:
- `lifecycle.dart` — characteristic definition in `buildControlService()`
- Android `GattServer.kt` — characteristic permissions (add `WRITE`, remove `WRITE_NO_RESPONSE`)
- iOS `PeripheralManagerImpl.swift` — characteristic properties (add `.write`, remove `.writeWithoutResponse`)

The server-side write handlers already send GATT responses, so no logic changes are needed on the server.

### 2. Lifecycle Extraction (Refactor)

Before adding the new failure-tracking logic, extract lifecycle code from `BlueyConnection` and `BlueyServer` into dedicated collaborators. This is a pure refactor validated by existing tests.

**File layout:**

```
bluey/lib/src/
  lifecycle.dart                          # shared kernel (constants, UUIDs, encoding)
  connection/
    lifecycle_client.dart                 # extracted from BlueyConnection
    bluey_connection.dart                 # composes LifecycleClient
  gatt_server/
    lifecycle_server.dart                 # extracted from BlueyServer
    bluey_server.dart                     # composes LifecycleServer
```

**`LifecycleClient`** (internal to Connection bounded context):
- Owns: heartbeat timer, failure counter, heartbeat char UUID, interval reading
- Public API: `start(services, writeFn)`, `stop()`, `sendDisconnectCommand(writeFn)`
- Callback: `onServerUnreachable` — fires when consecutive failures reach threshold
- Constructor takes: `maxFailedHeartbeats` (int)
- Provides: `filterControlService(services)` to remove control service from public results, `isControlService(uuid)` check

**`LifecycleServer`** (internal to GATT Server bounded context):
- Owns: per-client heartbeat timers, control service setup, control characteristic interception
- Public API: `addControlServiceIfNeeded(platform)`, `handleWriteRequest(req)` (returns bool), `handleReadRequest(req)` (returns bool), `dispose()`
- Callback: `onClientTimedOut(clientId)` — fires when heartbeat timeout expires
- Constructor takes: lifecycle interval (Duration?)

**`lifecycle.dart`** (shared kernel) stays unchanged — constants, UUIDs, encode/decode utilities.

### 3. Client-Side Failure Tracking

In `LifecycleClient`, the heartbeat write switches to write-with-response and tracks consecutive failures:

```
heartbeat write succeeds -> reset failure count to 0
heartbeat write fails -> increment failure count
  if count >= maxFailedHeartbeats -> invoke onServerUnreachable callback
  else -> wait for next heartbeat tick to retry
```

When `onServerUnreachable` fires, `BlueyConnection`:
1. Cancels the heartbeat (via `LifecycleClient.stop()`)
2. Skips the normal disconnect flow (no disconnect command — server is gone)
3. Emits `ConnectionState.disconnected` on the state stream
4. Cleans up resources

### 4. Configuration

`maxFailedHeartbeats` is a parameter on `Bluey.connect()`:

```dart
final connection = await bluey.connect(
  device,
  maxFailedHeartbeats: 3, // default: 1 (fail-fast)
);
```

This is client-side only. It does not flow to the platform layer or native code. The server's lifecycle interval (which controls the heartbeat cadence) remains configured separately via `bluey.server(lifecycleInterval: ...)`.

### 5. Timeout Behavior

The iOS ATT transaction timeout is ~30 seconds. In the worst case (Android BLE stack completely unresponsive), a heartbeat write could block for up to 30 seconds before failing. This is acceptable because:
- The common case (server process dies, BLE stack alive) returns an ATT error within milliseconds
- The current behavior is never detecting the disconnect at all
- No client-side timeout is added; we rely on the platform's ATT timeout

### 6. Testing Strategy

- **Lifecycle extraction**: Existing tests in `bluey/test/` validate the refactor — no behavior changes
- **LifecycleClient unit tests**: Test failure counting, threshold behavior, callback invocation using `FakeBlueyPlatform`
- **LifecycleServer unit tests**: Test heartbeat timeout, control service interception (extracted from existing integration tests)
- **Integration tests**: Verify end-to-end disconnect detection when heartbeat writes fail
- **Native tests**: Verify characteristic property changes on Android (`BlueyPluginTest.kt`) and iOS

### 7. What Does NOT Change

- Example app — uses default `connect()`, gets `maxFailedHeartbeats: 1` automatically
- Server-side heartbeat timeout logic — behavior unchanged, just extracted into `LifecycleServer`
- Platform interface / Pigeon definitions — no new platform methods needed
- `lifecycle.dart` shared kernel — constants and utilities unchanged
