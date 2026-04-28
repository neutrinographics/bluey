---
id: I306
title: Android server doesn't observe iOS client disconnect (BLE supervision-timeout latency or missing event)
category: bug
severity: medium
platform: android
status: open
last_verified: 2026-04-28
related: []
---

## Symptom

When the Android role is GATT server (peripheral) and the iOS role is GATT client (central), an iOS-side `connection.disconnect()` does not promptly surface as a disconnect event on the Android server. The Android server UI continues to show the central as connected, even though the BLE radio link has been torn down.

In the reverse direction (iOS server + Android client), the analogous Android-side disconnect IS eventually observed by the iOS server, "after a while" — consistent with BLE link-supervision-timeout-driven detection (typically 4–10 s).

## Status on main vs feat/handle-identity-rewrite

- **On `main` (pre-handle-rewrite)**: the Android server doesn't observe the iOS client's connection at all (server-side tracking didn't fire on connect). So the disconnect issue was masked by the connect issue.
- **On `feat/handle-identity-rewrite` (post-bundle)**: the Android server now correctly observes the iOS client's connect; reads/writes succeed; but disconnect does not fire on the server side. **This is a partial improvement, not a regression** — the rewrite fixed the connect-detection but exposed the latent disconnect-detection gap.

## Location

- `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/GattServer.kt:646` — `BluetoothGattServerCallback.onConnectionStateChange` is implemented and forwards `STATE_DISCONNECTED` to `flutterApi.onCentralDisconnected(deviceId)`. The native callback path is intact, so the issue is either:
  1. The Android BLE stack isn't firing `onConnectionStateChange` for this combo (the central went away without a clean L2CAP disconnect message), or
  2. iOS's `cancelPeripheralConnection` doesn't always issue a clean disconnect message that Android's stack interprets as `STATE_DISCONNECTED` — the server then waits for link-supervision timeout, which on some Android stacks is much longer than expected.

## Root cause (provisional)

Likely interaction between iOS's `cancelPeripheralConnection` and Android's GATT-server stack. iOS may issue a soft disconnect (e.g. terminate ATT before a link-layer disconnect) that some Android stacks don't surface to the application until link-supervision timeout fires. Some Android OEM stacks don't report supervision-timeout-driven disconnects on the server side at all.

The disconnect path on `GattServer.kt` did NOT change in the handle-identity rewrite — this is a behavior of the native stack, not the Bluey domain layer.

## Notes

Workaround until fixed: rely on application-level keepalive (heartbeat) over the lifecycle-control service to detect peer-gone. The BlueyServer's `_handleClientDisconnected` is invoked via `onClientGone` from the lifecycle layer when heartbeats stop, independent of the platform disconnect callback. Bluey-aware peers (those that speak the lifecycle protocol) already get this for free; non-Bluey iOS centrals don't.

If we want to fix this for non-Bluey iOS centrals, options:
- **Watchdog timer.** Track each connected central and start a timer (e.g. 30 s) on connect. Reset on any GATT activity. On expiry, manually call `BluetoothGattServer.cancelConnection(device)` and synthesize an `onCentralDisconnected` event. Aggressive but works around stack flakiness.
- **Read-RSSI polling.** Periodically attempt a low-impact GATT op against each central; if the op fails with a disconnect-like error, force the disconnect path. More radio-traffic-heavy.
- **Document the limitation.** Make non-Bluey iOS-central + Android-server an explicit edge case: app developers should plan for the latency.

Cost-benefit: medium severity. Read/write functionality works, just the explicit "disconnect" event is delayed or missing. Most production Bluey servers will use Bluey peers (which have the lifecycle heartbeat path), so this only bites for raw-GATT iOS-central interop. Worth filing for a future fix, not blocking the bundled-rewrite merge.

## Verification plan

When picked up: reproduce on a real iOS device + real Android device, with the Android server example app foregrounded and the iOS client example app tapping Disconnect. Time-stamp the iOS disconnect tap and compare to the Android-side `onCentralDisconnected` log line. Test across multiple Android OEMs (Samsung, Pixel, etc.) — disconnect-detection behavior varies.
