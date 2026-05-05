---
id: I324
title: Document iOS CoreBluetooth peer-merge behavior on dual-role connections
category: docs
severity: low
platform: ios
status: open
last_verified: 2026-05-05
related: [I323]
---

## Symptom

iOS's Core Bluetooth represents each physical peer as a single `CBPeer` (the parent of `CBCentral` and `CBPeripheral`), with one stable `identifier` UUID per peer regardless of GAP role. The OS multiplexes a *single* LL connection per peer pair; the central/peripheral abstractions are roles over that one link, not separate links.

Concretely, when iOS device **B** has device **A** connected as a peripheral (i.e. A initiated, A is central, B is peripheral) and then B calls `bluey.connectAsPeer(deviceA)`:

- iOS does **not** open a second physical LL connection. It returns a new `CBPeripheral` handle that shares the underlying connection with the existing `CBCentral`.
- When B later calls `peerConn.disconnect()` on the new peer connection, `cancelPeripheralConnection` tears down the *only* physical link.
- B's existing peripheral-side handle for A is now invalid; bluey emits `centralDisconnections` for A's clientId, the lifecycle `_handleClientDisconnected` fires, the app's `_clientIdToNodeId` map is cleared.
- Net effect: a routine "race-loser tear-down the duplicate connection" pattern destroys the original working link.

On Android the equivalent code path opens a second independent LL connection that can be torn down without affecting the first.

This is **not a bluey bug** — it's how Apple's stack works at the CoreBluetooth layer. But it's a sharp edge that consumers will hit unless told.

## Location

- `bluey/lib/src/bluey.dart:443–466` — `connectAsPeer` doc comment is the natural place for this caveat.
- `bluey/lib/src/peer/peer_connection.dart:62–76` — `disconnect` doc could also note the iOS-specific tear-down implication.
- A short prose section in `bluey/CLAUDE.md` or a dedicated `docs/cross-platform-quirks.md` would help future consumers.

## Verification

Reproduced 2026-05-05 on iOS 18 + Android 14 in the gossip_chat dogfood app, with diagnostic logs showing:

1. Android (central) → iOS (peripheral) connection established, lifecycle handshake completes, gossip messages flow.
2. iOS scans, gets Android's advertisement, calls `connectAsPeer(android)`.
3. iOS's app-level dedup detects the duplicate (registry already had Android as peripheral) and calls `peerConn.disconnect()` on the new connection.
4. Android sees the central drop, lifecycle clears identification, `peerConnections` re-fires on the next heartbeat from a "new" identification (clientId remains the same; only the dedup set was cleared).
5. Loop until manual intervention.

Workaround: the application maintains an address-keyed cache populated from *both* central-side `Device.address` and peripheral-side `Client.id`, then dedups *before* calling `connectAsPeer`. See `gossip_bluey` for a reference implementation.

## Proposed docs change

Add a paragraph to `Bluey.connectAsPeer`:

> **iOS caveat:** On iOS, Core Bluetooth represents a peer device as a single `CBPeer` regardless of GAP role. If your app already holds a peripheral-side handle for `device.address` (i.e. that device previously connected to your `Server`), do **not** call `connectAsPeer` for it. The new connection will share the underlying physical link, and disconnecting it will tear down the existing peripheral handle as well. Use a per-app address cache to dedup pre-connect; see I323 for a possible bluey-level helper.

And a short README/CLAUDE.md entry in `bluey/` summarising the cross-platform difference.

## Why low severity

- Documentation, not code.
- Affects only apps with bidirectional discovery (most apps are asymmetric: hub advertises, spokes scan).
- Can be worked around at the application layer with a few lines of code.
