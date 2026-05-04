# iOS error-mapping cleanup (I091 + I093)

Small bundle covering two iOS error-translation entries on the Tier 4 backlog.
Both target `bluey_ios`'s native-side `NSError`/`BlueyError` → `PigeonError`
translation. No public API changes, no breaking changes, no new domain
exception types.

## Background

Native iOS errors cross the Pigeon boundary as `PigeonError` instances with
one of a fixed set of `code` strings. The Dart-side translator in
`bluey_ios/lib/src/ios_connection_manager.dart` (`_translateGattPlatformError`)
maps those codes to typed platform-interface exceptions. Two paths regressed
or never quite landed:

- **I091** — `NSError+Pigeon.swift` keeps a hand-curated allowlist of
  `CBATTError` codes. Codes not in the allowlist drop to `bluey-unknown`,
  losing the numeric ATT status byte that callers want for distinguishing
  "rejected for security reasons" from "operation unsupported".
- **I093** — `BlueyError.notFound.toClientPigeonError()` maps to
  `gatt-disconnected`, surfacing a misleading `GattOperationDisconnectedException`
  when the actual cause is a lookup miss.

The I093 entry was last verified 2026-04-23, before the I088 handle rewrite
(`73656b4`). Re-investigation shows the entry's premise — characteristic /
descriptor UUID misses producing `gatt-disconnected` — was resolved by I088,
which routes handle misses to `BlueyError.handleInvalidated` →
`gatt-handle-invalidated` → `AttributeHandleInvalidatedException`. The three
remaining `BlueyError.notFound` sites in `CentralManagerImpl` are all
`peripherals[deviceId]` lookup misses, a different case.

## Goals

1. Bring iOS's `CBATTError` translation into symmetry with Android's
   `ConnectionManager.statusFailedError` (passes raw status bytes straight
   through).
2. Close I093 with a verification note rather than carrying a stale entry
   forward.
3. No new exception types, no Pigeon code additions, no breaking changes.

## Non-goals

- Introducing a typed `gatt-device-unknown` Pigeon code or
  `DeviceUnknownException` for the `peripherals[deviceId]` miss case. The
  three sites are rare in practice (caller passed a deviceId from a different
  plugin instance, or after dispose) and the existing
  `GattOperationDisconnectedException` is a defensible mapping —
  "you can't talk to this device right now" is the user-visible truth.
- Changing the server-side `BlueyError.notFound.toServerPigeonError()` path,
  which already correctly maps to `gatt-status-failed` with status 0x0A
  (ATTRIBUTE_NOT_FOUND).
- Touching the Dart-side `_translateGattPlatformError` in
  `ios_connection_manager.dart`. The existing `gatt-status-failed` branch
  already handles the new traffic (it preserves `details` as the status byte).

## I091 — drop the CBATTError allowlist

### Current state

`bluey_ios/ios/Classes/NSError+Pigeon.swift:26-43`:

```swift
private static func attStatusByte(for code: Int) -> Int? {
    switch code {
    case CBATTError.invalidHandle.rawValue:               return 0x01
    case CBATTError.readNotPermitted.rawValue:            return 0x02
    // ... 13 cases total ...
    case CBATTError.insufficientResources.rawValue:       return 0x11
    default:                                               return nil
    }
}
```

The thirteen `case` arms are each `code → return same code as Int`. Codes
outside the allowlist hit `default → nil`, which makes the caller in
`toPigeonError()` (line 13) skip the `gatt-status-failed` branch and fall
through to `bluey-unknown` at line 18.

Missing from the allowlist:
- 0x09 `CBATTError.prepareQueueFull`
- 0x0C `CBATTError.insufficientEncryptionKeySize`
- 0x0E `CBATTError.unlikelyError`
- 0x10 `CBATTError.unsupportedGroupType`

Plus any future Apple-added cases.

### After

```swift
func toPigeonError() -> PigeonError {
    if self.domain == CBATTErrorDomain {
        return PigeonError(code: "gatt-status-failed",
                           message: self.localizedDescription,
                           details: self.code)
    }
    return PigeonError(code: "bluey-unknown",
                       message: self.localizedDescription,
                       details: nil)
}
```

The `attStatusByte(for:)` helper is deleted. By definition every
`CBATTErrorDomain` code corresponds to an ATT status byte (that's what the
domain *means* per Bluetooth Core Spec v5.3 Vol 3 Part F §3.4.1.1) — Apple
isn't going to put non-ATT-status codes there. So we trust the domain check
and pass the numeric `code` straight through. This matches the Android
pattern at `ConnectionManager.kt:604` (`statusFailedError`).

### Test changes

Tests live in `bluey_ios/example/ios/RunnerTests/CBErrorPigeonTests.swift`.

| Existing test | Action |
|---|---|
| `testInvalidHandle_mapsToStatus0x01` … `testInsufficientResources_mapsToStatus0x11` (13 happy-path tests for the allowlisted codes) | Stay valid; numeric mapping unchanged. |
| `testUnknownDomain_mapsToBlueyUnknown` | Stays valid; non-`CBATTErrorDomain` errors still map to `bluey-unknown`. |
| `testUnknownCBATTErrorCode_mapsToBlueyUnknown` | **Flip**: rename to `testUnknownCBATTErrorCode_preservesNumericStatus`; assert it now maps to `gatt-status-failed` with `details = 0xFF` (the chosen unknown code). |

