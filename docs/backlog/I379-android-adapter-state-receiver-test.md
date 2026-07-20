---
id: I379
title: Drive the Android adapter-state receiver in a native test
category: enhancement
severity: low
platform: android
status: open
last_verified: 2026-07-19
related: [I350, I351]
---

## What this is

`BlueyPlugin` registers a `BroadcastReceiver` for
`BluetoothAdapter.ACTION_STATE_CHANGED`
(`bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/BlueyPlugin.kt:707-725`)
that maps adapter transitions to a DTO and forwards them to Dart via
`flutterApi.onStateChanged`. No Kotlin test drives this receiver — nothing
fires `STATE_OFF`/`STATE_ON` through it and asserts the forwarded event or
any teardown behavior.

This is the unlanded native half of the 2026-07-10 networking-test audit's
recommendation R6 (finding NT-4, "adapter-off mid-operation is never driven
as a transport event"): the fake-platform half shipped
(`cascadeAdapterTeardown`), the native adapter-transition tests did not.
The iOS-central equivalent is blocked on the delegate seam tracked as
[I350](I350-ios-central-manager-delegate-seam.md) and is owned there.

## Notes

Extend the existing Kotlin captured-callback harness style: construct the
receiver (or invoke `onReceive` directly with a synthetic
`ACTION_STATE_CHANGED` intent), assert the mapped `onStateChanged` DTO for
each adapter state, and pin whatever mid-operation behavior the plugin is
supposed to exhibit on `STATE_OFF` (today: event forwarding only — if
teardown-on-off ever lands natively, this test is where it gets pinned).

Source finding: NT-4 / R6 in
`docs/reviews/2026-07-10-networking-scenario-test-audit.md`.
