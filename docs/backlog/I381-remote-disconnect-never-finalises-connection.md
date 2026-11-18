---
id: I381
title: Finalise a Connection when the peer disconnects
category: bug
severity: high
platform: domain
status: fixed
last_verified: 2026-11-18
fixed_in: 3e6a653
related: [I369]
---

## Symptom

A disconnect the peer causes, the most common way a BLE link ends, leaves the `Connection` half alive. `stateChanges` and every notification stream stay open, so `await for` consumers hang. The platform subscriptions and per-characteristic controllers are never released, and no later call can release them. A later adapter-off event moves the dead connection from `disconnected` to `invalidated`.

## Location

`bluey/lib/src/connection/bluey_connection.dart:965` (the platform `disconnected` event only calls `_setState`), `:815` (`_cleanup()` runs only from an explicit `disconnect()`), `:787` (`disconnect()` returns early once the state is already `disconnected`).

## Root cause

Teardown is only reliable on the path the app initiates. Cleanup is attached to `disconnect()`, and `disconnect()` refuses to run on a connection that is already down, so once the peer ends the link nothing can finish the cleanup.

## Notes

Found by finding H3 of the [2026-11-17 audit](../reviews/2026-11-17-correctness-and-test-rig-audit.md). Closed by slice 1 (link lifecycle) of the architecture foundation ([design](../superpowers/specs/2026-11-17-architecture-foundation-design.md)).

Fix: run the same teardown on the platform `disconnected` event as on `disconnect()`, and make `disconnect()` on a dead connection finish the cleanup. [I369](I369-adapter-controller-leaks.md) tracks the adapter-level half; both are one change seen from different layers. Test: group `H3 (I381)` in `bluey/test/known_defects/domain_known_defects_test.dart`. One of the audit's three open Highs.

## Fixed (2026-11-18)

Fixed in `3e6a653` by slice 1 (link lifecycle, [design](../superpowers/specs/2026-11-18-link-lifecycle-design.md) sections 6.3 and 6.4). A link's lifecycle is one state machine, `Link`, run by one `LinkSession`: a drop and a requested disconnect reach the same end, and reaching it releases everything the link held, whatever ended it. A dropped Connection now emits `disconnected`, closes its streams and fails operations in flight with `DisconnectedException` (`linkLoss`); `disconnect()` on an ended Connection completes quietly. The two known-defect tests moved to group `H3 (I381)` in `bluey/test/features/connection/link_end_through_the_api_test.dart` and left the roster.
