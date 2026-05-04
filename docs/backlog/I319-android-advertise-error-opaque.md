---
id: I319
title: Android advertise-failure errors collapse to `bluey-unknown`; `DATA_TOO_LARGE` ambiguous under slot contention
category: bug
severity: low
platform: android
status: open
last_verified: 2026-05-04
related: [I051, I313, I318]
---

## Symptom

When the Android BLE stack rejects `BluetoothLeAdvertiser.startAdvertising`,
the failure surfaces to Dart as
`PlatformException(bluey-unknown, "<error string>", null)` — regardless of
which `AdvertiseCallback` error code fired. Callers have no programmatic
way to distinguish "data legitimately too large" from "too many concurrent
advertisers" from "Bluetooth daemon already started" from "internal error".

In particular, `ADVERTISE_FAILED_DATA_TOO_LARGE` (error code 1) is misnamed in
the AOSP stack: it also fires under advertiser-slot contention from other apps
(observed with Google Nearby Connections holding multiple slots, with the demo
app's advertisement well under the 31-byte budget — flags + one 128-bit UUID =
21 B primary, scan response with system name = ~10 B). The user sees an
"Advertise data too large" message that is literally untrue.

## Location

`bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/Advertiser.kt:140-152`
maps the Android error code to an English string and wraps in
`BlueyAndroidError.AdvertisingStartFailed(message)`.

`bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/Errors.kt:40-51`
(`toServerFlutterError`) then collapses every `BlueyAndroidError` (other than
`PermissionDenied` / `CentralNotFound` / `NoPendingRequest`) to
`FlutterError("bluey-unknown", message, null)`.

## Root cause

1. No typed domain exception per advertise-failure code — everything funnels
   into the generic `bluey-unknown` bucket via the catch-all branch.
2. The `DATA_TOO_LARGE` constant is overloaded by Android itself; Bluey just
   forwards the literal string without explaining the contention possibility.
3. No retry-on-contention or auto-fallback path (e.g. retry with
   `setIncludeDeviceName(false)` if a real overflow is suspected).

## Notes

Fix sketch (small):

- **Typed Pigeon codes per `AdvertiseCallback` error code.** Replace the
  catch-all `bluey-unknown` mapping with `bluey-advertise-data-too-large`,
  `bluey-advertise-too-many-advertisers`, `bluey-advertise-already-started`,
  `bluey-advertise-internal-error`, `bluey-advertise-feature-unsupported`.
  Surface as named domain exceptions in `bluey` so consumers can
  `try { startAdvertising() } on TooManyAdvertisersException { ... }`.
- **Compute the payload budget client-side and disambiguate
  `DATA_TOO_LARGE`.** Android's API only hands back an `int` error code,
  but `AOSP/BluetoothLeAdvertiser.totalBytes()` is fully deterministic from
  `AdvertiseData` + `BluetoothAdapter.getName().length`: 3 B flags (when
  connectable) + 2 B header per UUID-bitwidth class + (16/4/2 B per UUID)
  + 2 B header + manufacturer-data length + 2 B header + name length, etc.
  Mirror that in `Advertiser.kt`. On `DATA_TOO_LARGE` fire-time, attach
  the computed primary/scan-response sizes to the exception. If both are
  under 31 B, surface a message like:

  > "Android rejected advertising with DATA_TOO_LARGE, but computed payload
  > fits the 31-byte budget (primary=21 B, scan-response=10 B). This error
  > code is also returned under advertiser-slot contention from other BLE
  > apps (e.g. Google Nearby Connections). Stop conflicting apps and retry."

- **Add the missed `onStartFailure` log.** `Advertiser.kt:140-152` lacks the
  `BlueyLog.log(...)` call that `onStartSuccess` has — failures currently
  leave no trace in `bluey.android.advertiser`, only surfacing through the
  Pigeon error path. Should log alongside the size-disambiguation result so
  the Logcat / `bluey.logEvents` trail tells the full story.
- **Optional pragmatic auto-retry.** If `DATA_TOO_LARGE` fires *and* the
  computed payload is below the budget, retry once after a short delay
  before surfacing the error. Probably not worth the complexity until a
  concrete consumer needs it.
- **Dartdoc.** On `AdvertisingDataTooLargeException`, call out the
  Android conflation explicitly so callers know "data too large" can mean
  "stack under contention" — the size fields on the exception make this
  diagnosable without further log digging.

Pairs with I051 (advertise configurability) and I313 (scan-response slot)
but isn't subsumed by either — this is purely about the failure-translation
seam.
