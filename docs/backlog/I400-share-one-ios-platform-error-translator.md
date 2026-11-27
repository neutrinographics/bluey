---
id: I400
title: Share one iOS translator from platform errors to Bluey's exceptions
category: refactor
severity: low
platform: ios
status: open
last_verified: 2026-11-27
---

## Symptom

The iOS package turns the native `bluetooth-unavailable` error code into its Bluetooth-unavailable exception in four separate places: the scanner, the connection manager and twice in the server. Each copy reads the same code and answers the same exception, so a change to how iOS errors are read has to be made four times.

## Location

`bluey_ios/lib/src/ios_scanner.dart:49`, `bluey_ios/lib/src/ios_connection_manager.dart:65`, `bluey_ios/lib/src/ios_server.dart:31` and `:210`.

## Root cause

Each adapter grew its own translation when it first needed one. The scanner's was the third copy, added with the scan-failure work of slice 2.

## Notes

Found while reviewing slice 2's scanning pull request. Fix sketch: one `ios_errors.dart` in the iOS package that holds the translation, called by all four sites.
