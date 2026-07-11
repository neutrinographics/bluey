---
id: I369
title: Close per-device adapter controllers on failed and spontaneous disconnects
category: bug
severity: medium
platform: both
status: open
last_verified: 2026-07-10
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
