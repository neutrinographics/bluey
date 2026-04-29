---
id: I071
title: "`BlueyConnection.upgrade()` called twice leaks the previous lifecycle"
category: bug
severity: medium
platform: domain
status: fixed
last_verified: 2026-04-29
fixed_in: ccb5dc6
related: [I070, I300]
---

> **Fixed (superseded by I300).** `BlueyConnection.upgrade()` no longer exists. The I300 connection / peer bounded-context refinement (`ccb5dc6`) removed `upgrade()`, `isBlueyServer`, `serverId`, the control-service filter, and late-upgrade entirely from `BlueyConnection`. Peer-protocol concerns now live exclusively in `PeerConnection` (composition wrapper); a peer wrapper is constructed once with a fresh `LifecycleClient` and never mutated in place. Double-upgrade is impossible by construction.
>
> The 2026-04-26 note about `bluey_peer_test.dart` exercising a leaked OLD lifecycle is now stale: post-I300, `BlueyPeer.connect` (`bluey/lib/src/peer/bluey_peer.dart`) constructs exactly one `LifecycleClient` and hands it to `PeerConnection.create`. There is no second one to leak.
>
> Follow-up cleanup (out of scope for this entry): the test's lifecycle-timeline comments still reference the pre-I300 "OLD lifecycle's death watch" framing. Worth a comment-only refresh next time the file is touched, but the test itself is correct.

## Symptom

`BlueyConnection.upgrade(lifecycleClient:, serverId:)` assigns `_lifecycle = lifecycleClient` without checking whether `_lifecycle` was already set. If upgrade is called twice — for example, a spurious `onServicesChanged` during an in-progress upgrade, or a lifecycle retry — the first `LifecycleClient` is replaced in place without being stopped. Its timers continue firing.

## Location

`bluey/lib/src/connection/bluey_connection.dart:260-272` (approximately — the `upgrade()` method body).

## Root cause

No idempotency check. Assignment overwrites the reference.

## Notes

Fix: at the top of `upgrade()`, if `_lifecycle != null`, either (a) stop and replace, or (b) skip. Skip is safer — double-upgrade is a caller bug, and silently replacing masks it.

Adjacent concern also worth addressing in the same PR: `_handleServiceChange()` calls `_tryUpgrade()` from a service-change event; `Bluey.connect()` also calls it. Both paths can race if services change during the initial discovery. Guarding with `_upgrading` (already present) + idempotent `upgrade()` covers it.

**2026-04-26: a test in `bluey/test/peer/bluey_peer_test.dart` ("disconnects when heartbeat write fails") was found to be unintentionally exercising the leaked OLD lifecycle rather than the timeout the test passes to `createBlueyPeer`.** `BlueyPeer.connect` calls `blueyConnection.services()` which itself runs `_tryUpgrade` and installs a first `LifecycleClient` (using `BlueyConnection`'s own `_peerSilenceTimeout`). The peer code then constructs a *second* `LifecycleClient` and calls `upgrade(...)` again — but `LifecycleClient.start` on the second one finds no control service (post-upgrade `services()` filters it out) and returns silently, so the second client is never started. The first one keeps running and is the one whose death watch actually fires.

When I017 changed `BlueyConnection`'s `_peerSilenceTimeout` default from 20 s to 30 s, the OLD lifecycle's deadline shifted past the test's elapse window and the test failed. Workaround applied: bumped the test's elapse to 40 s and added a comment pointing at this entry.

Once I071 is fixed (idempotent or stop-and-replace `upgrade()`), the test should be rewritten to actually exercise the `createBlueyPeer(peerSilenceTimeout: ...)` value rather than relying on a leaked-lifecycle side effect. Until then the workaround is correct but misleading.