| New test | Asserts |
|---|---|
| `testPrepareQueueFull_mapsToStatus0x09` | `details == 0x09` |
| `testInsufficientEncryptionKeySize_mapsToStatus0x0C` | `details == 0x0C` |
| `testUnlikelyError_mapsToStatus0x0E` | `details == 0x0E` |
| `testUnsupportedGroupType_mapsToStatus0x10` | `details == 0x10` |

The `0xFE` "future-Apple-code" forward-compat case is already implicitly
covered by the renamed `testUnknownCBATTErrorCode_preservesNumericStatus`
(any `CBATTErrorDomain` code now passes through), so no separate test for
that.

### Dart-side ripple

`_translateGattPlatformError` in `ios_connection_manager.dart:31-64`
already has a `gatt-status-failed` branch that extracts `details` as the
status byte and throws `GattOperationStatusFailedException(operation, status)`.
No changes needed.

## I093 — close as obsolete-by-I088

### Original premise

Per the I093 entry: "When the iOS side can't find a characteristic or
descriptor in its cache (e.g., user passed a UUID that isn't in the current
service tree), `CentralManagerImpl` emits
`BlueyError.notFound.toClientPigeonError()` … resulting in
`GattOperationDisconnectedException`."

### Post-I088 state (verified 2026-05-04)

`CentralManagerImpl.swift:253-371` (every characteristic/descriptor op):

```swift
guard let characteristic = handleStore.characteristicByHandle[deviceId]?[Int(characteristicHandle)] else {
    completion(.failure(BlueyError.handleInvalidated.toClientPigeonError()))
    return
}
```

Handle misses (the I088-rewritten "characteristic / descriptor not in cache"
case) go to `gatt-handle-invalidated`, translated Dart-side to
`AttributeHandleInvalidatedException`. The original premise of I093 is
already fixed.

### Remaining `BlueyError.notFound` sites

Three sites in `CentralManagerImpl`, all of the same shape — `peripherals[deviceId]`
miss in `connect` (line 153), `disconnect` (line 194), and `discoverServices`
(line 226). Triggered when the user passes a deviceId never seen by this iOS
plugin instance.

Mapping to `gatt-disconnected` →`GattOperationDisconnectedException` is
defensible: "you can't talk to this device right now" is the user-visible
truth, even if the precise cause is "you never connected in the first place"
rather than "the connection just dropped." The case is rare in practice
(caller passed a deviceId from a different plugin instance, or after a
dispose / recreate cycle). No change.

### Action

- Mark I093 `status: fixed`, `fixed_in: <commit>`, `last_verified: 2026-05-04`.
- Append a closing note to the I093 entry explaining the post-I088 picture
  and noting that the remaining peripheral-miss sites were reviewed and left
  as-is intentionally.

## Implementation outline

1. **TDD on the iOS test target.** Add the four new
   `testXxx_mapsToStatus0xNN` tests; flip the unknown-code test. Run; expect
   failures.
2. **Edit `NSError+Pigeon.swift`.** Inline the helper into `toPigeonError`,
   delete `attStatusByte(for:)`. Run iOS tests; expect green.
3. **Run `flutter test` in `bluey_ios/`.** Sanity check the Dart side is
   unchanged.
4. **Run the example app's connect-to-real-hardware path** if a test rig is
   available — not strictly required (no contract changed for callers using
   already-mapped codes), but cheap insurance.
5. **Update backlog.** Mark I091 fixed; mark I093 fixed with the closing
   note. Update `docs/backlog/README.md`'s fixed table.
6. **Single commit.** Both entries in one commit titled e.g.
   `fix(ios): preserve CBATTError status byte through Pigeon (closes I091, I093)`.

## Risk

- **Forward-compat false positive.** If Apple ever adds a `CBATTErrorDomain`
  code outside the 0x00–0xFF status-byte range, our pass-through would emit
  a value that doesn't fit Bluetooth's spec. Probability is essentially zero
  — `CBATTErrorDomain` is defined as the ATT status byte domain — but the
  failure mode is "Dart receives an out-of-range int." Acceptable.
- **Caller code that switched on `bluey-unknown` for those four codes.** No
  such caller exists in this repo. External users would have to be using
  `GattOperationUnknownPlatformException` as a catch for these — the typed
  `GattOperationStatusFailedException` now reaching them is strictly more
  informative.

## Files touched

- `bluey_ios/ios/Classes/NSError+Pigeon.swift` (~15-line replacement).
- `bluey_ios/example/ios/RunnerTests/CBErrorPigeonTests.swift` (~30 lines: 1
  rename + 4 new tests).
- `docs/backlog/I091-ios-unmapped-cbatt-error-to-unknown.md` (mark fixed).
- `docs/backlog/I093-ios-notfound-maps-to-wrong-error.md` (mark fixed with
  closing note).
- `docs/backlog/README.md` (move entries from open → fixed table).
