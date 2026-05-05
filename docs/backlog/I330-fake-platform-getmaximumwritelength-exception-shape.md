---
id: I330
title: `FakeBlueyPlatform.getMaximumWriteLength` throws raw `Exception` instead of mimicking production `gatt-disconnected` shape
category: enhancement
severity: low
platform: domain
status: open
last_verified: 2026-05-06
related: [I325]
---

## Symptom

`bluey/test/fakes/fake_platform.dart` implements `getMaximumWriteLength` as:

```dart
Future<int> getMaximumWriteLength(String deviceId, {required bool withResponse}) async {
  // ... override or fallback ...
  final connection = _connections[deviceId];
  if (connection == null) {
    throw Exception('Not connected to device: $deviceId');
  }
  return connection.mtu - 3;
}
```

Production paths (Android `BlueyAndroidError.DeviceNotConnected`, iOS `BlueyError.notConnected`) surface to domain code as `GattOperationDisconnectedException` via `_translateGattPlatformError`. The fake throws a raw `Exception`, which the domain's `withErrorTranslation` wrapper does **not** map to `GattOperationDisconnectedException`.

A test asserting `expect(call(), throwsA(isA<GattOperationDisconnectedException>()))` against the fake would fail; tests today work because they either don't exercise the disconnect path or use higher-level `_ensureConnected` gating that throws `DisconnectedException` first.

## Location

- `bluey/test/fakes/fake_platform.dart` — the new `getMaximumWriteLength` override added in I325 (search for the method).

## Why low severity

- The pre-flight `_ensureConnected()` in `BlueyConnection.maxWritePayload` filters most disconnect paths before reaching the platform call.
- No current test asserts on the platform-call exception type for this method.
- Production-vs-fake exception-shape divergence is a generic test-fake concern that already exists for several other methods in the same fake (e.g. `requestMtu` also throws raw `Exception` for the same case).

## Fix sketch

Either:
1. Throw a typed exception that mirrors the production wire-level error, e.g. construct a `PlatformException(code: 'gatt-disconnected', ...)` so the domain wrapper translates it to `GattOperationDisconnectedException`. Match the iOS / Android error code.
2. Audit all `Exception('Not connected to device: ...')` throws in the fake and harmonize them as a single helper that emits the right wire-level error.

## Notes

Discovered during the I325 deep PR review. Pre-existing pattern; I325 inherited it for the new method. Consider bundling with a broader fake-fidelity sweep.
