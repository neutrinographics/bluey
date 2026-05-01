---
id: I059
title: BlueyServer.removeService doesn't await the platform call
category: bug
severity: low
platform: domain
status: fixed
last_verified: 2026-05-01
fixed_in: 6ebcf53
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

Fixed in `6ebcf53`. `Server.removeService` return type changed from `void`
to `Future<void>`. `BlueyServer.removeService` now awaits the platform call;
platform exceptions propagate to the caller. Two new domain-layer tests
cover both halves: a `Completer`-gated test proves the wrapper future is
gated on platform completion (would resolve in the first microtask under
fire-and-forget), and a throw-injection test asserts platform exceptions
reach the caller (would be swallowed as an unhandled microtask error
under fire-and-forget). Breaking API change.

I086 (`removeService` races with in-flight notify fanout) is now
addressable from the consumer side: `await server.removeService(uuid)`
sequences cleanly with notify fanout discipline.
