---
id: I014
title: Manufacturer data only first entry returned
category: bug
severity: low
platform: android
status: open
last_verified: 2026-04-23
historical_ref: BUGS-ANALYSIS-ANDROID-A9
---

## Symptom

BLE advertisements can carry multiple manufacturer-data entries, each keyed by a different 16-bit company ID. The scan result converter takes only the first entry from the `SparseArray`; anything else is dropped.

## Location

`bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/Scanner.kt:169-176` — explicitly reads `sparseArray.keyAt(0)` and `sparseArray.get(key)`.

## Root cause

Pigeon DTO models a single `(companyId, data)` pair, not a list. The native side was written to match. Multi-entry manufacturer data is uncommon but valid.

## Notes

Low priority — most beacons and peripherals emit a single manufacturer-data entry. Fix when extending the scan DTO for other reasons.

Fix: change the DTO field to `List<ManufacturerDataDto>` and iterate the `SparseArray` indices. iOS only surfaces one manufacturer-data key in `CBAdvertisementDataManufacturerDataKey` anyway, so iOS emits a single-element list.
