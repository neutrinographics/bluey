---
id: I206
title: Android force-kill has no cleanup hook
category: limitation
severity: low
platform: android
status: wontfix
last_verified: 2026-04-23
---

## Rationale

When an Android app is force-killed (swipe from recents, `kill` command, `Ctrl+C` on `flutter run`), no lifecycle callbacks fire. The process terminates immediately. BLE connections may persist at the OS / Bluetooth-stack level until they timeout (typically 20–30 seconds) or the remote peer disconnects.

## Current mitigation

Bluey cleans up on normal app close via `ActivityLifecycleCallbacks.onActivityDestroyed` and `onDetachedFromActivity`. For force-kill, the library accepts that connections briefly persist and relies on remote-side timeouts.

The lifecycle control service (see I201) helps here too — a force-killed Bluey client stops sending heartbeats, so the server detects the gap within `lifecycleInterval`.

## Decision

Wontfix at the OS level. No workaround exists.

## Notes

If force-kill cleanup becomes critical (e.g., for connection-density-constrained environments), the option is to expose a pre-kill hook through a background service, but that adds significant complexity and permission requirements (foreground service notification, etc.).
