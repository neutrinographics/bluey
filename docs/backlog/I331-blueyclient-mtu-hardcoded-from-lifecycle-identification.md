---
id: I331
title: `BlueyClient.mtu` is hardcoded to 23 when constructed from the lifecycle handshake path
category: bug
severity: medium
platform: domain
status: fixed
last_verified: 2026-07-06
fixed_in: "HEAD (verified 2026-07-06; no dedicated commit — handshake path now reuses the tracked client's MTU)"
related: [I325, I326]
---

## Symptom

`Server.peerConnections` emits a `PeerClient` whose `client.mtu` is **always 23** when the client was identified via the lifecycle handshake (the typical path on iOS centrals, and on Android centrals that connect cached without firing `onConnectionStateChange`).

The hardcoding is at `bluey/lib/src/gatt_server/bluey_server.dart:639–642`:

```dart
final client = BlueyClient(
  id: clientId,
  mtu: 23, // Default MTU — actual MTU is unknown without platform event
);
```

The `_trackPeerClient` path runs whenever the lifecycle ServerId write arrives. On iOS this is the *only* path that fires (CoreBluetooth never invokes `onConnectionStateChange` on the peripheral side for cached connections). So consumers reading `peerClient.client.mtu` to size notifications get 23 even when the underlying link has negotiated 247.

The other construction path (`bluey_server.dart:132–135`, in the `_centralConnections` listener) does pass `platformCentral.mtu` from the platform event. So Android centrals that fire `onConnectionStateChange` get the right MTU. But that path is racey — see I328.

## Reproduction

In a `gossip_bluey`-style consumer with bidirectional discovery: on Android-as-peripheral with iOS-as-central connected, log `peerClient.client.mtu` in the `peerConnections` listener. Result: 23, regardless of actual negotiated MTU (~247 in practice on Android+iOS).

Downstream consequence: chunked writes derive `chunkSize = mtu - 3 = 20`, so a 200-byte notification ships as 11 separate `notifyCharacteristicChanged` calls. This compounds with [I332] (notifyTo not awaiting `onNotificationSent`) into observable corruption under load — Android's notification queue overflows, drops happen, and the consumer's framing layer has to recover from misalignment.

## Proposed fix

Same shape as I326 / I325: thread the platform-reported MTU through. Two avenues:

1. **Capture from `onMtuChanged` on the server side too.** The Android plugin already fires `onMtuChanged` events to Dart. `BlueyServer` should subscribe (alongside the existing client connection / disconnection / write subscriptions) and update the cached MTU on `_connectedClients[clientId]`. iOS doesn't have an equivalent event, but it also doesn't expose MTU to apps at all on the peripheral side — accept 23 as the iOS-peripheral truth, since notification size is governed by `maximumUpdateValueLengthForCentral(_:)` instead (a separate API not currently exposed by bluey).

2. **Mirror `Connection.maxWritePayload` for the server side.** Add `Server.maxNotificationLength(Client client): Future<int>` that, on Android, returns `mtu - 3`, and on iOS forwards to `peripheralManager.maximumUpdateValueLengthForCentral(_)` (currently not surfaced — would require platform plumbing).

(2) is the cleaner architectural answer (parallel to I325's central-side change) and would let consumers stop computing `mtu - 3 - safety` arithmetic at all on the server side.

## Why medium severity

This is a footgun for any consumer that ships chunked notifications. Workaround at the consumer level is a fixed fallback chunk size when `client.mtu == 23` (similar to the iOS-central workaround in `gossip_bluey` before I325 landed). Until the upstream fix, every consumer with bidirectional traffic needs that workaround.

## Notes

- I326 covers the **central-side** equivalent (`AndroidConnectionExtensions.mtu` not auto-updated on spontaneous renegotiation). This ticket is the **server-side** sibling.
- I328 covers the racey first construction path (`bluey_server.dart:132`) where `mtu` *is* set from the platform event but other state initialization can race. Different scope from this ticket.
- A consumer-side workaround is shipping in `gossip_bluey` until this lands; can be removed once `BlueyClient.mtu` is honest about the actual link MTU (or once `Server.maxNotificationLength` exists and consumers migrate to it).
