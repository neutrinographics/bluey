---
id: I305
title: Re-introduce BLUEY badge in example app's connection screen via `bluey.tryUpgrade`
category: limitation
severity: low
platform: domain
status: open
last_verified: 2026-04-28
related: [I300]
---

## Symptom

The example app's connection screen used to display a small "BLUEY" badge next to the "Connected" label whenever the connected device was a Bluey peer (i.e. exposed the lifecycle control service). Pre-C.6, this rendered conditionally on `connection.isBlueyServer`.

After C.6 (commit `ccb5dc6`) removed `isBlueyServer` from the `Connection` interface — `BlueyConnection` is now a pure GATT connection with no peer-protocol state — the conditional was deleted with a TODO. The connection screen no longer indicates whether a connected device is a Bluey peer.

## Location

`bluey/example/lib/features/connection/presentation/connection_screen.dart` — search for `TODO(C.7): re-introduce a BLUEY badge`.

## Root cause

C.6 prioritized scoping over feature parity in the example app. Migrating the conditional would have required tracking a separate `PeerConnection?` field on the connection cubit/state alongside the existing `Connection` field, then either calling `bluey.tryUpgrade(connection)` post-connect to populate it, or switching the connect flow to `bluey.connectAsPeer` for known-peer device IDs. Either change is a small but real cross-cutting refactor of the cubit/state layer.

## Notes

Two viable shapes:

**Option A — opportunistic upgrade in cubit.**
After the existing `bluey.connect(device)` resolves, call `bluey.tryUpgrade(connection)` and store the result in cubit state as `PeerConnection? peer`. The badge renders when `peer != null`.

```dart
final connection = await bluey.connect(device);
final peer = await bluey.tryUpgrade(connection);  // null if not a peer
emit(state.copyWith(connection: connection, peer: peer));
```

**Option B — opt-in peer connect.**
If the device is known to be a peer (e.g. from a peer-discovery scan), use `bluey.connectAsPeer(device)` directly and store a `PeerConnection` only. For non-peer devices, use `bluey.connect(device)` and store a raw `Connection`. State holds either a `Connection` or a `PeerConnection`.

**Recommendation:** Option A. It mirrors the pre-rewrite UX (auto-detect peerness post-connect) without forcing the example app to discriminate between the two flows at connect time. Adds ~10 lines to the cubit.

Cost-benefit: minor UX polish in the example app. Not blocking. Best done during Phase E doc/example cleanup or as a one-shot follow-up.
