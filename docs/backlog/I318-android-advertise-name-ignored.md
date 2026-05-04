---
id: I318
title: Android `config.name` silently ignored; system Bluetooth adapter name advertised instead
category: bug
severity: medium
platform: android
status: open
last_verified: 2026-05-04
related: [I051, I205, I313]
---

## Symptom

Caller passes `Server.startAdvertising(name: 'Bluey Demo')`. On Android the
advertisement carries the **system Bluetooth adapter name** (e.g. "Pixel 6a") —
the string the caller passed never reaches the wire. iOS honors the
parameter. Behavior is platform-divergent without any signal to the caller.

## Location

`bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/Advertiser.kt:107-111`

```kotlin
val scanResponseBuilder = AdvertiseData.Builder()
    .setIncludeDeviceName(config.name != null)
```

`config.name` is treated purely as a boolean — the string itself is dropped.

## Root cause

Android's `AdvertiseData.Builder` has no API to set a custom Complete Local
Name (AD type 0x09). `setIncludeDeviceName(true)` causes the BLE stack to
read `BluetoothAdapter.getName()` at advertise time. The Kotlin code didn't
compensate for that constraint.

## Notes

Two ways to honor `config.name`:

1. **Temporarily set the adapter name.** Cache `BluetoothAdapter.getName()`,
   call `BluetoothAdapter.setName(config.name)` before `startAdvertising`,
   restore in `stopAdvertising` / `cleanup`. Side-effects: changes the
   system BT name visible in classic-BT pairing dialogs and other scanners
   while advertising, requires `BLUETOOTH_CONNECT` on Android 12+, and is
   async (the adapter takes a moment to apply; ideally wait for
   `ACTION_LOCAL_NAME_CHANGED`). On crash between set and restore, the
   adapter is left renamed until the user toggles Bluetooth or the app
   restarts and runs cleanup.
2. **Document the limitation and rename the parameter.** Drop `name` from
   the Android-affecting surface and replace with
   `includeDeviceName: bool`. Less honest API for cross-platform callers,
   but no surprises and no system-wide side-effects.

Either way, encode the divergence in `Capabilities` (cf. I053) so callers can
branch deliberately. Consider folding the fix into the I051 (advertising
options not exposed) bundle — same Advertiser surface, same DTO.
