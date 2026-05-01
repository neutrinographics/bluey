---
id: I058
title: BlueyServer.startAdvertising drops user-supplied advertising mode
category: bug
severity: medium
platform: domain
status: fixed
last_verified: 2026-05-01
fixed_in: 6ebcf53
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

Fixed in `6ebcf53`. Public-domain `AdvertiseMode` enum
(`lowPower` / `balanced` / `lowLatency`) added to
`bluey/lib/src/gatt_server/server.dart`. `Server.startAdvertising` gained an
optional `AdvertiseMode? mode` parameter (default `null` = let the platform
decide; the entry's original sketch suggested defaulting to `balanced` but
keeping it `null` preserves the iOS-noop story cleanly without forcing a
domain-level choice). `BlueyServer` translates via a new
`_mapAdvertiseModeToPlatform` helper, mirroring the existing
`_mapGattResponseStatusToPlatform` pattern. Documented as Android-only —
iOS ignores the value because CoreBluetooth manages intervals
automatically.

4 new tests in `bluey/test/bluey_server_test.dart` cover propagation of
each enum value plus the null-passthrough case. Remains a subset of I051
(scan/advertise options); other AdvertiseSettings.Builder fields stay open.

External references:
- Android [`AdvertiseSettings.Builder.setAdvertiseMode(int)`](https://developer.android.com/reference/android/bluetooth/le/AdvertiseSettings.Builder#setAdvertiseMode(int)).
