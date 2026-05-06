---
id: I333
title: Bluetooth adapter state transitions are not observed; stale `Server`/`Connection` references are kept across `STATE_OFF`
category: bug
severity: high
platform: both
status: open
last_verified: 2026-05-06
related: []
---

## Symptom

When the user toggles Bluetooth off and back on (or when the OS turns Bluetooth off — airplane mode, low battery, recovery from a stack crash), bluey's internal state becomes silently invalid:

- The `Server` reference held by `Bluey.server()` continues to look healthy from Dart's side, but the underlying Android `BluetoothGattServer` Binder is **dead** (the OS destroyed it on `STATE_OFF`).
- Any subsequent operation against that server — `addService`, `startAdvertising`, `notifyTo`, `respondToWrite` — calls into a dead Binder proxy and throws `android.os.DeadObjectException`. The Android plugin's catch translates this into a generic `PlatformException(bluey-unknown, …)`.
- Identical pattern on the `Connection` side: stale `BluetoothGatt`/`CBPeripheral` handles don't know they've been invalidated.

Reproduced 2026-05-06 in the gossip_chat dogfood app on a Pixel-class Android with a healthy iOS peer:

1. App running, peers connected, traffic flowing normally.
2. User toggles Bluetooth off in Android Quick Settings. Peers disconnect (visible in app).
3. User toggles Bluetooth back on.
4. App's `isDiscovering` UI flag still shows true (app never learned the underlying scanner died); discovery is silently dead.
5. User taps "restart scanning". App calls `BlueyTransport.startAdvertising()` which calls `Server.addService(...)`.
6. **DeadObjectException → PlatformException(bluey-unknown)**. Stack trace from log:

```
E/BluetoothGattServer: android.os.DeadObjectException
  at android.bluetooth.IBluetoothGatt$Stub$Proxy.addService(IBluetoothGatt.java:1541)
  at android.bluetooth.BluetoothGattServer.addService(BluetoothGattServer.java:946)
  at com.neutrinographics.bluey.GattServer.addService(GattServer.kt:180)
  ...
[BLUEY-LIB] [WARN] bluey.android.gatt_server: addService: server.addService returned false
Unhandled Exception: PlatformException(bluey-unknown, Failed to add service: …)
```

The exception was unhandled in the consumer (gossip_bluey), but even if it had been caught, the consumer has no way to recover gracefully — bluey doesn't expose enough information to know "the adapter cycled, drop your state and try again" vs. "this particular service is unaddable."

## Why this is a bluey bug

Two reasons:

1. **Lifecycle observation belongs in the platform-aware library.** Android's `BluetoothAdapter.STATE_OFF` / `STATE_ON` broadcasts and iOS's `CBManagerState` callbacks are platform-specific concerns. Every consumer would otherwise have to subscribe individually and reconcile the signal with bluey's internal state — duplicating work and inviting drift between consumers' state and bluey's state.

2. **Typed errors require platform context.** Translating `DeadObjectException` into `BluetoothUnavailableException` requires knowing what the platform was doing when the exception fired. The translation is correct in bluey; in a consumer, it'd have to inspect `PlatformException.code == 'bluey-unknown'` *and* the Bluetooth adapter state separately to make the same inference.

## Proposed scope

Three sub-features, in increasing order of cost:

### A. State observation + invalidation (required)

- Subscribe to `BluetoothAdapter.STATE_*` (Android) and `CBManagerState` (iOS) at the platform plugin layer.
- On a transition to a `not-on` state (`STATE_OFF`, `STATE_TURNING_OFF`, iOS `.poweredOff`/`.unauthorized`/`.unsupported`/`.resetting`):
  - Mark all live `Server`, `Connection`, `Scanner` instances as **terminal-failed**.
  - Tear down internal references (Binder proxies, `CBPeripheral` cached state).
  - Subsequent calls against terminal-failed instances throw `BluetoothUnavailableException` immediately, without attempting the underlying platform call.
- On a transition back to `STATE_ON` (`.poweredOn` on iOS): no auto-reinitialization. Consumers must explicitly request fresh `Server`/`Connection`/`Scanner` instances. This avoids the consumer being surprised by state that lingered "around" the toggle.

### B. Public observability via `Bluey.events` (required)

Add events to the existing `Bluey.events` stream:

```dart
final class BluetoothAdapterStateChanged extends BlueyEvent {
  final BluetoothAdapterState state;
  // Whether previously-acquired Server/Connection/Scanner instances
  // are now terminal-failed (true on any transition to non-on).
  final bool invalidatedExistingInstances;
}

enum BluetoothAdapterState {
  on,            // ready
  off,           // user/OS turned it off
  turningOn,
  turningOff,
  unauthorized,  // permissions denied (iOS, or Android 12+ runtime)
  unsupported,   // device has no BLE
  resetting,     // iOS-specific transient state
  unknown,       // not yet determined at startup
}
```

Consumers subscribe and react: drop their bookkeeping, surface UI, queue retries.

### C. Typed exception hierarchy (required)

Replace `PlatformException(bluey-unknown, …)` for adapter-state-related failures with:

- `BluetoothUnavailableException` — adapter is not in the `on` state at the time of call.
- `StaleHandleException` — the operation targeted a `Server`/`Connection`/`Scanner` instance that was invalidated by a prior state transition.

Both extend the existing `BlueyException` so consumers can keep a single `on BlueyException catch (e)` site if they want to.

## Why high severity

- **Causes a UI lie**: app says "scanning" when the underlying scanner is dead. There's no way for the consumer to detect this without either (a) installing platform listeners themselves (defeats the point of the library), or (b) issuing a probe call and catching the exception (wasteful, racy).
- **Recovery requires app restart** in the current state — there's no documented "reinitialize bluey" path that consumers can call to get a fresh, valid Server. Without state observation, even if such a path existed, consumers wouldn't know when to call it.
- **Exception translation gap** — `PlatformException(bluey-unknown, "Failed to add service")` is indistinguishable from a real "this service can't be added" error, so consumers can't make smart choices.
- **Affects every consumer of bluey**, not just gossip_bluey.

## Notes

- `bluey_android` already exposes `getBluetoothState()` as a one-shot query (used by `Bluey.ensureReady`). The missing piece is the *event stream* — observing transitions, not just sampling the current state.
- iOS's `CBCentralManager`/`CBPeripheralManager` provide `centralManagerDidUpdateState` / `peripheralManagerDidUpdateState` callbacks. Both are already required by the iOS API contract; bluey's iOS plugin presumably handles them internally for its own initialization. They just need to be wired up to the public event stream.
- A consumer-side workaround pending this fix: catch the unhandled exception at the consumer's adapter (e.g. `gossip_bluey`'s `BlueyPortImpl.startAdvertising`) and surface it as a typed error. This is a backstop, not a substitute — it doesn't address the UI-lie problem (the consumer still has stale "is scanning" state because no event told it otherwise).
