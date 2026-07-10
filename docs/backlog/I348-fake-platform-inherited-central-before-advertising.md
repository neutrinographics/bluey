---
id: I348
title: Let the fake platform accept inherited central connections before advertising starts
category: enhancement
severity: low
platform: domain
status: open
last_verified: 2026-07-10
related: [I338]
---

## What this is

On real devices, a central can appear *before* the local server ever starts
advertising. The documented case: iOS caches its connection to a peer; when
that peer's app restarts and opens a fresh Bluetooth server, iOS's cached
connection "reconnects" instantly — the server sees a connected central before
advertising begins. The native layers deliberately report these inherited
connections to the library so apps can handle them.

The in-memory test platform models this as impossible:
`simulateCentralConnection` throws a `StateError` when advertising is not
active (`bluey/test/fakes/fake_platform.dart:663-665`). The only
pre-advertising path it supports is the narrower "surviving announced central"
re-announce used by the reset-on-init contract.

## Why it matters

A test fake that *forbids* a scenario the real platforms *produce* means the
library's handling of inherited connections (immediate reporting, lifecycle
identification of a client that was never seen to connect during this
advertising session) is untestable, and any regression in that handling ships
silently. This is also a fidelity bug in the fake: it encodes an invariant —
"connections only happen while advertising" — that is false on both platforms.

## Rough approach

Drop or soften the advertising guard: allow `simulateCentralConnection` while
not advertising (matching native behavior of reporting all connections
regardless of advertising state), or add an explicit
`simulateInheritedCentralConnection` seam if keeping the guard is valuable for
catching test-authoring mistakes. Then add coverage for the inherited-central
flow: server created → central appears pre-advertising → lifecycle
identification proceeds normally.

## Related

- The platform behavior: `bluey_android/ANDROID_BLE_NOTES.md` §"iOS Interoperability" (iOS connection caching; connections reported regardless of advertising state).
- The narrower existing path: reset-on-init survivor re-announce from [I338](I338-lifecycle-silence-emits-disconnect-without-gatt-teardown.md).
- Audit that identified the gap: [2026-07-10 networking-scenario test audit](../reviews/2026-07-10-networking-scenario-test-audit.md) (addendum scenario 11).
