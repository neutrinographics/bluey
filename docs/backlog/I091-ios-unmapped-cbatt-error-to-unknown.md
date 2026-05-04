---
id: I091
title: "iOS unmapped `CBATTError` codes silently become `bluey-unknown`"
category: bug
severity: medium
platform: ios
status: fixed
last_verified: 2026-05-04
fixed_in: 8875f4c
---

> **Note (2026-04-25):** I091 was originally suspected as the cause of
> [I087](I087-failure-injection-no-auto-reconnect.md)'s failure-injection
> reconnect bug. Diagnostic instrumentation showed the actual cause was
> in `CentralManagerImpl.didDisconnectPeripheral`, not `NSError+Pigeon`.
> See [I096](I096-ios-nil-disconnect-error-to-unknown.md). I091 remains
> open for the original `CBATTError` allowlist gap, which has no
> production evidence of firing — low priority.

## Symptom

iOS's `NSError.toPigeonError()` maps known `CBATTError` cases (insufficientAuthentication, insufficientEncryption, etc.) to `gatt-status-failed` with the status byte preserved. Unmapped codes — `missingEncryptionKey` (0x0C), `unsupportedGroupType` (0x0E), future additions — fall through to `bluey-unknown` with the status byte lost.

On the Dart side, these become `GattOperationUnknownPlatformException` with no status. Callers that want to distinguish "write rejected for security reasons" from "operation unsupported" can't.

## Location

`bluey_ios/ios/Classes/NSError+Pigeon.swift:26-42` — the `attStatusByte()` extension returns `nil` for unmapped codes.

## Root cause

Explicit allowlist of handled error codes. Everything else is dropped.

## Notes

Fix: extend the allowlist to cover every `CBATTError` case (the enum is finite; Swift-native `switch .allCases` approach). Better: preserve the numeric status code even for unmapped cases — a status-failed with an unknown code is still more useful than an unknown-platform error with no code.

Android-side parallel: `Errors.kt` maps known `BluetoothGatt.GATT_*` constants and has a fallback. Verify symmetry — this entry's Android twin may already be handled correctly, or may have the same allowlist gap.

## Resolution

`NSError+Pigeon.swift` no longer maintains an explicit `CBATTError`
allowlist. Any `NSError` whose `domain == CBATTErrorDomain` is
translated to `gatt-status-failed` with `details = self.code`, so
the four previously-dropped codes (0x09, 0x0C, 0x0E, 0x10) and any
future Apple-added codes surface as typed
`GattOperationStatusFailedException` carrying the numeric ATT status.
This brings iOS into symmetry with Android's
`ConnectionManager.statusFailedError`.

Test coverage in `CBErrorPigeonTests.swift`: the previously-passing
`testUnknownCBATTErrorCode_mapsToBlueyUnknown` is flipped to
`testUnknownCBATTErrorCode_preservesNumericStatus`, and four named
tests cover the previously-dropped codes by name.
