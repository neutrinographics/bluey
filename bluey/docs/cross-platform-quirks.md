# Cross-Platform Quirks

This document captures behavioral differences between Android and iOS that bluey **cannot** paper over — places where the same API call has materially different effects on each platform, and where consumer apps need to design around the difference.

For native-side implementation notes (Kotlin / Swift internals, workarounds for native API gaps), see `bluey_android/ANDROID_BLE_NOTES.md` and `bluey_ios/IOS_BLE_NOTES.md`. Those target maintainers of the platform packages. This document targets app developers using bluey.

## iOS shares one LL connection per peer pair across GAP roles

**Affects:** apps using bidirectional discovery (both devices advertise *and* scan, with `peerDiscoverable: true`).

**Symptom on iOS.** When device **B** has device **A** already connected as a client (A initiated, A is GATT central, B is GATT server) and **B** then calls `bluey.connectAsPeer(deviceA)` based on a fresh scan emission, Core Bluetooth does **not** open a second physical link. It returns a new `CBPeripheral` handle that shares the underlying LL connection with the existing `CBCentral`. When B later calls `peerConn.disconnect()` on the new handle, `cancelPeripheralConnection` tears down the *only* physical link — invalidating B's existing peripheral-side handle for A as well.

The typical loop:

1. A → B central-role connection established.
2. B's scanner sees A's advertisement, calls `connectAsPeer(deviceA)`.
3. App-level dedup in B notices the duplicate and calls `peerConn.disconnect()`.
4. A's central side observes the disconnect, lifecycle clears identification.
5. A re-emits identification on the next heartbeat.
6. B's scanner sees A's advertisement again — back to step 2.

**Symptom on Android.** Same code opens a second independent LL connection. Disconnecting it has no effect on the first. Wasteful (2 links per pair instead of 1) but correctness is intact.

**Why this happens.** Apple's `CBPeer` is the parent type of both `CBCentral` and `CBPeripheral`, with a single stable `identifier` UUID per peer regardless of role. The OS multiplexes a single LL connection per peer pair. The central / peripheral abstractions are roles over that one link, not separate links. This is by design and has been consistent across iOS 11–18.

### Recommended pattern: address-based dedup before `connectAsPeer`

The `ClientAddress` observed peripheral-side (`Client.address`, also the value on `Server.disconnections`) and the `DeviceAddress` observed central-side (`Device.address`) wrap the **same** raw platform identifier per platform — MAC on Android, `CBPeer.identifier` UUID on iOS. They are deliberately distinct types per bounded context (see I337), so cross them explicitly via `.value`: `ClientAddress(device.address.value)`. An address-equality check then answers "is this device already attached to me in some role?".

```dart
final server = bluey.server()!;
// ... server is set up and advertising

scanner.scan().listen((scanResult) async {
  final device = scanResult.device;

  // Dedup BEFORE connecting. Skip any device already attached as a
  // client — on iOS, connecting and then disconnecting would tear down
  // the existing peripheral-side link. `Client.address` and
  // `Device.address` are distinct types over the same raw value, so
  // bridge with `ClientAddress(device.address.value)`.
  if (server.isClientConnected(ClientAddress(device.address.value))) return;

  try {
    final peer = await bluey.connectAsPeer(device);
    // ... use peer
  } on NotABlueyPeerException {
    // Not a Bluey peer — fine, ignore.
  }
});
```

Apps that hold multiple central-role peer connections concurrently should *also* dedup against their own connection registry, since `Server.isClientConnected` only sees the peripheral-role side.

### Why `tryUpgrade` is also affected

`tryUpgrade` doesn't open a new link itself — it wraps an existing `Connection`. But the trap is at *disconnect* time, not at connect time, so any code path that ends up calling `disconnect()` on a `PeerConnection` whose underlying connection shares an LL link with an existing peripheral-side handle hits the same trap. Guard the upstream connect, not the upgrade.

## Android stops delivering GATT-server requests after a client↔server role reversal on a still-live link

**Affects:** bidirectional apps that reverse GATT roles with the *same* peer — e.g. a session that ran A-server/B-client and then flips to B-server/A-client — **without first tearing the prior link down**.

