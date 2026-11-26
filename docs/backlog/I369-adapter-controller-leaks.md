---
id: I369
title: Close per-device adapter controllers on failed and spontaneous disconnects
category: bug
severity: medium
platform: both
status: fixed
last_verified: 2026-11-18
fixed_in: 79c6be2
related: [I381]
---

## Symptom

Both platform adapters insert per-device stream controllers *before*
the connect await and prune them only on explicit `disconnect()` — a
failed connect, a remote drop, or reconnect-without-disconnect leaks
or orphans them (audit DA-27, latent).

## Location

`bluey_android/lib/src/android_connection_manager.dart`,
`bluey_ios/lib/src/ios_connection_manager.dart` — `connect` /
`disconnect`.

## Notes

Prune and close in the terminal-disconnect state callback and on the
connect failure path (the R1 connect-translation work made those
failure paths typed and testable).

## Audit 2026-11-17

The [2026-11-17 audit](../reviews/2026-11-17-correctness-and-test-rig-audit.md) (M3) adds that a second `connect()` to a connected device replaces the per-device stream controllers in both adapters, so the first `Connection` stops receiving state changes and notifications and never learns the link dropped. The same gap seen from the domain is [I381](I381-remote-disconnect-never-finalises-connection.md). Test: `M3 (I369)` in `bluey_android/test/known_defects/android_adapter_known_defects_test.dart`. Closed by slice 1 (link lifecycle) of the architecture foundation ([design](../superpowers/specs/2026-11-17-architecture-foundation-design.md)).

## Fixed (2026-11-18)

Fixed in `79c6be2` (with `427c752`) by slice 1 (link lifecycle, [design](../superpowers/specs/2026-11-18-link-lifecycle-design.md) section 6.10). Each platform package's `DeviceStreams` owns a device's stream controllers: a second connect to a live device keeps the streams already handed out, and they are closed on the device's terminal disconnected report and when a connect fails, a failed second connect closing only the streams it opened. The M3 test moved into `bluey_android/test/android_connection_manager_test.dart`, its twin is in `bluey_ios/test/ios_connection_manager_test.dart`, and its name left `bluey_android`'s roster. `DeviceStreams` has since moved to `bluey_platform_interface`, held once for both platforms.
