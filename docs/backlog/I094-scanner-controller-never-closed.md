---
id: I094
title: Scanner broadcast controllers never closed on either platform
category: bug
severity: medium
platform: both
status: open
last_verified: 2026-04-23
---

## Symptom

`AndroidScanner._scanController` and `IosScanner._scanController` are created as broadcast `StreamController<PlatformDevice>` in constructors. Neither has a `dispose()` or close path — they live for the lifetime of the scanner (which is the lifetime of the Bluey instance). If an app creates multiple `Bluey()` instances over its lifetime, each scanner's controller leaks.

Not a production-critical leak because a typical app creates one `Bluey` and keeps it for the session. Becomes an issue in tests (fresh Bluey per test), or in advanced reconfig flows that recreate the plugin.

## Location

`bluey_android/lib/src/android_scanner.dart:11-54`, `bluey_ios/lib/src/ios_scanner.dart:13-56`.

## Root cause

No `dispose()` method on the scanner class. The parent `Bluey` object also doesn't propagate a dispose call.

## Notes

Fix: add `dispose()` to each platform scanner that closes `_scanController` (and cancels any active scan). Wire through `Bluey.dispose()` (which... may not exist as a public method yet; worth verifying).

Same pattern as the Android/iOS server controllers (I095). Consider a uniform disposal pattern across both.
