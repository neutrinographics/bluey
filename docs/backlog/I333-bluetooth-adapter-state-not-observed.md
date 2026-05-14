---
id: I333
title: Live `Server`/`Connection`/`Scanner` instances are not invalidated when the adapter cycles off
category: bug
severity: medium
platform: both
status: open
last_verified: 2026-05-06
related: []
---

## What's already in place (verified 2026-05-06)

Several pieces this ticket originally claimed were missing already exist. This section is here so anyone picking up the ticket doesn't rebuild what's already there.

- **Adapter state observation, both platforms.** Android registers a `BluetoothAdapter.ACTION_STATE_CHANGED` `BroadcastReceiver` in `BlueyPlugin.kt:711` and maps `STATE_OFF` / `STATE_TURNING_OFF` / `STATE_ON` to `BluetoothStateDto`. iOS implements `centralManagerDidUpdateState` / `peripheralManagerDidUpdateState` in `CentralManagerDelegate.swift` and `PeripheralManagerDelegate.swift`. Both fire `flutterApi.onStateChanged(...)` up to Dart.
- **Public Dart surface.** `Bluey.stateStream: Stream<BluetoothState>` (`bluey/lib/src/bluey.dart:214`) is a broadcast stream of every adapter transition. `Bluey.currentState` (line 209) returns the last-known value. `Bluey.state` returns a one-shot `Future<BluetoothState>`. `Bluey.ensureReady()` (line 276–293) throws `BluetoothUnavailableException` / `BluetoothDisabledException` / `PermissionDeniedException` based on a one-shot probe.
- **Typed exceptions.** `BluetoothUnavailableException` (`bluey_platform_interface/lib/src/exceptions.dart:20`) and `BluetoothDisabledException` (line 29) already exist and are thrown by `Bluey.ensureReady`.

What does **not** exist:

- Internal invalidation of live `Server` / `Connection` / `Scanner` instances when `stateStream` emits a non-`on` value. No code path in `BlueyServer`, `BlueyConnection`, or the scanner subscribes to `stateStream` for cleanup.
- Translation of `DeadObjectException` (Android) or the equivalent iOS post-`poweredOff` failure mode into a typed `BluetoothUnavailableException`. Both currently surface as `PlatformException(bluey-unknown, …)`.

## Symptom

When the user toggles Bluetooth off and back on (or when the OS turns it off — airplane mode, low battery, recovery from a stack crash), bluey's internal state becomes silently invalid:

- The `Server` reference held by `Bluey.server()` continues to look healthy from Dart's side, but the underlying Android `BluetoothGattServer` Binder is **dead** (the OS destroyed it on `STATE_OFF`).
- Any subsequent operation against that server — `addService`, `startAdvertising`, `notifyTo`, `respondToWrite` — calls into a dead Binder proxy and throws `android.os.DeadObjectException`. The Android plugin's catch translates this into a generic `PlatformException(bluey-unknown, …)`.
- Identical pattern on the `Connection` side: stale `BluetoothGatt` / `CBPeripheral` handles don't know they've been invalidated.

A consumer can already subscribe to `Bluey.stateStream` and react when the adapter goes off — but bluey doesn't do this internally, so the consumer must either (a) subscribe and proactively drop their bookkeeping, or (b) catch opaque `PlatformException(bluey-unknown)` after the fact. Neither is great.

Reproduced 2026-05-06 in the gossip_chat dogfood app on a Pixel-class Android with a healthy iOS peer:

1. App running, peers connected, traffic flowing normally.
2. User toggles Bluetooth off in Android Quick Settings. Peers disconnect (visible in app).
3. User toggles Bluetooth back on.
4. App's `isDiscovering` UI flag still shows true (consumer never subscribed to `stateStream`); discovery is silently dead.
5. User taps "restart scanning". App calls `BlueyTransport.startAdvertising()` which calls `Server.addService(...)`.
6. **DeadObjectException → PlatformException(bluey-unknown)**:

```
E/BluetoothGattServer: android.os.DeadObjectException
  at android.bluetooth.IBluetoothGatt$Stub$Proxy.addService(IBluetoothGatt.java:1541)
  at android.bluetooth.BluetoothGattServer.addService(BluetoothGattServer.java:946)
  at com.neutrinographics.bluey.GattServer.addService(GattServer.kt:180)
  ...
[BLUEY-LIB] [WARN] bluey.android.gatt_server: addService: server.addService returned false
Unhandled Exception: PlatformException(bluey-unknown, Failed to add service: …)
```

