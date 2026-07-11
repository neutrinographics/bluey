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
