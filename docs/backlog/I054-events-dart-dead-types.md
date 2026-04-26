---
id: I054
title: Several `BlueyEvent` subtypes are defined but never emitted
category: no-op
severity: low
platform: domain
status: open
last_verified: 2026-04-26
related: [I068]
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

Two viable resolutions:

1. **Emit from `_loggedGattOp` success paths.** Add an `event:` callback parameter to `_loggedGattOp` that constructs the appropriate event given the operation name and result, then call it on success. Hook into every call site — `BlueyRemoteCharacteristic.read`/`write`, `BlueyConnection.services`, `BlueyRemoteCharacteristic.notifications`.
2. **Delete the dead types.** If the events stream is intended only for high-level lifecycle (connect/scan/server), document that and remove the GATT-op event types.

Recommended: option (1). The events stream is the right diagnostic API for consumer-visible monitoring; the structured `dev.log` calls give essentially the same data but are harder to consume programmatically.

Pair with I068 (lifecycle protocol events not emitted as BlueyEvents) — both are about making the events stream as comprehensive as the catalog suggests.
