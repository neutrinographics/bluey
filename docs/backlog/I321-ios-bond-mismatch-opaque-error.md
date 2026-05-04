---
id: I321
title: iOS `connect` surfaces `CBError.peerRemovedPairingInformation` (code 14) as opaque `BlueyPlatformException`; no actionable UX path for stale-bond recovery
category: bug
severity: medium
platform: ios
status: open
last_verified: 2026-05-04
related: [I313]
---

## Symptom

When an iOS central tries to connect to a peripheral with which iOS has
a stored bond record that the peripheral no longer recognises (typical
after the peripheral-side app was reinstalled, the device was factory
reset, the user toggled "Forget device" on Android, or Android rotated
its IRK), the connect fails with:

```
Error Domain=CBErrorDomain Code=14 "Peer removed pairing information"
```

The bluey iOS plugin's `didFailToConnect` translates this to a generic
`PlatformException(code: "connect-failed", …)` which arrives at the
domain layer as a generic `BlueyPlatformException`. Application code has
no programmatic way to distinguish "stale bond on iOS — tell the user to
forget the device" from any other connection failure.

The user-facing recovery is non-obvious:

- iOS Settings → Bluetooth → tap (i) on the peripheral → "Forget This
  Device". (The peripheral may not appear in this list at all if it's a
  BLE-only device; restarting the iOS device clears the in-memory
  pairing cache as a hammer.)
- Or, on the peripheral side, "Unpair" the iOS device.

End-user-visible behaviour is "the connect just fails, with no clue
what's wrong." This pattern reproduces reliably during normal app
development cycles (Android reinstall → next iOS connect attempt fails)
and was discovered while validating I313's cross-platform discovery fix.

## Location

- `bluey_ios/ios/Classes/CentralManagerImpl.swift` — the
  `didFailToConnect` handler that emits the current opaque
  `connect-failed` Pigeon code.
- `bluey_ios/ios/Classes/Errors.swift` — wherever the `CBError` →
  Pigeon-code mapping lives (verify path; may be inlined in the
  manager).
- `bluey_ios/lib/src/ios_connection_manager.dart` — the Dart-side
  `_translateGattPlatformError` analogue for connect-time errors.
- `bluey_platform_interface/lib/src/exceptions.dart` — destination for
  a new typed `PlatformPeerPairingMismatchException`.
- `bluey/lib/src/shared/error_translation.dart` — domain-layer
  translation site.
- `bluey/lib/src/shared/exceptions.dart` — domain-layer typed exception
  (e.g. `BondMismatchException` or a new `ConnectionFailureReason.bondMismatch`
  on the existing `ConnectionException`).

## Root cause

Two distinct issues compound:

1. **Error surface is opaque.** The bluey iOS plugin pre-translates
   every CBError to a generic `connect-failed` Pigeon code, losing the
   underlying OS error code. The domain layer maps that to
   `BlueyPlatformException` — which is the catch-all the project
   explicitly uses for "we don't have a typed translation for this." The
   I313 work established the pattern for surfacing typed errors through
   each layer (`PlatformAdvertiseDataTooLargeException` →
   `AdvertisingException(dataTooBig)`); the same pattern should apply
   here.

2. **No programmatic bond-state recovery on iOS.** CoreBluetooth does
   not expose iOS's bond cache. There is no public API to enumerate
   stored bonds, no API to delete a specific bond, and no way to force
   "connect without using the cached pairing." The user is forced into
   the Settings UI (or a device restart) to recover. This is an Apple
   limitation; bluey can't fully fix it, but can document the recovery
   path and let apps surface a useful error message.

## Notes

**Two-part fix:**

### Part A — surface the error properly (mirrors I313's pattern)

1. Add `PlatformPeerPairingMismatchException` to
   `bluey_platform_interface/lib/src/exceptions.dart`. Same shape as
   `PlatformAdvertiseDataTooLargeException` (immutable, value equality,
   `implements Exception`).

2. Add a new error-code constant `bluey-peer-pairing-mismatch` to the
   bluey iOS plugin's error translator. Map `CBError.code == 14` (or the
   Swift constant `.peerRemovedPairingInformation`) to that code.

3. Translate the new code in `bluey_ios/lib/src/ios_connection_manager.dart`
   (or wherever the Dart-side `connect-*` codes are translated) to
   `PlatformPeerPairingMismatchException`.

