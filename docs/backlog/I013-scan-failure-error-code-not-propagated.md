---
id: I013
title: Scan failure error code discarded
category: bug
severity: medium
platform: android
status: open
last_verified: 2026-04-23
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
