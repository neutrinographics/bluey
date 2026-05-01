---
id: I054
title: Several `BlueyEvent` subtypes are defined but never emitted
category: no-op
severity: low
platform: domain
status: fixed
last_verified: 2026-05-01
fixed_in: 14bae42
related: [I068, I317]
---

## Symptom

Consumers subscribing to `bluey.events` expect to see GATT-operation events (read, write, notify, service discovery) based on the catalog in `events.dart`. They never arrive. The `Bluey` instance emits only scan, connect, server, advertising, and error events.

## Location

`bluey/lib/src/events.dart` defines the following types that are never `emit()`ed anywhere in the production codebase:

- `DiscoveringServicesEvent` (line 124)
- `ServicesDiscoveredEvent` (line 135)
- `CharacteristicReadEvent` (line 151)
- `CharacteristicWrittenEvent` (line 169)
- `NotificationReceivedEvent` (line 191)
- `NotificationSubscriptionEvent` (line 209)
- `DebugEvent` (line 418)

The structured logging in `_loggedGattOp` at `bluey/lib/src/connection/bluey_connection.dart:88-129` produces equivalent information via `dev.log` but does not also emit events.

## Root cause

Implementation gap. The event types were declared as part of the catalog but the emission sites were never added to `_loggedGattOp` or `BlueyRemoteCharacteristic`/`BlueyRemoteDescriptor`.

## Notes

Fixed in `14bae42`. Resolution: option (1) — emit from the existing
call sites rather than deleting the types.

A new `EventPublisher` port (just `void emit(BlueyEvent)`) was
introduced in `event_bus.dart`; `BlueyEventBus` implements it. Aggregates
that need to publish events depend on the port (Interface Segregation
— minimum surface needed). Threading: `BlueyConnection` and
`BlueyRemoteCharacteristic` constructors accept `EventPublisher?`,
threaded from `Bluey._eventBus` via `Bluey.connect` and through
`PeerDiscovery` / `BlueyPeer` for the peer-protocol path.

Emission sites:
- `BlueyConnection.services()` — `DiscoveringServicesEvent` before,
  `ServicesDiscoveredEvent` after.
- `BlueyRemoteCharacteristic.read()` — `CharacteristicReadEvent` after success.
- `BlueyRemoteCharacteristic.write()` — `CharacteristicWrittenEvent` after success.
- `BlueyRemoteCharacteristic.notifications` first-listen / last-cancel —
  `NotificationSubscriptionEvent(enabled: true|false)`.
- Inbound platform notifications — `NotificationReceivedEvent`.

`DebugEvent` left as-is; it's a generic catch-all without a clear
production emission site.

Migration of existing consumers (`BlueyServer` / `BlueyScanner` /
`Bluey`) from depending on the concrete `BlueyEventBus` to
depending on `EventPublisher` is filed as **I317** — left as a
transitional inconsistency to keep this fix scoped.

Paired with I068 (lifecycle protocol events) — both shipped together
and share the new `EventPublisher` port.
