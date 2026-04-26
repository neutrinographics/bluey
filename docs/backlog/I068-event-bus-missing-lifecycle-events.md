---
id: I068
title: Lifecycle protocol state changes not emitted as BlueyEvents
category: no-op
severity: low
platform: domain
status: open
last_verified: 2026-04-26
related: [I054]
---

## Symptom

Consumers monitoring `bluey.events` cannot observe heartbeat-protocol behavior: heartbeat sent, heartbeat acknowledged, heartbeat failed (transient vs counted), threshold tripped (server declared unreachable), pending-request pause, server-side client-gone detection. These are visible only via `dev.log` strings.

For a library whose distinguishing feature is its lifecycle protocol, the protocol's own state transitions are the highest-value diagnostic events.

## Location

- `bluey/lib/src/connection/lifecycle_client.dart` — fires `dev.log` for various heartbeat events; no `_emitEvent` calls.
- `bluey/lib/src/gatt_server/lifecycle_server.dart` — no diagnostic events at all.

## Root cause

Lifecycle classes don't have `BlueyEventBus` injected. Adding events would require threading the bus through `LifecycleClient` and `LifecycleServer` constructors.

## Notes

Suggested events to add to `events.dart`:

- `HeartbeatSentEvent(deviceId)`
- `HeartbeatAcknowledgedEvent(deviceId)`
- `HeartbeatFailedEvent(deviceId, isDeadPeerSignal)`
- `PeerDeclaredUnreachableEvent(deviceId)` (post-I097: when the silence detector fires)
- `LifecyclePausedForPendingRequestEvent(clientId)`  (server-side)
- `ClientLifecycleTimeoutEvent(clientId)` (server-side)

Threading: pass `BlueyEventBus` into `LifecycleClient` and `LifecycleServer` constructors. Update the `Connection`-side construction in `Bluey.connect`/`BlueyPeer.connect` to thread the bus through.

Pair this with I054 (dead GATT-op event types) — both are about making the events stream as comprehensive as the catalog suggests.
