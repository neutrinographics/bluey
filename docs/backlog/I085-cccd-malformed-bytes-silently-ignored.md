---
id: I085
title: Android CCCD write with malformed bytes is silently ignored
category: bug
severity: medium
platform: android
status: open
last_verified: 2026-04-23
---

## Symptom

`onDescriptorWriteRequest` for CCCD (`0x2902`) checks three specific byte patterns: enable-notification (`0x01, 0x00`), enable-indication (`0x02, 0x00`), disable (`0x00, 0x00`). A write with a different byte pattern — malformed value, wrong length, spec-noncompliant client — falls through all three `contentEquals` checks. The auto-response at the end of the callback still fires `GATT_SUCCESS`, so the client thinks the CCCD write succeeded, but the server's subscription state is unchanged.

Extra problem: `contentEquals` on different-length arrays returns false cleanly, but the implicit assumption is that the CCCD value is exactly 2 bytes. A 1-byte or 3-byte write misleads the server silently.

## Location

`bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/GattServer.kt:511-527` — the CCCD write classifier.

## Root cause

No fallback/error branch. Silent-ignore was probably the "conservative" choice but it masks real spec violations.

## Notes

Fix: add an `else` branch. On unrecognized CCCD value, return `GATT_REQUEST_NOT_SUPPORTED` (0x06) in the response, and optionally log at warning level. The malformed client learns the write was rejected.

Consequence today: a buggy client that writes `0x03, 0x00` (undefined bits) gets `GATT_SUCCESS` but never receives notifications — and has no way to diagnose why.

Related: once I020/I021 lands (server read/write go through Dart), this CCCD validation could be promoted to Dart level for unified handling across platforms.
