---
id: I304
title: Extract a shared peer-builder helper for `_tryBuildPeerConnection` and `_BlueyPeer.connect`
category: limitation
severity: low
platform: domain
status: open
last_verified: 2026-04-28
related: [I300]
---

## Symptom

After Phase C of the handle-rewrite (commits `541fdbc`–`7f819d6`), there are two construction sites for `PeerConnection`:

1. **`Bluey._tryBuildPeerConnection(Connection)`** at `bluey/lib/src/bluey.dart` — used by `Bluey.connectAsPeer(Device)` and `Bluey.tryUpgrade(Connection)`. Starts from a `Connection`, discovers the control service, reads the `ServerId` from the device, builds a `LifecycleClient`, calls `lifecycleClient.start()`, returns `PeerConnection.create(...)`.

2. **`_BlueyPeer.connect(...)`** at `bluey/lib/src/peer/bluey_peer.dart` — used when a caller already has a `BlueyPeer` (typically from `bluey.peer(serverId)` or `bluey.discoverPeers()`). Starts from a `ServerId` (it already knows the identity), uses `PeerDiscovery.connectTo` for scan-based discovery, builds a `LifecycleClient`, calls `start()`, returns `PeerConnection.create(...)`.

Both paths set up an identical `LifecycleClient(platformApi, connectionId, peerSilenceTimeout, onServerUnreachable)` and pass it into `PeerConnection.create`. The post-discovery boilerplate (~20 lines) is duplicated.

The starting contexts differ — one has a `Connection`+unknown-`ServerId`, the other has a `ServerId`+no-`Connection`-yet — so a single shared entry point isn't natural. But the post-discovery work (LifecycleClient construction + start + PeerConnection.create) is identical.

## Location

- `bluey/lib/src/bluey.dart` — `_tryBuildPeerConnection` (slow path, post-services discovery + LifecycleClient setup).
- `bluey/lib/src/peer/bluey_peer.dart` — `_BlueyPeer.connect`'s body (post-PeerDiscovery + LifecycleClient setup).

## Root cause

C.7 (commit `7f819d6`) intentionally avoided cross-cutting refactor and kept both sites self-contained. The plan suggested `_BlueyPeer.connect` could delegate to `bluey.connectAsPeer(device)`, but `_BlueyPeer` operates on `ServerId` (not `Device`), so direct delegation isn't structurally clean.

## Notes

The shape of the shared helper:

```dart
PeerConnection _buildPeer({
  required BlueyPlatform platform,
  required Connection rawConnection,
  required ServerId serverId,
  required List<RemoteService> allServices,
  required Duration peerSilenceTimeout,
}) {
  final lifecycleClient = LifecycleClient(
    platformApi: platform,
    connectionId: _connectionIdFor(rawConnection),
    peerSilenceTimeout: peerSilenceTimeout,
    onServerUnreachable: () {
      rawConnection.disconnect().catchError((_) {});
    },
  );
  lifecycleClient.start(allServices: allServices);
  return PeerConnection.create(
    connection: rawConnection,
    serverId: serverId,
    lifecycleClient: lifecycleClient,
  );
}
```

Lives somewhere in `bluey/lib/src/peer/` (e.g. `peer_builder.dart`) as a top-level package-internal function. Both call sites in `bluey.dart` and `bluey_peer.dart` shrink to one call.

Cost-benefit: ~20 lines saved across two files; a clear single source of truth for the LifecycleClient lifecycle. Worth doing during Phase E cleanup or the next refactor that touches either file. Not blocking.