4. In `bluey/lib/src/shared/error_translation.dart`, translate the
   platform-interface exception to a domain-layer typed exception. Two
   reasonable shapes:
   - **(a)** A new top-level `BondMismatchException extends BlueyException`
     with a static doc string suggesting the recovery steps.
   - **(b)** Add `ConnectionFailureReason.bondMismatch` to the existing
     `ConnectionFailureReason` enum and surface via the existing
     `ConnectionException`. Closer to existing patterns; keeps the
     exception hierarchy flat.

   Option (b) is preferred unless app code needs to differentiate
   bond-mismatch from other connect failures via runtime type rather
   than enum discriminator. Discuss in the PR.

5. Tests: domain-layer translation test in
   `bluey/test/shared/error_translation_test.dart`; Dart-side iOS
   connection manager test in `bluey_ios/test/ios_connection_manager_test.dart`
   verifying the Pigeon code is translated; bluey_platform_interface
   exception equality + isA test.

### Part B — UX guidance + Android-side equivalent

1. Document the recovery path in `bluey/lib/src/shared/exceptions.dart`'s
   dartdoc on the new exception (Settings → Bluetooth → Forget; or
   restart iOS device; or unpair from the peripheral side).

2. Investigate Android-side equivalents. When iOS unpairs from Android,
   does Android surface `GATT_INSUF_AUTHENTICATION` (status 5) or
   `GATT_INSUFFICIENT_ENCRYPTION` on subsequent reads? Audit and add
   typed translation for those if not already in place.

3. Audit whether bluey itself triggers bonding anywhere. The lifecycle
   control service uses plain `read`/`write` permissions (verified in
   `bluey/lib/src/lifecycle.dart` — no `encryptedRead` / `encryptedWrite`
   / `authenticated*`), so bluey should not initiate SMP. But user
   characteristics added via `Server.addService` may. Document that
   "characteristics with encrypted permissions trigger bonding" so
   developers can decide whether they actually need encryption.

4. **Consider a `Bluey.clearPairing(deviceId)` API** that's a no-op on
   iOS (CoreBluetooth doesn't expose this) and dispatches to
   `BluetoothDevice.removeBond()` on Android (via reflection — the
   public API doesn't expose `removeBond` but the hidden method works
   on most AOSP builds). This would let app code surface "Tap to clear
   pairing and retry" buttons that work on at least one platform. Mark
   the iOS implementation as throwing a documented "iOS does not expose
   this API; instruct user to forget the device in Settings" with the
   specific text the app should display.

   This is a real ask: the user reproducibly hit this during dev cycles
   (Android app reinstall regenerates IRK; iOS retains the old bond) and
   "tell the user to navigate to Settings → Bluetooth" is the kind of
   support burden that consumes engineering time.

**Severity rationale.** Medium because: (a) reliable workaround exists
(forget device); (b) reproducible during normal dev cycles; (c) opaque
error surface costs every consumer development time the first time they
hit it; (d) no end-user data loss, but the app appears broken from the
user's perspective.

**Out of scope.** Apple-side limitation that bond cache isn't
inspectable from CoreBluetooth — file as separate "external dependency
limitation" if you want to track the upstream issue, but bluey can't fix
it.

## Reproduction

1. iOS device runs the bluey example scanner (or any consumer app).
2. Android device runs the bluey gossip example with `peerDiscoverable: true`.
3. iOS connects to Android successfully (bond may or may not be created
   depending on whether the gossip app uses encrypted characteristics).
4. **Reinstall the gossip app on Android** (or factory-reset, or
   manually clear the Bluetooth bond from Android Settings). This
   regenerates Android's IRK / clears its bond record.
5. iOS scans, sees the Android device, attempts to connect.
6. iOS's stored bond doesn't match Android's (now-fresh) state — connect
   fails within ~350 ms with `CBError.peerRemovedPairingInformation`.
7. Confirmed log signature:

```
[INFO ] bluey: connect entered
[INFO ] bluey.connection: connect started
[INFO ] bluey.ios.central: connect
[WARN ] bluey.ios.central: didFailToConnect {error: CBErrorDomain Code=14
        "Peer removed pairing information"} err=connect-failed
[ERROR] bluey.connection: connect failed {exception: BlueyPlatformException}
```

The `BlueyPlatformException` at the bottom is the bug surface. After
the fix, this should be a typed `BondMismatchException` (or
`ConnectionException(reason: bondMismatch)`) that app code can pattern-
match on.

## External references

- Apple, [`CBError`](https://developer.apple.com/documentation/corebluetooth/cberror)
  — error code 14 is `peerRemovedPairingInformation`.
- Apple, ["Performing Common Central Role Tasks"](https://developer.apple.com/documentation/corebluetooth/transferring-data-between-bluetooth-low-energy-devices)
  — CoreBluetooth has no API for inspecting or clearing the bond cache.
- BLE Core Specification 5.4 Vol 3 Part H §3 — Security Manager Protocol
  pairing failure modes.
