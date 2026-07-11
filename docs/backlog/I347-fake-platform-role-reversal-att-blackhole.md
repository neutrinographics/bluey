---
id: I347
title: Make the Android role-reversal ATT blackhole injectable in the fake platform
category: enhancement
severity: low
platform: domain
status: fixed
last_verified: 2026-07-10
fixed_in: r12-fake-modeling merge
related: [I208]
---

## What this is

On Android there is a documented failure state where the connection looks
perfectly healthy but the device, acting as a Bluetooth server, silently never
receives its clients' requests: reads and heartbeat writes get no answer at
all and hang until the sender's per-operation timeout fires. It happens when
two devices swap client/server roles while their existing physical link is
still alive (recorded as a deliberate wontfix for auto-detection — handling it
is the app's responsibility).

The in-memory test platform has no way to express "the server stops receiving
requests while the link stays up," so the library's documented behavior in
this state — heartbeat write-failures accumulating into a dead-peer verdict
and eventual teardown — has no automated test.

## Why it matters

This is the harshest real-world networking condition the project has recorded:
a *silent* one-directional loss, invisible to connection-state monitoring. It
is precisely the kind of scenario the lifecycle protocol's death-watch exists
to catch. An injectable "server-side request blackhole" in the fake would let
tests prove the death-watch actually converges (accumulated write timeouts →
peer declared unreachable → teardown) instead of trusting the design on paper,
and would guard the documented app-level guidance against regression.

## Rough approach

Add a fake seam that, per connected central (or globally), swallows inbound
server-bound requests: the client-side write/read is accepted onto the wire
but no request event reaches the server role and no response ever returns, so
the client's operation runs into its timeout. Combined with virtual time, a
test can then script: healthy traffic → blackhole on → N heartbeat timeouts →
dead-peer teardown. Pairs naturally with the audit's fault-rule queue
recommendation (R2) and per-operation timeout seams.

## Related

- The underlying platform behavior and wontfix decision: [I208 — Android dual-role server request delivery](I208-android-dual-role-server-request-delivery.md); consumer-facing writeup in [cross-platform quirks](../../bluey/docs/cross-platform-quirks.md) §"Android stops delivering GATT-server requests after a client↔server role reversal".
- Audit that identified the gap: [2026-07-10 networking-scenario test audit](../reviews/2026-07-10-networking-scenario-test-audit.md) (addendum scenario 10; pairs with recommendation R2).
