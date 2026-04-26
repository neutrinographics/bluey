---
id: I067
title: ConnectionState collapses link-up and services-discovered into one state
category: limitation
severity: medium
platform: domain
status: fixed
last_verified: 2026-04-26
fixed_in: 8b02ccf
---

## Symptom

The `ConnectionState` enum has four values (`disconnected`, `connecting`, `connected`, `disconnecting`). There is no value that distinguishes "link established but services not yet discovered" from "fully ready for GATT operations." A consumer that subscribes to `connection.stateChanges` and reacts to `connected` by issuing reads/writes might do so before service discovery completes, depending on how the Connection was obtained.

## Location

`bluey/lib/src/connection/connection_state.dart:1-13`.

## Root cause

The state machine mirrors the OS's link-layer view (disconnected/connecting/connected/disconnecting) rather than the domain-meaningful "ready for GATT ops" view. BLE connections have multiple post-link initialization steps (services discovery, optional MTU negotiation, optional CCCD subscriptions, optional bond) before they are usable.

In the current Bluey code, `Bluey.connect()` and `BlueyPeer.connect()` both run services discovery internally before returning, so the "linked but not ready" window is never observable from the public Connection. But the state machine itself doesn't enforce this — a future code path that returns the Connection earlier would expose the gap.

## Notes

Fixed in `8b02ccf` by replacing the single `connected` value with a five-state lifecycle:

```dart
enum ConnectionState {
  disconnected,
  connecting,
  linked,    // link established; services not yet discovered
  ready,     // services discovered; usable for GATT ops
  disconnecting;
}
```

`BlueyConnection` now constructs in `linked` (was `connected`). Platform `CONNECTED` maps to `linked`. Promotion to `ready` is driven domain-side from `services()` after first successful discovery and from `upgrade()` after lifecycle install. A new `_setState` helper makes platform-driven transitions idempotent and non-regressing — refuses to walk `ready → linked` if the platform re-emits `CONNECTED`. `upgrade()` deliberately bypasses idempotency so re-upgrade still emits, since the example app's connection cubit listens for that re-emit to detect lifecycle re-attachment.

New helpers: `isReady` (only true for `ready`); `isConnected` extended to cover both `linked` and `ready` (semantic preserved: "link is up"); `isActive` extended to cover the new states.

Public API breaking change: 54 call sites across the library, tests, and example app were updated. Most assertions about "the connection that came out of `Bluey.connect()` is up" became `state == ConnectionState.ready`. The example app's `ConnectionStateChip` switch became exhaustive over all five states with `linked` rendered separately. Bumps the next release to a minor or major version depending on policy.

External references:
- Nordic recommendation to delay 600-1600ms after `STATE_CONNECTED` before calling `discoverServices()` for bonded devices: https://devzone.nordicsemi.com/f/nordic-q-a/4608/gatt-characteristic-read-timeout
