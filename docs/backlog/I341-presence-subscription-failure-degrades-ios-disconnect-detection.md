---
id: I341
title: A failed presence-characteristic subscription silently degrades iOS-server disconnect detection for that peer
category: bug
severity: low
platform: ios
status: open
last_verified: 2026-06-02
related: [I338, I201, I340]
---

> **Corner case — deferred.** Address when hit in the field or when there's
> time. Not a blocker for the Pattern B landing (PR #37). The realistic
> transient cause (a CCCD-write failure on an otherwise-healthy link) is
> rare; the global `reportsCentralDisconnects == false` fallback and the
> client-side `warn` log already bound the impact.

## Symptom

Under Pattern B ([I338](I338-lifecycle-silence-emits-disconnect-without-gatt-teardown.md)),
a latest-protocol Bluey client subscribes to the presence notify
characteristic (`b1e70005-…`) on connect, and the iOS server infers a
disconnect from `didUnsubscribeFrom(presence)`. If that subscription
**fails** (e.g. the CCCD write fails transiently — GATT busy, timing — on
an otherwise-healthy link), the peer is silently downgraded to
"undetectable disconnect" *on an iOS server only*.

## What happens today (traced)

- **Client** (`LifecycleClient.start`): `notifications.listen` errors →
  `onError` logs a `warn` (`bluey.connection.lifecycle`,
  "presence subscription error…"). `start()` otherwise proceeds normally —
  the heartbeat timer arms, heartbeats flow, the client is identified as a
  peer. The connection looks healthy; only disconnect detection is degraded.
  There is **no retry** — a notification `listen` does the CCCD write once.
- **iOS server**: `didSubscribeTo(presence)` never fires (the write never
  landed). The central is still tracked (its heartbeat writes reach the
  server) and identified, but with no presence subscription. On link loss:
  no `didUnsubscribe(presence)`, no native callback (I201), silence is
  advisory (`reportsCentralDisconnects == true`) → returns early →
  **`disconnections` never fires; the session leaks until the server
  restarts.** The server has no idea — only the client logged the failure.
- **Android server**: unaffected — `onConnectionStateChange` detects the
  disconnect regardless of presence. No leak.

## Proposed fix (when actioned)

**Client-side bounded retry** of the presence subscription. The failure is
detectable exactly where it occurs (the client), and a retry is harmless on
any server platform (no-op benefit on Android; re-arms the disconnect signal
on iOS). The client does not know the server's platform, so it must not fail
the connection on subscribe failure (that would wrongly kill a healthy
Android-server link).

- On presence-subscribe `onError`, re-attempt a small number of times
  (suggested: 3 attempts, ~500 ms backoff — virtual-time in tests).
- Self-heals the realistic transient case.
- If exhausted, keep the current `warn` log; the residual collapses into the
  already-documented "no presence signal" gap, with the global
  `reportsCentralDisconnects=false` fallback behind it.
- Local to `LifecycleClient`; no protocol/architecture change; CI-testable
  with the fake under virtual time (inject a `setNotification` failure →
  assert retry → success, or exhaust → log).

## Rejected alternatives

- **Fail the connection on subscribe failure** — aggressive, and wrong for an
  Android server where presence is irrelevant; the client can't tell which.
- **Server-side eviction of non-subscribers** — blocked by I207 (iOS can't
  force-disconnect a central) and re-opens the per-client authoritative gate
  that was deliberately deferred (it was mostly a backwards-compatibility
  concern, and the project supports only latest-protocol Bluey clients +
  non-Bluey devices).

## Scope note

Out of scope: old Bluey clients that predate the presence characteristic.
The project does not target protocol backwards-compatibility — only
latest-protocol Bluey clients (which subscribe) and non-Bluey clients (which
never heartbeat, so they are not subject to the silence path; their
disconnects on an iOS server are bounded by the pre-existing I201 limit, not
by this issue).
