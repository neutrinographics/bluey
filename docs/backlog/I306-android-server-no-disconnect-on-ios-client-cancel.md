---
id: I306
title: Android server doesn't observe non-Bluey iOS client disconnect (BLE supervision-timeout latency)
category: bug
severity: low
platform: android
status: open
last_verified: 2026-04-29
related: []
---

## Scope (post-2026-04-29)

The Bluey↔Bluey case is now closed: `PeerConnection.disconnect()` writes a `0x00` lifecycle courtesy hint to the server, which fires `onClientGone` immediately via `LifecycleServer.handleWriteRequest` — bypassing the platform-callback dependency entirely. This works in both directions (Android-server + iOS-client and iOS-server + Android-client). Verified on real devices.

The remaining open scope is **non-peer iOS centrals connecting to an Android server as raw GATT clients** — they have no lifecycle service to write to, so the server still depends on Android's `BluetoothGattServerCallback.onConnectionStateChange` firing for `STATE_DISCONNECTED`. Some Android stacks delay or never fire that callback when iOS issues a soft disconnect, leaving the server with a stale "connected" state until link-supervision timeout (4–10 s, sometimes longer on OEM stacks).

This narrows the original premise: most production Bluey servers connect to Bluey peers, and Bluey peers now disconnect cleanly. Only raw-GATT iOS interop is affected.

## Symptom

When the Android role is GATT server (peripheral) and a **non-Bluey** iOS app is the GATT client, an iOS-side `connection.disconnect()` does not promptly surface as a disconnect event on the Android server. The Android server UI continues to show the central as connected, even though the BLE radio link has been torn down. Eventually the Android stack fires `onConnectionStateChange(STATE_DISCONNECTED)` via supervision timeout — typically several seconds, sometimes longer.

In the reverse direction (iOS server + non-Bluey Android client), the analogous Android-side disconnect IS eventually observed by the iOS server "after a while" — same supervision-timeout pattern.

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

For non-Bluey iOS centrals (raw GATT, no lifecycle service), there's no application-layer keepalive to lean on. Options if/when this becomes worth fixing:

- **Watchdog timer.** Track each connected central and start a timer (e.g. 30 s) on connect. Reset on any GATT activity. On expiry, manually call `BluetoothGattServer.cancelConnection(device)` and synthesize an `onCentralDisconnected` event. Aggressive but works around stack flakiness.
- **Read-RSSI polling.** Periodically attempt a low-impact GATT op against each central; if the op fails with a disconnect-like error, force the disconnect path. More radio-traffic-heavy.
- **Document the limitation.** Make non-Bluey iOS-central + Android-server an explicit edge case: app developers should plan for the latency.

Cost-benefit: now **low severity**. The peer-protocol fast path (post-`3041eca`) covers the common case (Bluey↔Bluey) in both directions. Read/write functionality on non-peer iOS centrals still works during the connected window; only the explicit "disconnect" event is delayed by supervision timeout (typically 4–10 s, OEM-dependent). Punted to opportunistic — pick up only if a concrete consumer needs raw-GATT iOS-central interop with sub-second disconnect detection.

## Verification plan

When picked up: reproduce on a real iOS device + real Android device with a **non-Bluey** iOS client (one that does NOT subscribe to or write the lifecycle service). Use a generic BLE explorer app on iOS (e.g. LightBlue, nRF Connect). Time-stamp the iOS disconnect action and compare to the Android-side `onCentralDisconnected` log line. Test across multiple Android OEMs (Samsung, Pixel, etc.) — disconnect-detection behavior varies.
