---
id: I098
title: Coherent rewrite of Android ConnectionManager — threading invariants + disconnect lifecycle
category: bug
severity: high
platform: android
status: fixed
last_verified: 2026-04-27
fixed_in: 051f415
related: [I060, I061, I062, I064]
---

> **Fixed 2026-04-27.** Landed across 11 commits: `3962e43` (I064 dead-code purge), `d9e1e51` + `f9d83d4` (I062 threading), `424834c` + `5fac284` (concurrent-connect mutex with `ConnectInProgress`), `1ed0fb5` + `c70d6d0` (I060 disconnect lifecycle + 5 s fallback), `3563f52` + `33c48fb` (I061 cleanup contract), `051f415` (docs). 15 new JVM unit tests in `ConnectionManagerLifecycleTest.kt`. Manual on-device verification still pending. Spec: `docs/superpowers/specs/2026-04-27-android-connection-manager-rewrite-design.md`.


## Symptom

Three high-severity issues in `ConnectionManager.kt` are correctly diagnosed as separate backlog entries (I060 fire-and-forget disconnect, I061 cleanup orphans pending callbacks, I062 binder-thread mutation), plus the dead-code cleanup (I064). All four share the same file and overlapping fix logic. Fixing them piecemeal risks introducing new races between fixes.

## Location

`bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/ConnectionManager.kt`.

## Root cause

The class was iterated through Phase 2a/2b without a single coherent threading + lifecycle pass. Each phase added new invariants (handler, queue) but legacy state-management code wasn't refactored to use them consistently.

## Notes

Bundle as a single coherent rewrite:

1. **Delete legacy `pending*` and `pending*Timeouts` maps (I064).** These have been dead since Phase 2a. The cleanup paths still reference them; remove the references too.
2. **Wrap every `when` branch body of `onConnectionStateChange` in `handler.post` (I062).** Use the pattern from I062's fix sketch verbatim. After this, all map mutations are on the main thread.
3. **Make `disconnect()` await `STATE_DISCONNECTED` (I060).** Replace the synchronous `callback(Result.success(Unit))` with a pending completer registered before `gatt.disconnect()`. The `STATE_DISCONNECTED` branch invokes the completer.
4. **Add a 5-second fallback timer (I060/I061).** If `STATE_DISCONNECTED` doesn't fire, force-call `gatt.close()` and complete the callback with a synthesized `gatt-disconnected` error.
5. **Add a `connect()` mutex** to prevent the race documented in the review (two simultaneous connects to the same device).

The result is a single ~2-day PR that resolves four backlog entries and significantly reduces flakes under stress testing.

**Verification.** Once implemented, validate against the existing stress test suite (especially `runSoak` and `runFailureInjection`) to confirm no regressions. Add a multi-connect race test as suggested in I062's notes.

**Spec hand-off.** Suggested spec name: `2026-XX-XX-android-connection-manager-rewrite-design.md`.

External references:
- Punch Through, [Android BLE: The Ultimate Guide to Bluetooth Low Energy](https://punchthrough.com/android-ble-guide/).
- Martijn van Welie, [Making Android BLE Work — Part 2](https://medium.com/@martijn.van.welie/making-android-ble-work-part-2-47a3cdaade07).
- AOSP [`gatt_api.h`](https://android.googlesource.com/platform/external/bluetooth/bluedroid/+/master/stack/include/gatt_api.h).
