---
id: I326
title: `AndroidConnectionExtensions.mtu` does not auto-update on spontaneous MTU renegotiation
category: bug
severity: low
platform: android
status: open
last_verified: 2026-05-05
related: [I325]
---

## Symptom

After I325 lands, Android exposes `connection.android?.mtu` as the cached negotiated MTU. The cache is updated in two places:

- When `requestMtu()` returns successfully (Dart-side cache write).
- (Not yet) when the platform fires `onMtuChanged` spontaneously.

Android's native plugin already fires `flutterApi.onMtuChanged(MtuChangedEventDto)` whenever `BluetoothGattCallback.onMtuChanged` triggers — including for renegotiations initiated by the peer or by the platform itself. The Dart side currently ignores this event.

Result: if the peer renegotiates the MTU after the initial `requestMtu` call, `connection.android?.mtu` reports a stale value. `connection.maxWritePayload()` is unaffected because it round-trips to the platform on each call, but anyone reading `mtu` directly for tuning / diagnostics gets the stale number.

## Location

- `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/ConnectionManager.kt` — `onMtuChanged` callback already fires `flutterApi.onMtuChanged(...)`.
- `bluey/lib/src/connection/bluey_connection.dart` — listens to platform events but does not handle `onMtuChanged` for the cached `_mtu` value.

## Fix sketch

Add an `onMtuChanged` event subscription in `BlueyConnection` (Android-only path, gated by capability) that updates the cached `_mtu` field. Verify with a fake-platform test that emits an `MtuChangedEvent` outside of an explicit `requestMtu` call and asserts the `android?.mtu` getter reflects the new value.

## Why low severity

- Most apps call `requestMtu` once at connect time and never renegotiate. The cache is correct for them.
- The application-facing `maxWritePayload` is correct regardless of cache state — it round-trips to the platform.
- The bug surfaces only for diagnostic readers of `connection.android?.mtu` after a peer-initiated renegotiation, which is rare in practice.
