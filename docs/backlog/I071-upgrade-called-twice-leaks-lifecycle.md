---
id: I071
title: "`BlueyConnection.upgrade()` called twice leaks the previous lifecycle"
category: bug
severity: medium
platform: domain
status: open
last_verified: 2026-04-23
related: [I070]
---

## Symptom

`BlueyConnection.upgrade(lifecycleClient:, serverId:)` assigns `_lifecycle = lifecycleClient` without checking whether `_lifecycle` was already set. If upgrade is called twice — for example, a spurious `onServicesChanged` during an in-progress upgrade, or a lifecycle retry — the first `LifecycleClient` is replaced in place without being stopped. Its timers continue firing.

## Location

`bluey/lib/src/connection/bluey_connection.dart:260-272` (approximately — the `upgrade()` method body).

## Root cause

No idempotency check. Assignment overwrites the reference.

## Notes

Fix: at the top of `upgrade()`, if `_lifecycle != null`, either (a) stop and replace, or (b) skip. Skip is safer — double-upgrade is a caller bug, and silently replacing masks it.

Adjacent concern also worth addressing in the same PR: `_handleServiceChange()` calls `_tryUpgrade()` from a service-change event; `Bluey.connect()` also calls it. Both paths can race if services change during the initial discovery. Guarding with `_upgrading` (already present) + idempotent `upgrade()` covers it.
