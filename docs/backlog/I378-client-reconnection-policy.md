---
id: I378
title: Add a client reconnection policy (auto-reconnect on dropped links)
category: unimplemented
severity: medium
platform: both
status: open
last_verified: 2026-07-19
related: [I043, I048, I084]
---

## Symptom

When an established connection drops — peer out of range, peer reboot,
supervision timeout — Bluey surfaces the disconnect and stops. There is no
way to ask the library to re-establish the link: no auto-reconnect option on
`connect()`, no retry/backoff policy, and no client-side re-subscription
after a successful manual reconnect. Every consumer that needs a long-lived
connection hand-rolls the same scan → connect → re-subscribe loop, which is
where real-world BLE apps spend most of their debugging time.

The 2026-07-07 audit (DA-35, cluster M-K) called the missing
reconnection/autoConnect policy "the most consequential breadth gap vs. the
field" — `flutter_blue_plus` exposes Android's `autoConnect`, and
`flutter_reactive_ble` consumers routinely wrap `connectToDevice` in retry
streams. Bluey offers neither an escape hatch nor a policy.

## Location

- `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/ConnectionManager.kt:177,179` — `device.connectGatt(context, false, …)`; the platform `autoConnect=true` path is never used or exposed.
- `bluey_ios/ios/Classes/CentralManagerImpl.swift:221` — `centralManager.connect(peripheral, options: nil)` issued once; no pending-connect retry (iOS connects never time out natively, but a dropped link is never re-armed).
- `bluey/lib/src/bluey.dart` — `connect()`/`connectAsPeer()` take no reconnection parameter.

## Root cause

Feature was never in scope; the connection lifecycle was built
disconnect-terminal. The adjacent pieces each got their own item (see
Related) but the policy that would tie them together was not tracked until
the 2026-07-19 audit-absorption double-check.

## Notes

Fix sketch, deliberately high-level (this is a design decision as much as a
feature):

- A `ReconnectionPolicy` value object passed to `connect()` — e.g. `none`
  (today's behavior, default) vs. `auto(backoff, maxAttempts)`.
- A domain-level retry loop is likely more portable than Android's
  `autoConnect=true` (which connects at a reduced duty cycle and retries
  forever with no failure signal); Android `autoConnect` could still back an
  opt-in low-power variant later.
- Client-side re-subscription (re-enable notifications the consumer had
  active before the drop) belongs to this item; the server-side twin is
  [I084](I084-reconnect-loses-subscriptions.md).
- Composes with [I043](I043-ios-no-retrieve-peripherals.md) (retrieve-then-
  connect makes iOS retries cheap — no scan needed) and
  [I048](I048-ios-no-state-restoration.md) (state restoration covers the
  background-relaunch flavor of the same consumer need).
- Interaction to decide: how a reconnection policy composes with
  `PeerConnection` (the lifecycle protocol has its own death-watch teardown;
  auto-reconnect must not fight `PeerDeclaredUnreachableEvent`).

Source finding: audit DA-35 in
`docs/reviews/2026-07-07-full-stack-audit.md` (cluster M-K).
