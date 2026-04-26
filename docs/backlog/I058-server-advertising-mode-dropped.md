---
id: I058
title: BlueyServer.startAdvertising drops user-supplied advertising mode
category: bug
severity: medium
platform: domain
status: open
last_verified: 2026-04-26
related: [I051]
---

## Symptom

A consumer calling `server.startAdvertising(mode: AdvertiseMode.lowPower)` sees no effect on Android — the advertising interval remains the default. The `mode` parameter is silently dropped between Dart and the platform.

## Location

`bluey/lib/src/gatt_server/bluey_server.dart:173-179`.

```dart
final config = platform.PlatformAdvertiseConfig(
  name: name,
  serviceUuids: services?.map((u) => u.toString()).toList() ?? [],
  manufacturerDataCompanyId: manufacturerData?.companyId,
  manufacturerData: manufacturerData?.data,
  timeoutMs: timeout?.inMilliseconds,
  // mode: ???   <- not passed
);
```

The `Server.startAdvertising` interface doesn't expose `mode` at all — so the issue is twofold: (a) the public API doesn't have the parameter, and (b) even if added, the platform-config builder would need updating.

## Root cause

Implementation oversight. The platform interface already supports it (`PlatformAdvertiseConfig.mode`), the Pigeon DTOs support it (`AdvertiseConfigDto.mode` with `AdvertiseModeDto` enum), the Android side honors it — but the Dart-side public Server interface and `BlueyServer.startAdvertising` don't propagate it.

## Notes

Two-step fix:

1. Add `AdvertiseMode` enum to the public domain layer (`bluey/lib/src/gatt_server/server.dart` or similar).
2. Add `mode` parameter to `Server.startAdvertising`, default to `balanced`, propagate to `PlatformAdvertiseConfig.mode` in `BlueyServer`.

Document loudly that `mode` is Android-only — iOS manages advertising intervals automatically.

This is a subset of I051 (advertising options not exposed) but specifically the `mode` parameter has all the plumbing in place; only the final hop is missing.

External references:
- Android [`AdvertiseSettings.Builder.setAdvertiseMode(int)`](https://developer.android.com/reference/android/bluetooth/le/AdvertiseSettings.Builder#setAdvertiseMode(int)).
