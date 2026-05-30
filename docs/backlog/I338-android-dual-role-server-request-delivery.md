---
id: I338
title: Android stops delivering GATT-server ATT requests after a client↔server role reversal on a still-live link
category: limitation
severity: high
platform: android
status: open
last_verified: 2026-05-29
related: [I306, I063]
---

## Symptom

In a bidirectional session, when an Android device becomes the GATT **server**
for a peer it was — moments earlier — talking to under the *opposite* role, and
that physical link is still alive, Android's `BluetoothGattServer` callbacks
never fire for that central's requests. The connected central's reads and
lifecycle heartbeat-writes receive **no ATT response at all** and hang until the
central's per-op timeout (~10 s) fires.

Observed 2026-05-29 in the `gossip_chat` dogfood app between an iPhone and a
Pixel 6a. Sequence: ran iOS-server / Android-client, then switched to
Android-server / iOS-client **without tearing the prior link down**. The iOS
central connected to the Android server fine (link established: the Android
side logged `onConnectionStateChange` connected, `onPhyUpdate`, `onMtuChanged`)
but its first `readCharacteristic` stalled the full client op-timeout
(`GattTimeoutException`, `durationMs: 10052`), delaying peer identification by
that 10 s; subsequent heartbeat writes also timed out
(`GattOperationTimeoutException`), counting as dead-peer signals until the link
churned/disconnected. Throughout, the Android server logged **no**
`onCharacteristicReadRequest` / `onCharacteristicWriteRequest` entry despite
those handlers logging at `DEBUG` and `DEBUG` being visible — i.e. the requests
never reached the app layer.

Toggling Bluetooth on both devices (full ACL teardown) and reconnecting with
Android as server — same scenario — **worked**. iOS-as-server in the same
sequence answers the requests normally; the failure is Android-specific.

## Location

- Android server request callbacks that never fire under this condition:
  `bluey_android/.../GattServer.kt` — `onCharacteristicReadRequest` (~:790),
  `onCharacteristicWriteRequest` (~:836). The response path
  (`respondToReadRequest` / `respondToWriteRequest` → `sendResponse`, ~:441/:473)
  is never invoked because the request is never delivered.
- The Dart routing (`bluey_server.dart`, `lifecycle_server.dart`) is **not**
  implicated — the same platform-agnostic Dart server answers these requests
  correctly when iOS is the server.

## Root cause

Android multiplexes a single ACL link per peer (the same "one physical link per
peer" reality behind the iOS shared-link trap documented in
`bluey/docs/cross-platform-quirks.md`). When that link was established under one
GATT-role association and the roles reverse while the link is still live, the
stack keeps routing inbound ATT requests by the stale association and they never
reach the new server-role callback. This is the Android **server-receive**
cousin of the iOS trap — same underlying cause, different surface. It is a
platform-stack behavior; bluey did not change any native code around it
(confirmed: the I337 branch that surfaced the report touched zero native code,
and iOS-as-server with the identical Dart works).

## Notes

- **Not a regression** from I337 (transport-address value objects). That work was
  Dart-only; this is a runtime BLE-state issue triggered by role reversal on a
  live link.
- **Reliable workaround (consumer-side):** tear the prior link down before
  reversing roles — `connection.disconnect()` / `peerConn.disconnect()` and wait
  for the platform to report it down before standing up the opposite role. A BT
  toggle force-releases the ACL during development. Documented for app developers
  in `bluey/docs/cross-platform-quirks.md` ("Android stops delivering
  GATT-server requests after a client↔server role reversal on a still-live link").
- **Open question (why this entry is `open`, not `wontfix`):** whether bluey
  should detect and pre-empt the trap — e.g. before serving a peer, check for a
  lingering same-peer *client* link and tear it down; and/or surface a faster,
  clearer signal than a silent 10 s timeout when a server gets a connection but
  no ATT traffic. These are real design calls (especially for bidirectional apps)
  and are being brainstormed separately.
- **Confirmation still pending real-device instrumentation** to nail the exact
  stack mechanism (vs a narrower bluey_android setup issue): an unconditional
  INFO log at the top of the server read/write callbacks, plus logging whether a
  concurrent same-peer `BluetoothGatt` client link exists at server-connect time.
  Related: I063 (late GATT callback misrouted after app-level timeout) and I306
  (Android server doesn't observe non-Bluey iOS client disconnect) are adjacent
  Android server-direction routing issues.
