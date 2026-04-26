---
id: I017
title: Default `peerSilenceTimeout` is internally inconsistent and races OS supervision timeout
category: bug
severity: low
platform: domain
status: fixed
last_verified: 2026-04-26
fixed_in: a352c17
related: [I097, I071]
---

## Symptom

**(a) Internal default mismatch.** The library-level default for `peerSilenceTimeout` in `Bluey.connect`, `Bluey.peer`, `BlueyConnection` constructor, and `_BlueyPeer.connect` is **20 seconds**. The example app's `ConnectionSettings` uses **30 seconds**. Consumers reading the library docstring see one value; consumers copying the example app see another.

**(b) Racing OS supervision timeout.** The Android default link supervision timeout is approximately 20 seconds. When the BLE link genuinely fails, the OS-level supervision timeout fires at ~20s and the platform reports `STATE_DISCONNECTED`, which already triggers tear-down through a separate path (the `connectionStateStream` listener in `BlueyConnection`).

If the silence detector also fires at 20s, the two detection paths race. Usually the OS path wins because it tears down the platform connection synchronously (which drains the queue with `gatt-disconnected` errors, which feeds the silence detector to convergence). But the timing coincidence isn't ideal — a slightly longer silence-detector default gives the OS room to act first, simplifying the failure narrative for consumers and reducing the chance of "double-disconnect" events on the connection state stream.

## Location

- Library defaults (post-I097):
  - `bluey/lib/src/bluey.dart:313, 376, 522` — `connect(...)`, `peer(...)`, `_upgradeIfBlueyServer(...)`: `Duration(seconds: 20)`.
  - `bluey/lib/src/connection/bluey_connection.dart:198` — constructor default `Duration(seconds: 20)`.
- Example app default:
  - `bluey/example/lib/features/connection/domain/connection_settings.dart:12` — `Duration(seconds: 30)`.

## Root cause

Independent default-value choices that drifted apart during the I097 (peer-silence) work. The 20s figure was chosen as "shorter than the heartbeat interval doubled"; the example app's 30s figure was chosen as "longer than typical user-op timeouts." Neither default explicitly considered the OS supervision timeout as an upstream constraint.

## Notes

Fixed in `a352c17` by introducing a single `lifecycle.defaultPeerSilenceTimeout = Duration(seconds: 30)` constant and pointing all five default-value sites at it (`Bluey.connect`, `Bluey._upgradeIfBlueyServer`, `Bluey.peer`, `BlueyConnection` constructor, `createBlueyPeer`). Doc-comments on `Bluey.connect` and `Bluey.peer` updated to describe the parameter as covering both heartbeat-probe timeouts and user-op timeouts (post-I097 reality) and to cite the OS-supervision constraint. Bluetooth Core Spec 5.4 Vol 6 Part B §4.5.2 (Link Supervision Timeout) is referenced in the constant's doc-comment.

The recommendation to add a constructor-time minimum-clamp assertion was not implemented — minimum-value validation of timeout-knob parameters is more naturally bundled with the value-object refactor in I301 (primitive obsession), where `PeerSilenceTimeout` would become a typed value object with construction-time validation.

Side discovery: verification surfaced a concrete consequence of [I071](I071-upgrade-called-twice-leaks-lifecycle.md) (upgrade-leaks-previous-lifecycle). A test in `bluey_peer_test.dart` was relying on the leaked OLD lifecycle's timeout rather than the timeout it passed to `createBlueyPeer`. Workaround applied (longer elapse window + comment); the I071 entry now records the test as a candidate for rewrite once I071 lands.

External references:
- Bluetooth Core Specification 5.4, Vol 6 (Low Energy Controller), Part B, §4.5.2 — Link Supervision Timeout. AOSP default `BTM_BLE_CONN_TIMEOUT_DEF` ≈ 2000 (× 10ms = 20s).
- Apple Accessory Design Guidelines (R8 BLE), Connection Parameters: recommended supervision timeout 2–6 seconds; iOS may negotiate longer.
