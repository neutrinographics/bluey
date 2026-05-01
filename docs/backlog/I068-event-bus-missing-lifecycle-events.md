---
id: I068
title: Lifecycle protocol state changes not emitted as BlueyEvents
category: no-op
severity: low
platform: domain
status: fixed
last_verified: 2026-05-01
fixed_in: d2fb012
related: [I054, I317]
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

Fixed in `d2fb012`. Six new event types added to `events.dart`:

- `HeartbeatSentEvent(deviceId)` — every probe write.
- `HeartbeatAcknowledgedEvent(deviceId)` — every successful ack.
- `HeartbeatFailedEvent(deviceId, isDeadPeerSignal: bool, reason)` —
  on probe error. `isDeadPeerSignal` flag distinguishes dead-peer
  signals (timeout / disconnected / counted codes) from transient
  errors that don't move the silence clock.
- `PeerDeclaredUnreachableEvent(deviceId)` — silence detector trips
  and the client is about to local-disconnect.
- `LifecyclePausedForPendingRequestEvent(clientId)` (server-side) —
  fires on the pause edge when the first pending request lands on a
  tracked client. Not noisy — fires once per pause transition, not
  per request.
- `ClientLifecycleTimeoutEvent(clientId)` (server-side) — heartbeat
  timer expires. Distinct from the generic `ClientDisconnectedEvent`
  which fires for any disconnect; this fires only when the lifecycle
  silence detector trips.

Threading: `LifecycleClient` and `LifecycleServer` constructors gained
optional `events` (`EventPublisher`) parameters. `LifecycleClient`
also gained an optional `deviceId` since its events need it; without
deviceId, emissions skip silently — defensive for tests that build a
client in isolation. Construction sites in `Bluey.connectAsPeer`,
`BlueyPeer.connect`, and `BlueyServer` thread the bus through.

Paired with I054 (dead GATT-op event types) — both shipped together
and share the new `EventPublisher` port introduced in I054. Existing
consumer migration (`BlueyServer` / `BlueyScanner` / `Bluey`) tracked
as **I317**.
