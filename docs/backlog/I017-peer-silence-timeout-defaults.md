---
id: I017
title: Default `peerSilenceTimeout` is internally inconsistent and races OS supervision timeout
category: bug
severity: low
platform: domain
status: open
last_verified: 2026-04-26
related: [I097]
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

Suggested fix:

1. **Reconcile defaults.** Pick one value and use it consistently across library and example. Recommendation: **30 seconds**:
   - Conservative against false positives during transient link congestion on stressed Android devices.
   - Strictly longer than the Android default supervision timeout (~20s), so the OS path has room to fire first on genuine link loss.
   - Aligned with iOS's longer effective supervision timeout.
2. **Document the rationale.** The doc-comment on `Bluey.connect`'s `peerSilenceTimeout` parameter should explicitly note that the value should exceed the platform supervision timeout, with a one-sentence pointer to the BLE Core Spec section on supervision timeout.
3. **Optional: clamp to a minimum.** Constructor-time assertion or warning if `peerSilenceTimeout < Duration(seconds: 10)` — values below the supervision timeout actively undermine the design.

External references:
- Bluetooth Core Specification 5.4, Vol 6 (Low Energy Controller), Part B, §4.5.2 — Link Supervision Timeout. AOSP default `BTM_BLE_CONN_TIMEOUT_DEF` ≈ 2000 (× 10ms = 20s).
- Apple Accessory Design Guidelines (R8 BLE), Connection Parameters: recommended supervision timeout 2–6 seconds; iOS may negotiate longer.
