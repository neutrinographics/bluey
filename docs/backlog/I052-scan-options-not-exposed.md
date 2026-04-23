---
id: I052
title: Scan options not exposed (mode, RSSI filter, duplicates)
category: unimplemented
severity: medium
platform: both
status: open
last_verified: 2026-04-23
---

## Symptom

`Bluey.scan(...)` exposes service-UUID filtering and a timeout. It doesn't expose:

- **Scan mode** (Android): `SCAN_MODE_LOW_POWER` / `BALANCED` / `LOW_LATENCY`. Currently hardcoded.
- **Allow-duplicates / report mode** (Android `REPORT_DELAY` + `SCAN_RESULT_TYPE_FULL|ABBREVIATED`; iOS `CBCentralManagerScanOptionAllowDuplicatesKey`): by default iOS deduplicates the same peripheral unless this key is set; apps that want RSSI updates need dup-allow.
- **RSSI threshold filter** (Android 8+ via `ScanFilter.Builder().setRssiRange(...)`): pre-filter at OS level.
- **Manufacturer-data filter** (Android `ScanFilter.Builder().setManufacturerData(...)`): filter by company ID and pattern.
- **Service-data filter** (Android): filter by service data pattern.
- **Device-name filter** (Android).
- **Address filter** (Android `setDeviceAddress`, iOS not supported).

## Location

`bluey_android/.../Scanner.kt` — hardcoded scan settings and filters built from service UUIDs only.

`bluey_ios/.../CentralManagerImpl.swift` — `scanForPeripherals(withServices: options:)` call with `options = nil`.

Domain API: `Bluey.scan` accepts a minimal `ScanConfig`; fields listed above are missing.

## Root cause

Same as I051 — initial cut chose sensible defaults; the config DTO wasn't extended.

## Notes

Fix direction: extend `ScanConfig` with a structured `filter` (service UUIDs, manufacturer data, service data, name, address, RSSI range) and a structured `settings` (mode, allow-duplicates, report-delay). Map platform-appropriate subsets to each. Capability flags on the platform (I053) tell the domain what's supported.

Android has a documented foot-gun: background scans (outside an app-foreground service) are implicitly forced to `SCAN_MODE_OPPORTUNISTIC` and filtered. Worth a docs note if `ScanMode` becomes user-settable.
