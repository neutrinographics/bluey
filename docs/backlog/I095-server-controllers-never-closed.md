---
id: I095
title: AndroidServer / IosServer broadcast controllers never closed
category: bug
severity: medium
platform: both
status: open
last_verified: 2026-04-23
related: [I094]
---

## Symptom

Four broadcast stream controllers (`_centralConnectionsController`, `_centralDisconnectionsController`, `_readRequestsController`, `_writeRequestsController`) are created in both `AndroidServer` and `IosServer` constructors. Neither class has a `dispose()` method. Controllers live for the life of the Bluey instance.

Similar lifecycle concern to I094 but for server-side streams. Same test-instance / reconfig-flow pitfall.

## Location

`bluey_android/lib/src/android_server.dart:13-20`, `bluey_ios/lib/src/ios_server.dart:16-23`.

## Root cause

No disposal contract for platform server adapters. The domain-level `BlueyServer` does close its own controllers in `dispose()` (confirmed at `bluey_server.dart:339-342`), but the underlying platform-adapter controllers it reads from aren't closed.

## Notes

Fix: add `dispose()` to both platform server classes that closes all four controllers. Wire through `BlueyServer.dispose()` which currently only closes domain-level controllers.

Downstream maps from request controllers (in `BlueyServer.readRequests` / `writeRequests` getters) should also be reviewed; see I015-related concern.
