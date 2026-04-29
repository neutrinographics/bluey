---
id: I092
title: Scan errors not translated to domain exceptions
category: bug
severity: medium
platform: both
status: fixed
last_verified: 2026-04-29
fixed_in: 8fd3428
related: [I013, I099]
---

> **Fixed 2026-04-29** as part of the I099 typed-error-translation rewrite. `BlueyScanner.scan`'s `onError` handler now calls `translatePlatformException` (the pure form, since stream onError is sync) before forwarding on the domain stream's error channel. Subscribers pattern-matching on `BlueyException` see the typed contract on scan errors for the first time.

## Symptom

The scan stream on both platforms is a bare `StreamController<PlatformDevice>.broadcast()`. Error events — adapter off mid-scan, permission revoked, Android's `onScanFailed`, iOS's `.unauthorized` / `.poweredOff` state change — either don't propagate at all (see I013 for the Android error-code drop) or propagate as raw `PlatformException` through the stream's error channel.

Callers pattern-matching on Bluey exceptions (`PermissionDeniedException`, `BluetoothOffException`) miss scan errors entirely.

## Location

`bluey_android/lib/src/android_scanner.dart:11-54`, `bluey_ios/lib/src/ios_scanner.dart:11-57`.

## Root cause

No translation layer between the scan stream and the domain exception hierarchy. Each platform scanner just pipes PlatformDevices through and ignores errors.

## Notes

Fix: introduce a typed `ScanException` on the domain side, and make each platform adapter translate its native errors (Android `ScanFailedException`, iOS `CBManagerState.unauthorized/.poweredOff`) into `ScanException(reason: …)` dispatched via `_scanController.addError`.

Related: I013 covers the Android-native side of this (error code discarded in `onScanFailed`). Fixing both together is natural.
