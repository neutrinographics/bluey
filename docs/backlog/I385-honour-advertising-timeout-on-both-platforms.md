---
id: I385
title: Honour the advertising timeout on both platforms
category: bug
severity: medium
platform: both
status: open
last_verified: 2026-11-17
related: [I081, I051]
---

## Symptom

The advertising `timeout` is ignored on iOS. On Android the radio stops at the timeout but `isAdvertising` stays true natively and in the domain, so the next `startAdvertising` returns success without advertising. A timeout under 1 s becomes no timeout.

## Location

`bluey_ios/ios/Classes/PeripheralManagerImpl.swift:187-219`; `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/Advertiser.kt:47-50`, `:78-82`.

## Root cause

Found by reading, not run. The timeout is applied in the Android advertiser without telling the layers above it that advertising ended, and iOS has no timeout at all.

## Notes

Found by finding M8 of the [2026-11-17 audit](../reviews/2026-11-17-correctness-and-test-rig-audit.md).

Related to [I081](I081-advertiser-concurrent-start.md) and [I051](I051-advertising-options-not-exposed.md). The Dart half closes in slice 2 (the advertising session learns that advertising ended) and the native half in slice 4. No known-defect test yet: it gets one as the red step of its slice.
