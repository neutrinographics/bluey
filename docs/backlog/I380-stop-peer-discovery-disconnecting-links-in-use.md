---
id: I380
title: Stop peer discovery disconnecting links in use
category: bug
severity: high
platform: domain
status: fixed
last_verified: 2026-11-18
fixed_in: 3e6a653
related: [I374]
---

## Symptom

`discoverPeers()` or a second `BlueyPeer.connect()` can drop a link the app is already using. Discovery probes every advertising candidate, and Bluey servers keep advertising while connected, so a device the app holds a `Connection` to is probed too. The probe's disconnect tears the app's link down, and the original `Connection` stays `ready` on a dead link.

## Location

`bluey/lib/src/peer/peer_discovery.dart:183`, `:187`, `:238`, `:252` — the raw `_platform.connect` probe and its unconditional `_platform.disconnect(address)`.

## Root cause

Discovery talks to the platform directly and `Bluey` keeps no registry of live connections by address, so discovery cannot tell a candidate it may probe from a link someone else owns. On the real adapters the probe's connect also replaces the per-device stream controllers ([I369](I369-adapter-controller-leaks.md)), so the original `Connection` is never told.

## Notes

Found by finding H2 of the [2026-11-17 audit](../reviews/2026-11-17-correctness-and-test-rig-audit.md). Closed by slice 1 (link lifecycle) of the architecture foundation ([design](../superpowers/specs/2026-11-17-architecture-foundation-design.md)).

Fix: a registry of live connections by address, with discovery reading the server id over the existing link or skipping the address. Related to [I374](I374-ios-same-peer-connect-guard.md), which covers only the iOS shared-link case. Test: group `H2 (I380)` in `bluey/test/known_defects/domain_known_defects_test.dart`. One of the audit's three open Highs.

## Fixed (2026-11-18)

Fixed in `3e6a653` by slice 1 (link lifecycle, [design](../superpowers/specs/2026-11-18-link-lifecycle-design.md) sections 6.5 and 6.9). One registry, `LinkRegistry` over the pure `LiveLinks`, knows every live link, and peer discovery no longer connects or disconnects through the platform: it borrows the device's link, reads the server id over it, and gives it back, which closes the link only when the probe opened it and nobody else uses it. `connectAsPeer` borrows the same way since `bd9b340`. The known-defect test moved to group `H2 (I380)` in `bluey/test/peer/peer_discovery_test.dart` and left the roster. The iOS shared-link case, [I374](I374-ios-same-peer-connect-guard.md), is not closed here: it moved to slice 5.
