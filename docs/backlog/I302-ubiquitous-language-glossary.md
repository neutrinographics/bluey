---
id: I302
title: Cross-context vocabulary lacks a glossary; Domain ↔ Platform seam silently translates terms
category: limitation
severity: low
platform: domain
status: open
last_verified: 2026-04-26
related: [I300]
---

## Symptom

Different bounded contexts use different terms for structurally similar concepts ("the thing on the other end of the BLE link"), and the Domain ↔ Platform-Interface seam silently translates between them:

- **Discovery** uses `Device` (`bluey/lib/src/discovery/device.dart`) — the result of scanning. Has a UUID `id` and a platform-specific `address`.
- **Connection** uses `Connection` itself, with the remote side implicitly the `Device` you connected to.
- **Server** (peripheral role) uses `Client` (`bluey/lib/src/gatt_server/server.dart:18`) — the GATT central that has connected. The Server API uses this term consistently (`connectedClients`, `Client.disconnect()`).
- **Peer** uses `BlueyPeer` (`bluey/lib/src/peer/peer.dart:16`) — protocol-aware promotion of "device + lifecycle protocol".
- **Platform-interface** uses `PlatformDevice` and `PlatformCentral` (`bluey_platform_interface/lib/src/platform_interface.dart:165, 662`).

Each context is **internally consistent**, which is good. The friction shows at the seams:

1. **Domain ↔ Platform translation is silent.** `PlatformCentral` becomes `Client` at the boundary; `PlatformDevice` becomes `Device`. The translation happens inside `bluey_server.dart` etc., but the rationale (different contexts, different vocabulary) isn't documented for new contributors.
2. **No glossary exists.** A consumer reading the public API encounters `Bluey.connect(Device)`, `bluey.discoverPeers()`, `BlueyPeer.connect()`, `Server.connectedClients` — five overlapping role-words (device, peer, client, server, central) with no single document explaining how they relate.

## Location

- `bluey/lib/src/discovery/device.dart:13` — `Device`.
- `bluey/lib/src/gatt_server/server.dart:18, 77` — `Client`, `List<Client> connectedClients`.
- `bluey/lib/src/gatt_server/server.dart:26` — `Client.disconnect()` (consistent with the `Client` naming).
- `bluey/lib/src/peer/peer.dart:16` — `BlueyPeer`.
- `bluey/lib/src/peer/peer_discovery.dart:20` — `PeerDiscovery`.
- `bluey_platform_interface/lib/src/platform_interface.dart:165, 537, 662` — `PlatformDevice`, `disconnectCentral` (platform-interface only), `PlatformCentral`.
- `bluey/lib/src/gatt_server/bluey_server.dart:540` — `_platform.disconnectCentral(...)` translation site.

## Root cause

Each module evolved with the vocabulary that fit its bounded context:

- **Discovery** module: "device" (you find devices, you don't yet know their role).
- **Server** module: "client" (peripheral's-eye view of who's connected to it).
- **Peer** module: "peer" (protocol-aware, role-symmetric).

The contexts each chose internally-coherent terms; the gaps appear at the seams between contexts and at the Domain ↔ Platform-Interface boundary.

## Notes

**Step 1 — Glossary (recommended, low cost).** Add a glossary section to `CLAUDE.md` (or a new `GLOSSARY.md`) that defines each term, its scope, and its relationships:

> - **Device** — a BLE peripheral discovered via scanning. The local role is implicitly "central." Use this term in the Discovery bounded context.
> - **Connection** — an established GATT link to a remote Device. The local role is GATT central. Use this term in the Connection bounded context.
> - **Server** — the peripheral role, hosted by this device. The local role is GATT server. Use this term in the GATT-Server bounded context.
> - **Client** — a GATT central that has connected to our local Server. Used inside the Server bounded context. Translates to `PlatformCentral` at the platform-interface seam.
> - **Peer** — a Device or Client that speaks the Bluey lifecycle protocol. Promotion to Peer happens after control-service discovery. Use this term only in the Peer bounded context.

**Step 2 — Document the Domain ↔ Platform seam translation.** Add a brief comment near `_platform.disconnectCentral(...)` in `bluey_server.dart` and at the `Device` / `Client` factories explaining that the platform-interface uses BLE-spec-aligned vocabulary (`Central`, `PlatformDevice`) and the domain layer uses bounded-context-aligned vocabulary (`Client`, `Device`), and that the translation is intentional.

## Scope-tightening note (2026-04-26)

The original review proposal (REVIEW-2026-04-26-ddd-followup.md) suggested two additional renames that turned out to be **already-correct** in HEAD:

1. ~~Rename `Server.disconnectCentral` → `Server.disconnect(ConnectedClient)`.~~ No `Server.disconnectCentral` exists in the public API. Disconnect is exposed as `Client.disconnect()`, which is consistent with `connectedClients` returning `List<Client>`. The "Central" name only surfaces at the platform-interface boundary (`_platform.disconnectCentral`), which is the wire-level call.
2. ~~Rename `Client` → `ConnectedClient`.~~ The Server bounded context already uses `Client` consistently. Renaming to `ConnectedClient` would be cosmetic, not a clarity improvement.

This entry's scope is therefore narrower than the original proposal: the glossary + the Domain ↔ Platform seam documentation. The full original is preserved in the parent review for reference.

## Cost-benefit

Low-priority. The cost (writing the glossary, occasional doc cross-references) is small; the benefit (a more legible API for new consumers and contributors) is real but diffuse. The glossary alone (Step 1) is the high-leverage piece; Step 2 is bonus. Worth doing as an opportunistic doc pass, not its own project.

External references:
- Eric Evans, *Domain-Driven Design* (2003), Chapter 2: "Communication and the Use of Language" — the foundational treatment of ubiquitous language. Specifically: "the language used by domain experts and developers should be the same."
- Vaughn Vernon, *Implementing Domain-Driven Design* (2013), Chapter 1: "Getting Started with DDD" — practical advice on building and maintaining a glossary.
- Bluetooth Core Specification 5.4, Vol 1, Part A, §1.2 — defines the BLE-spec terminology (Central / Peripheral / GATT Client / GATT Server) that is the upstream source of the platform-interface vocabulary.
