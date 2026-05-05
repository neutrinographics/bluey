---
id: I323
title: `Bluey.connectAsPeer` does not detect device already connected in the other GAP role
category: enhancement
severity: low
platform: domain
status: open
last_verified: 2026-05-05
related: [I324]
---

## Symptom

When an application has bidirectional discovery (both devices advertise *and* scan, with `peerDiscoverable: true`), and **device A** is already connected to **device B** as a central — so on B, A is a `PeerClient` registered via `Server.peerConnections` — and **then** B calls `bluey.connectAsPeer(deviceA)` based on a fresh scan emission, bluey opens a *new* central-role connection without any indication that the same physical device is already attached in the inverse role.

On iOS this triggers a CoreBluetooth peer-merge (see I324): the new connect-then-disconnect sequence tears down the *existing* peripheral-side handle for the same peer. Result: an infinite reconnect loop and broken connectivity.

On Android the two LL connections coexist, but it's still wasteful: every pair holds two BLE links per direction (4 total per pair) for the duration both sides have one another in the registry. With 8-device meshes, this can pressure controller-side resource limits.

## Location

- `bluey/lib/src/bluey.dart:443–466` — `Bluey.connectAsPeer(Device, ...)` calls `connect` then `_tryBuildPeerConnection`. There is no check against `Server.peerConnections` history for an already-known `PeerClient` whose `client.id` equals `device.address`.
- `bluey/lib/src/gatt_server/bluey_server.dart` — the server already maintains `_connectedClients` and `_identifiedPeerClientIds`, indexed by `clientId`, which on every platform is the same string as `Device.address` (see I324 for derivation).

## Proposed behavior

Two non-mutually-exclusive options:

1. **`Bluey.isPeerKnown(Device device): bool`** — returns true if the device's address matches any currently-connected client/peer (across roles). Apps can call this before `connectAsPeer` to avoid the trap. Cheap, additive.

2. **`connectAsPeer` self-check** — if the address matches a known peer, throw a typed `AlreadyConnectedAsPeerException` rather than silently opening a redundant link. More opinionated; risks breaking apps that intentionally want a second connection. Probably gated behind a parameter (`onAlreadyConnected: AlreadyConnectedPolicy.throw`).

## Why low severity

Applications can already implement this dedup themselves: the `clientId` (peripheral side) and `Device.address` (central side) refer to the same identifier per platform, and apps can maintain their own address-keyed cache. `gossip_bluey` does this in its `ConnectionService._addressToNodeId`. The bluey-level helper would be a convenience and a guardrail, not a correctness fix.

## Notes

- The gossip_bluey workaround (cache `address → NodeId` from peripheral-side `peerConnections` events) is documented in `gossip/docs/superpowers/specs/2026-05-05-gossip-bluey-peripheral-address-dedup-design.md` (or wherever that spec lands). That should remain the application's responsibility; this ticket is purely about giving consumers a less footgunny default.
- Consider whether the same logic should apply to plain `Bluey.connect` (non-peer connect). Probably not — a non-peer connect is a deliberate raw GATT connect, and the caller usually knows what they're doing.
