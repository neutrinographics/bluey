---
id: I015
title: GATT server close order on engine detach
category: bug
severity: low
platform: android
status: open
last_verified: 2026-04-23
historical_ref: BUGS-ANALYSIS-ANDROID-A8
---

## Symptom

Two independent cleanup paths touch the Android GATT server: `Application.ActivityLifecycleCallbacks.onActivityDestroyed` and `FlutterPlugin.onDetachedFromEngine`. Depending on which runs first and whether `cleanupOnActivityDestroy` is configured, the server may be double-closed, or closed in a state where Flutter API calls post-detach silently no-op.

## Location

`bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/BlueyPlugin.kt:100-118` (activity-lifecycle path) and `:149-159` (engine-detach path) — both call `gattServer?.cleanup()`.

## Root cause

Redundant cleanup entry points without idempotency guarantees. Each `cleanup()` is locally safe but there's no central state machine saying "the server is torn down" to prevent double-tear-down.

## Notes

Low severity — most users experience this as benign logs on app close. Fix either by consolidating to a single cleanup coordinator or making every resource's `cleanup()` a strict idempotent no-op-after-first-call.

Would become more important if the plugin grows more detach-time state (e.g., the lifecycle control service already does some teardown; its ordering relative to this matters).
