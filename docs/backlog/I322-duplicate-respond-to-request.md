---
id: I322
title: Duplicate `respondTo*Request` invocation; second response fails with `RespondNotFoundException`
category: bug
severity: medium
platform: both
status: open
last_verified: 2026-05-05
related: [I308, I313, I321]
---

## Symptom

In production a connected Android central → iOS server pair, after the
I313 cross-platform discovery fix, exhibits a recurring crash with the
following signature on the iOS server side:

```
[WARN ] bluey.ios.peripheral: respondToReadRequest: requestId not found
        {requestId: <id>} err=not-found
[ERROR] (unhandled) PlatformException(bluey-not-found, ...)
```

The crash fires at a deterministic ~30-second cadence — matching the
discovery probe frequency on the central side. Each discovery round
issues a read on `b1e70004` (the lifecycle `serverId` characteristic).

The proximate cause is a fire-and-forget `_platform.respondToReadRequest`
in `LifecycleServer.handleReadRequest`. The defensive containment
(typed-exception chain + warn/error log) shipped in this PR; that work
stops the crash but does not address the underlying issue: **why is the
lifecycle handler responding to the same `requestId` more than once**?

**Note on `platform: both`.** The crash *surfaces* in domain code
(`bluey/lib/src/gatt_server/lifecycle_server.dart`), but the root cause
is upstream — the top-ranked hypothesis (broadcast-stream
multi-subscriber) lives at the iOS-plugin / platform-interface seam,
and an Android-side equivalent likely exists. The investigation plan
below is intentionally cross-layer; the eventual fix may split into
separate per-layer follow-ups once the layer responsible is
identified.

## Location

- `bluey/lib/src/gatt_server/lifecycle_server.dart:_respondAndContain`
  — the containment is in place; the duplicate-invocation root cause is
  upstream.
- `bluey_ios/lib/src/ios_server.dart` — `_readRequestsController` is a
  *broadcast* `StreamController` (verified at lines 20-21 in the I313
  investigation); multiple subscribers all receive every emission.
- `bluey/lib/src/gatt_server/bluey_server.dart` — `BlueyServer`
  subscribes to `_platform.readRequests` in its constructor and only
  cancels the subscription in `dispose()`.

## Root cause (hypotheses, ranked)

**1. Multi-subscriber on the broadcast `readRequests` stream.** If two
`BlueyServer` instances are alive simultaneously, both subscribe to
`_platform.readRequests` and both invoke
`LifecycleServer.handleReadRequest(req)` for each emission. Both
attempt `respondToReadRequest(req.requestId, ...)` — first wins, second
hits "not found." Plausible scenarios:

- Hot reload (Flutter rebuilds Dart-side state but the iOS native
  plugin's `_readRequestsController` survives across reloads, so the
  old `BlueyServer`'s subscription stays alive while a new one
  registers).
- An app-level path that constructs a second `BlueyServer` without
  disposing the first (audit `bluey/example/lib/features/server/`
  callsites).
- A `dispose-without-await` race that returns control before the
  subscription is fully canceled.

**2. Duplicate emission from the platform side.** The iOS plugin's
`didReceiveRead` always assigns a fresh `requestId` (incrementing
counter) and calls `flutterApi.onReadRequest(...)` once per
`CBATTRequest`. Pigeon's `flutterApi.onReadRequest` is generated to
deliver each call exactly once. **Unlikely**, but worth ruling out by
adding a unique-id check in `_readRequestsController.add(...)`.

**3. `closeServer` racing in-flight responds.** Possible but should
fire only on teardown; doesn't fit the steady-state cadence. Low
probability.

## Notes

**Defense-in-depth shipped (this PR):** the typed-exception chain
(`BlueyError.pendingRequestNotFound` →
`PlatformRespondToRequestNotFoundException` →
`RespondNotFoundException`) plus `_respondAndContain` in
`lifecycle_server.dart` log warn-and-move-on on the expected race and
surface unexpected failures at error level. App code no longer crashes
on this. The trace-level log on entry carries `requestId`,
`characteristicUuid`, and `branch` (`serverId` / `interval`) so
investigators can correlate.

**Symmetric `respondToWriteRequest`:** lifecycle_server.dart's
`handleWriteRequest` (around the response path) also calls
`_platform.respondToWriteRequest` fire-and-forget. The same
defense-in-depth should apply. The Swift split shipped in this PR
already covers both call sites (`PeripheralManagerImpl.swift:296` and
`:316` both raise `BlueyError.pendingRequestNotFound`), but the Dart
adapter wrapper in `IosServer` and the lifecycle_server.dart wrapper
only cover reads. Schedule writes as a small follow-up commit.

**Android equivalent:** the Android plugin has an analogous
pending-request map. Verify the equivalent error code propagates
through `_translateGattPlatformError` (or its server-side counterpart)
and add the same `PlatformRespondToRequestNotFoundException`
translation. Without it, Android servers that hit the same
multi-subscriber issue would still crash with a generic
`bluey-unknown`. Out of scope for this PR; small follow-up.

**Investigation plan:**

1. Capture a fresh failure with the new trace log enabled. Confirm the
   `branch` and `characteristicUuid` consistently match (i.e., it's
   always the same characteristic firing).

2. Add a duplicate-emission guard at the platform-interface layer
   (debug build only): if the same `req.requestId` is observed on
   `_platform.readRequests` more than once within ~1 second, log at
   error level. This will distinguish hypothesis 1 from hypothesis 2.

3. Audit `BlueyServer` lifecycle:
   - Does `dispose()` await `_platformReadRequestsSub?.cancel()`? Yes,
     verified — but does the example app actually await
     `BlueyServer.dispose()` before constructing a new one?
   - Hot reload: does the iOS plugin re-init `_readRequestsController`
     on `BlueyPlugin.handleHotRestart` (or equivalent)? Audit.

4. Once root cause is identified, implement the fix and remove the
   `// see I322` comment from `lifecycle_server.dart`'s
   `_respondAndContain`.

External references:
- BLE Core Specification 5.4 Vol 3 Part F — ATT request/response semantics.
