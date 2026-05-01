---
id: I313
title: Auto-include control UUID in Android scan response so peerDiscoverable can default to true
category: unimplemented
severity: medium
platform: android
status: open
last_verified: 2026-05-01
related: [I055, I051]
---

## Symptom

`Server.startAdvertising(peerDiscoverable: true)` (post-I055) prepends
the Bluey lifecycle control service UUID to the *primary* advertising
payload. On Android that competes with the user's app service UUIDs,
device name, and manufacturer data inside a 31-byte legacy budget — a
128-bit UUID alone consumes ~18 bytes (16 UUID + 2 header). Apps already
near the limit get `ADVERTISE_FAILED_DATA_TOO_LARGE` when they opt in.

To keep the budget pressure down, the I055 fix landed `peerDiscoverable`
**off by default**. New Bluey users have to read the docs and opt in
deliberately. The fix's broader UX goal — "`bluey.discoverPeers()` works
out of the box" — is blocked on this.

## Location

`bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/Advertiser.kt`
(or wherever the active advertiser builder lives — verify path).
`bluey_android/lib/src/android_server.dart` — Pigeon delegation site.
`bluey_android/pigeons/messages.dart` — schema if the host API needs to
expose scan-response fields separately.

## Root cause

Android's `BluetoothLeAdvertiser` exposes two distinct buffers:

1. **`AdvertiseData`** — the primary advertisement, 31-byte legacy
   budget. Visible to passive scanners.
2. **`AdvertiseSettings.Builder.setScanResponseData(...)`** — a separate
   31-byte buffer transmitted only in response to active scan requests.
   Most BLE clients (including iOS CoreBluetooth's default centrals and
   Android's own scanner with `SCAN_TYPE_ALLMATCHES`) issue active
   scans, so the scan response is delivered to them too.

The current `BlueyAdvertiser` packs everything (name + service UUIDs +
manufacturer data) into the primary `AdvertiseData`. There is no native
plumbing for scan-response data.

## Notes

**Fix sketch (multi-day):**

1. Add scan-response fields to `AdvertiseConfigDto` in
   `bluey_android/pigeons/messages.dart`. Decide whether to surface
   them as separate primary/scan-response sub-DTOs or as a tagged set
   of optional fields per AD type.
2. In the Android advertiser, build the primary `AdvertiseData` from
   the user-supplied `services` / `manufacturerData` / `name` and the
   scan-response `AdvertiseData` from the control UUID (when
   `peerDiscoverable: true`).
3. Once shipped, change the I055 default from `peerDiscoverable: false`
   to `peerDiscoverable: true`. Document the new behavior in dartdoc
   on `Server.startAdvertising` and remove the budget-warning paragraph.

iOS impact: none. CoreBluetooth doesn't expose scan-response separately;
overflow-area promotion already handles the equivalent budget pressure.

This is a subset of I051 (advertising options not exposed) — specifically
the scan-response slot. Consider folding into that umbrella, or keep
separate as a single-use surface for the control UUID.

**Privacy considerations.** Scan-response data is only transmitted when
a scanner actively probes — it's not visible to passive scanners. That
makes the fingerprinting cost lower than primary-AD inclusion. Still
worth documenting as a tradeoff for privacy-sensitive deployments
(provide an explicit `peerDiscoverable: false` opt-out even after the
default flips).

External references:
- Android [`AdvertiseSettings.Builder.setAdvertiseMode(int)`](https://developer.android.com/reference/android/bluetooth/le/AdvertiseSettings.Builder).
- Android [`BluetoothLeAdvertiser.startAdvertising(...)`](https://developer.android.com/reference/android/bluetooth/le/BluetoothLeAdvertiser) — three-argument form takes both primary and scan-response `AdvertiseData`.
- BLE Core Specification 5.4, Vol 6, Part B, §4.4.2.4: scan-response PDU.
