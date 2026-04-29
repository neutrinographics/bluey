---
id: I310
title: iOS platform adapter throws Dart `UnsupportedError` for capability-gated ops; surfaces as `BlueyPlatformException` with null code
category: bug
severity: medium
platform: ios
status: open
last_verified: 2026-04-29
related: [I053, I065, I069, I099]
---

## Symptom

Real-device stress testing on Android-server / iOS-client (post-I099 typed-error rewrite) surfaced ~10 `BlueyPlatformException(code: null)` for the Mixed Ops test and 1 for the MTU probe. Tracking it back to the helper's catch ladder shows these errors hit the defensive `Object` backstop:

```dart
// bluey/lib/src/shared/error_translation.dart
return BlueyPlatformException(error.toString(), cause: error);
```

The message text comes from `error.toString()` and carries the descriptive prose, but the `code` field is `null` because the original error is not a typed platform-interface exception. Callers pattern-matching on a wire-level code can't distinguish "unsupported on this platform" from "unknown native error."

## Location

`bluey_ios/lib/src/ios_connection_manager.dart:255, 281, 296, 310, 319, 329` — five methods throw plain Dart `UnsupportedError`:

- `requestMtu` ("iOS does not support requesting a specific MTU.")
- `removeBond` ("iOS does not support removing bonds programmatically.")
- `getPhy` ("iOS does not support reading PHY information.")
- `requestPhy` ("iOS does not support requesting PHY settings.")
- `getConnectionParameters` ("iOS does not support reading connection parameters.")
- `requestConnectionParameters` ("iOS does not support requesting connection parameters.")

`bluey_ios/lib/src/bluey_ios.dart:124` has another `UnsupportedError` along the same lines.

## Root cause

iOS lacks the BLE capabilities Android exposes (no programmatic MTU request, no PHY API, no bond removal, no connection-parameter API). The iOS adapter signals "not supported" with Dart's built-in `UnsupportedError` rather than a typed platform-interface exception. The platform-interface error hierarchy (`GattOperation*Exception`, `PlatformPermissionDeniedException`) doesn't currently include an "unsupported operation" type, so there is no typed channel to use.

The I099 typed-translation rewrite cannot map these because they aren't in the typed hierarchy — the helper falls through to the catch-all `Object` backstop.

## Notes

Three fix shapes, in increasing order of cleanliness:

**Option A — surface as typed platform exception.** Add `PlatformUnsupportedOperationException` to `bluey_platform_interface/lib/src/exceptions.dart`:

```dart
class PlatformUnsupportedOperationException implements Exception {
  final String operation;
  final String reason; // e.g. "iOS does not support requesting MTU"
  const PlatformUnsupportedOperationException(this.operation, this.reason);
}
```

iOS adapter throws this instead of `UnsupportedError`. The translation helper adds a branch mapping it to a new domain `UnsupportedOperationException` (or to `BlueyPlatformException` with `code: 'unsupported'`). Smallest delta; preserves the typed-translation contract.

**Option B — gate at the domain layer via the capabilities matrix.** `BlueyConnection.requestMtu`, `connection.android?.bond`, etc. consult `_platform.capabilities` *before* calling the platform method. If the relevant flag is false, throw a typed `UnsupportedOperationException` synchronously without crossing the platform-interface seam. The platform call never fires for unsupported features. This is the proper Clean-Architecture fix — domain knows what it can do without asking the adapter — and is essentially [I065](I065-capabilities-matrix-decorative.md)'s "make capabilities load-bearing" extended to the unsupported-op surface.

**Option C — both.** B for callers that go through the documented surface; A as a backstop for direct platform-interface consumers (mostly tests) plus future capabilities the matrix doesn't yet model.

**Recommendation:** Option B if I065 is in scope; otherwise Option A as a tactical fix. Both fixes leave the I099 helper's defensive backstop in place — it's still load-bearing for genuinely-unknown errors.

## Verification plan

When picked up: run the iOS-client stress tests (Mixed Ops, MTU probe) and assert the surfaced exception is the typed unsupported-operation type, not `BlueyPlatformException(null)`. Equally: a unit test that calls `connection.requestMtu(Mtu(247))` against a fake iOS-flavored capabilities matrix and asserts the typed exception.