**Symptom on Android.** When Android becomes the GATT **server** for a peer it was, moments earlier, talking to under the opposite role (and that physical link is still alive), Android's `BluetoothGattServer` callbacks (`onCharacteristicReadRequest`, `onCharacteristicWriteRequest`, …) **silently never fire** for that central's requests. The central's reads and lifecycle heartbeat-writes get no ATT response at all and hang until the central's per-op timeout (~10 s) fires — so peer identification is delayed by a full timeout, and the heartbeat write-failures accumulate as dead-peer signals until the link is torn down. The connection *itself* is up (you see `onConnectionStateChange`, `onPhyUpdate`, `onMtuChanged`); only inbound ATT **requests** vanish. A full ACL teardown — disconnecting the prior link, or toggling Bluetooth on either device — clears the stale association, and the identical Android-server scenario then works.

**Symptom on iOS.** iOS as server in the same role-reversal sequence answers the requests normally; this failure mode is Android-specific.

**Why this happens.** Android multiplexes a single ACL link per peer (the same "one physical link per peer" reality behind the iOS trap above). When that link was established under one GATT-role association and the roles reverse while the link is still live, the stack keeps routing inbound ATT requests by the stale association and they never reach the new server-role callback. This is the Android *server-receive* cousin of the iOS shared-link trap — same underlying cause, different surface.

**Recommended pattern: tear the prior link down before reversing roles.** Don't flip a peer between client and server roles while a link to it is live. Disconnect the existing connection (`connection.disconnect()` / `peerConn.disconnect()`) and wait for the platform to report it down before standing up the opposite role. If you're stuck in the failure state during development, toggling Bluetooth force-releases the ACL. bluey intentionally does **not** auto-detect or auto-tear-down this state — the failure fingerprint is ambiguous and an auto-disconnect could surprise an app that holds a client link deliberately — so handling it is the app's responsibility (decision recorded in backlog **I208**).

## Heartbeat silence is advisory on Android, a disconnect on iOS

**Affects:** GATT-server apps using the Bluey lifecycle protocol (`peerDiscoverable: true`) that need to distinguish a paused peer from a truly disconnected one.

**Background.** When a connected Bluey peer's central-side app is backgrounded or paused, its heartbeat writes to the lifecycle control characteristic stop. The server's silence detector fires after `lifecycleInterval` (default 10 s) with no write received.

**Behavior on Android** (`Capabilities.reportsCentralDisconnects == true`). Android delivers a native `onConnectionStateChange` callback when a client link actually drops. Because bluey has a reliable disconnect signal, heartbeat silence is treated as **advisory only**: the server emits a `ClientLifecycleTimeoutEvent` on `Server.events` but does **not** emit on `Server.disconnections`. The peer remains in `connectedClients`; when it resumes and heartbeats again it is identified seamlessly with no reconnect overhead.

**Behavior on iOS** (no native client-disconnect callback, I201). iOS does not deliver a peripheral-role disconnect event for a central that simply goes away. Heartbeat silence is therefore still the only signal available, and it **does** drive `Server.disconnections` — the client's session is *evicted* (removed from `connectedClients`, identification cleared). Because the GATT link is still physically up, the paused peer does not learn it was evicted until it resumes: its next request (heartbeat or app write) finds no established session, so the server rejects it with a reserved application-range ATT status and does **not** dispatch it. The peer's bluey layer translates that status into a clean `disconnect()` — surfacing `DisconnectedException(DisconnectReason.evictedByServer)` — and the app's normal reconnect logic runs. The reconnect re-establishes a fresh, frame-aligned session.

**The key property: both paths are non-corrupting.** A paused-then-resumed peer never silently re-identifies mid-stream (that was the I338 stream-framing corruption path, now closed). On Android the pause resumes *seamlessly* — no `disconnections`, no reconnect. On iOS the same pause costs a brief **reconnect blip**: a real disconnect followed by a real reconnect, with the consumer's per-connection stream state (frame decoders, reassembly buffers) cleanly bracketed by the `disconnections` / `peerConnections` edges. The only visible cross-platform difference is that iOS reconnect blip.

**Practical guidance.** On Android, treat a `ClientLifecycleTimeoutEvent` as a warning that a peer may be paused, not as confirmation it is gone — wait for the `Server.disconnections` emission before tearing down app state for that client. On iOS, expect a transient pause beyond the timeout to manifest as a disconnect/reconnect pair; bracket per-connection state on `Server.disconnections` / `Server.peerConnections` and it stays consistent across the blip. To widen the pause envelope before either platform reacts, raise `lifecycleInterval` on the server (default 10 s) and `peerSilenceTimeout` on the client (default 30 s) to match your app's background-pause profile.

*(I338 — lifecycle-silence transport reconciliation. Stage 1 fixed the Android advisory path; Stages 2–3 fixed the iOS eviction→clean-reconnect path.)*
