---
id: I013
title: Scan failure error code discarded
category: bug
severity: medium
platform: android
status: fixed
last_verified: 2026-11-27
fixed_in: fcfc6d1
historical_ref: BUGS-ANALYSIS-#15
---

## Symptom

When Android's `BluetoothLeScanner` fails to start a scan, `onScanFailed(errorCode)` fires with a specific reason (already-started, registration failed, feature unsupported, internal error). Bluey collapses all of these into a generic `onScanComplete` event. Callers can't tell whether the scan ended normally or blew up, and can't react to `SCAN_FAILED_FEATURE_UNSUPPORTED` differently from a transient error.

## Location

`bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/Scanner.kt:83-88` — `onScanFailed` calls `onScanComplete` and drops the error code.

## Root cause

No error-shaped event in the Pigeon API. `onScanComplete` is a void signal.

## Notes

Fix sketch:

1. Add a `ScanError` Pigeon event — `{code: int, message: String}`. Map each Android `SCAN_FAILED_*` constant to a human-readable message.
2. On Dart side, the scan stream emits a `ScanException` via `_scanController.addError(...)` and then closes.
3. Define a domain-level `ScanException` with a typed reason enum so callers can match.

iOS has a parallel need — `centralManager(_:didDiscover:...)` doesn't have a failure mode but state changes like `.unauthorized` / `.poweredOff` during a scan should surface similarly. A shared domain type covers both.

## Audit 2026-11-17

The [2026-11-17 audit](../reviews/2026-11-17-correctness-and-test-rig-audit.md) (M2) adds that the Dart adapters do not await `startScan` (`android_scanner.dart:27`, `ios_scanner.dart:26`). When the native side rejects it, for instance with no scan permission on a first run, the rejection is an unhandled async error and the scan stream stays silent. Both are the missing error channel for scanning, so they are fixed together. Test: `M2 (I013)` in `bluey_android/test/known_defects/android_adapter_known_defects_test.dart`. Closed by slice 2 (scanning and advertising sessions) of the architecture foundation ([design](../superpowers/specs/2026-11-17-architecture-foundation-design.md)).

## Fixed

Slice 2, scanning pull request ([design](../superpowers/specs/2026-11-27-scanning-and-advertising-sessions-design.md)). Both Dart adapters handle the future of `startScan` and a refusal is an error on the platform scan stream (`fcfc6d1`). Android's `onScanFailed` reports its code through a new Pigeon callback, `onScanFailed(errorCode)`, mapped to `PlatformScanFailedException` and its reason. Discovery's `PlatformScanning` turns that into a `ScanFailure`, and the edge turns it into `ScanFailedException(reason)` (`fcfc6d1`). The known-defect test moved into `bluey_android/test/android_scanner_test.dart`, and with it `bluey_android` has no known defects left. The Kotlin change (`Scanner.kt`, `ScannerTest.kt`, the generated `Messages.g.kt`) has no cloud gate: its Gradle run is on Joel's Mac.
