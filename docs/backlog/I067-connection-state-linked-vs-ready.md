---
id: I067
title: ConnectionState collapses link-up and services-discovered into one state
category: limitation
severity: medium
platform: domain
status: open
last_verified: 2026-04-26
---

## Symptom

The `ConnectionState` enum has four values (`disconnected`, `connecting`, `connected`, `disconnecting`). There is no value that distinguishes "link established but services not yet discovered" from "fully ready for GATT operations." A consumer that subscribes to `connection.stateChanges` and reacts to `connected` by issuing reads/writes might do so before service discovery completes, depending on how the Connection was obtained.

## Location

`bluey/lib/src/connection/connection_state.dart:1-13`.

## Root cause

The state machine mirrors the OS's link-layer view (disconnected/connecting/connected/disconnecting) rather than the domain-meaningful "ready for GATT ops" view. BLE connections have multiple post-link initialization steps (services discovery, optional MTU negotiation, optional CCCD subscriptions, optional bond) before they are usable.

In the current Bluey code, `Bluey.connect()` and `BlueyPeer.connect()` both run services discovery internally before returning, so the "linked but not ready" window is never observable from the public Connection. But the state machine itself doesn't enforce this — a future code path that returns the Connection earlier would expose the gap.

## Notes

The cleanest fix is a tri-state lifecycle:

```dart
enum ConnectionState {
  disconnected,
  connecting,
  linked,           // link established; services not yet discovered
  ready,            // services discovered; usable for GATT ops
  disconnecting;
}
```

`Bluey.connect()` continues to await `ready` before returning the Connection. Consumers that subscribe to `stateChanges` see the explicit `linked → ready` transition.

This is a domain modeling improvement that supports future use cases (e.g., exposing partial connections for diagnostic UIs). If no current code path returns a Connection in `connected` state without having discovered services, this is a forward-looking architectural concern, not a current bug — adjust severity to `low`.

External references:
- Nordic recommendation to delay 600-1600ms after `STATE_CONNECTED` before calling `discoverServices()` for bonded devices: https://devzone.nordicsemi.com/f/nordic-q-a/4608/gatt-characteristic-read-timeout