The exception is opaque. Even if a consumer catches it, they have no way to distinguish "the adapter cycled" from "this particular service is unaddable." Without bluey-side invalidation they're forced to inspect `PlatformException.code == 'bluey-unknown'` *and* the adapter state separately to make the inference.

## Why this is a bluey bug (not a consumer bug)

1. **Each consumer would otherwise re-subscribe to `stateStream` and reconcile their bookkeeping with bluey's internal state.** Duplicating work; inviting drift between consumers' state and bluey's state. Bluey already has the signal — it just doesn't act on it.
2. **Translating `DeadObjectException` into `BluetoothUnavailableException` requires platform context.** That translation is correct in bluey's Android plugin; in a consumer, it'd have to inspect `PlatformException.code` *and* the adapter state to make the same inference.

## Proposed scope

### A. Internal invalidation on stateStream-off (required)

Subscribe to `Bluey.stateStream` (or directly to the platform's state-change events) inside `BlueyServer`, `BlueyConnection`, and the scanner. On any transition out of `BluetoothState.on`:

- Mark the instance as **terminal-failed**.
- Tear down internal references (Binder proxies, `CBPeripheral` cached state, native handle maps).
- Subsequent calls against terminal-failed instances throw `BluetoothUnavailableException` (existing exception type) immediately, without attempting the underlying platform call.

On a transition back to `BluetoothState.on`: no auto-reinitialization. Consumers must explicitly request fresh `Server`/`Connection`/`Scanner` instances. Auto-reinitialization is a footgun (consumers might not realize state was lost).

### B. Translate `DeadObjectException` → `BluetoothUnavailableException` (required)

Backstop for any race that slips past A's pre-emptive invalidation. In `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/Errors.kt`, catch `android.os.DeadObjectException` (and `BluetoothGattServer.addService` returning `false` after `STATE_OFF`) and translate to the existing `bluetooth-unavailable` Pigeon error code. Symmetric work on iOS for the analogous post-`poweredOff` failure modes.

### C. `StaleHandleException` (defer; only if A is insufficient)

`BluetoothUnavailableException` says "the adapter is unavailable now." It does not say "the handle you're holding was invalidated by a *prior* adapter-state transition." If consumers hit cases where they need to distinguish those — e.g. retry logic that wants to know whether a fresh `Server()` would succeed — add `StaleHandleException` extending `BlueyException`.

Defer until A + B land and we see whether the disambiguation is actually needed in practice.

### Out of scope

- **`BluetoothAdapterStateChanged` event on `Bluey.events`** — this would duplicate `Bluey.stateStream` and create two parallel ways to observe the same signal. Document `stateStream` as canonical instead.
- **Auto-reinitialization** — explicitly excluded per A.

## Why medium severity (not high)

The original framing was "high severity, UI lies, no recovery without app restart." Tempering that:

- A consumer can already subscribe to `Bluey.stateStream` (one line) to know when the adapter cycled, fixing the "UI lie" half of the problem entirely.
- A consumer can already call `Bluey.ensureReady()` before operations to get typed exceptions, reducing the surface where opaque `bluey-unknown` errors leak.
- "No recovery without app restart" is overstated — once `state == on` again, a consumer can construct a fresh `bluey.server()` / `bluey.connect(...)` and proceed.

The genuine pain is:
- A consumer that *doesn't* subscribe to `stateStream` (most consumers, today, since it isn't surfaced in any example) gets an opaque exception with no signal.
- Even consumers that *do* subscribe still hit the race where an op is in flight when the adapter cycles, and the exception they see is `bluey-unknown` rather than `BluetoothUnavailableException`.

A + B fix both. Medium severity reflects "real but workaround-able with existing API."

## Notes

- `bluey_android` already exposes `getBluetoothState()` as a one-shot query (used by `Bluey.ensureReady`). The event stream (`stateStream`) is also already there. The missing piece is *acting on the events internally*.
- Look at the existing `BlueyConnection` invalidation pattern from I088 (Service Changed → `AttributeHandleInvalidatedException` clears `_cachedServices`). The shape of A's invalidation should mirror it.
- A consumer-side workaround pending this fix: subscribe to `Bluey.stateStream`; on any non-`on` transition, drop your `Server`/`Connection`/`Scanner` references and surface the state to the user. This is documented above as the "B is a backstop" path; it works today, it's just not advertised.
