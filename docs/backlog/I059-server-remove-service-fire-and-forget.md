---
id: I059
title: BlueyServer.removeService doesn't await the platform call
category: bug
severity: low
platform: domain
status: open
last_verified: 2026-04-26
related: [I086]
---

## Symptom

A consumer calling `server.removeService(uuid)` returns synchronously (the method is declared `void`, not `Future<void>`), giving no signal of when the underlying platform call has completed or whether it failed. Errors from the platform-side removal are silently swallowed.

## Location

`bluey/lib/src/gatt_server/bluey_server.dart:158-160`.

```dart
@override
void removeService(UUID uuid) {
  _platform.removeService(uuid.toString());
}
```

The platform method returns `Future<void>` but the call site doesn't await it; the wrapper method's return type (`void`) makes it impossible for callers to await either.

## Root cause

API shape mismatch. The Server interface declared `removeService` as synchronous, but the underlying operation is asynchronous and can fail.

## Notes

Change `Server.removeService` to return `Future<void>`, await the platform call, propagate errors. This is a breaking API change; account for it in the next minor version.

This issue compounds with I086 (`removeService` races with in-flight notify fanout): with a fire-and-forget removal, the consumer cannot even sequence "stop fanning notifies before removing" without race windows.
