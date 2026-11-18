---
id: I374
title: Consider an internal guard against connecting out to an already-attached iOS peer
category: enhancement
severity: low
platform: ios
status: open
last_verified: 2026-07-10
related: [I208, I346]
---

## What this is

The iOS shared-link trap (one physical link per peer pair) is
documented as a consumer responsibility with a recommended
`isClientConnected` dedup pattern. The library could make the safe
path the default: detect that the connect target's identifier matches
an attached client and refuse (or warn) instead of letting the caller
tear down the shared link by accident (audit DA-33's one actionable
suggestion; the trap itself is modeled and regression-tested via
[I346](I346-fake-platform-shared-link-trap-model.md)).

## Notes

Design decision required: hard refusal vs opt-in guard vs warning
event — a hard guard could surprise apps that hold a client link
deliberately (the reason [I208](I208-android-dual-role-server-request-delivery.md)
was wontfixed for auto-teardown).

## Moved to slice 5 (2026-11-18)

Slice 1 (link lifecycle) leaves this open: it moved to slice 5 (server and peer), as decided in the [link lifecycle design](../superpowers/specs/2026-11-18-link-lifecycle-design.md), section 6.9. The rule needs to know which clients are attached to the local server, which is GATT Server's knowledge, and today `Bluey.server()` keeps no server it builds, so doing it in slice 1 meant glue in the composition root that slice 5 would rewrite. "Roles share one link" is not a fact `Capabilities` holds either. And skipping such a device during discovery would drop it from `discoverPeers()` and make `BlueyPeer.connect()` to it fail, where slice 5 can report the peer from the identity it already sent as a client, without probing it. Until then a probe of an iOS device attached to our `Server` as a client still drops that client, as before.
