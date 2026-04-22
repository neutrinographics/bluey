# iOS Error Consistency + Stress-Test MTU Prologue — Design

**Date:** 2026-04-23
**Status:** Approved for implementation planning
**Related:** PR #9 (activity-aware liveness) surfaced the symptoms; PR #7 (Phase 2a GATT queue) and PR #5 (lifecycle detection) established the exception hierarchy this design extends.

## Motivation

Two symptoms surfaced during stress-test runs against an iOS server from an Android client:

1. **Burst writes failed on first run** with a 20-byte payload. The wire payload is 21 bytes (1 opcode + 20 data), exceeding iOS's default ATT MTU payload (20 bytes = MTU 23 − 3 header). Once MTU auto-negotiates up later in the connection, the same burst succeeds. Net effect: a freshly-connected stress test looks broken until MTU-up happens.
2. **Failure display is opaque.** The UI showed `PlatformException × 28` because the errors that fired (raw `PlatformException` with iOS's `BlueyError` codes) slipped through `_runGattOp`'s translation layer and the stress-test UI used `runtimeType.toString()`. There was no way to diagnose which error actually occurred.

Investigation revealed that symptom 2 is a symptom of a deeper asymmetry: the library's public exception contract (`sealed class BlueyException`) is fully honoured on Android but leaks raw `PlatformException` on iOS for every `BlueyError` case (`notFound`, `notConnected`, `unsupported`, `unknown`, `timeout`) and for several `CBATTErrorDomain` NSError codes. A library user writing `try { await char.write(...) } on GattOperationFailedException catch (e) { ... }` gets the typed exception on Android but a raw `PlatformException` on iOS for the same conceptual failure.

## Goals

1. **Consistent cross-platform API surface:** user code that catches `BlueyException` subtypes works identically on Android and iOS. Raw `PlatformException` cannot reach user code from any GATT op.
2. **Actionable failure diagnostics:** when an op fails, the user sees a typed exception + (where applicable) a BLE ATT status code that identifies the failure class (MTU overflow, write not permitted, not supported, etc.).
3. **Stress tests succeed on first run** for payloads within the standard negotiable MTU (up to 247 bytes).
4. **No false-disconnect regressions:** the per-context semantic difference between client-side `BlueyError.notFound` ("peer gone") and server-side `BlueyError.notFound` ("programming error") is preserved; server-side precondition errors do not trip client-side lifecycle disconnect logic.

## Non-Goals

- Cancellation of in-flight GATT ops (discussed earlier as a separate UX concern; not in this spec).
- New `BlueyException` subtypes beyond extending existing ones. YAGNI: callers who need fine-grained branching can switch on `BlueyPlatformException.code`.
- Reworking Android error translation. Android is already consistent; it surfaces GATT errors through the three existing `gatt-*` Pigeon codes and the corresponding typed exceptions.
- UI visual redesign of the stress-test results panel beyond including the status code / platform code in the existing failure display.

## Architecture

Four layers of change, each with a clear responsibility:

1. **Swift native (`bluey_ios/ios/Classes/`)** — translate every `BlueyError` case and every `CBATTErrorDomain` `NSError` into a `PigeonError` with one of the well-known `gatt-*` codes Dart already knows how to translate. After this step `BlueyError` is strictly Swift-internal; it never crosses the Pigeon FFI boundary.
2. **Dart platform adapter (`bluey_ios/lib/src/ios_connection_manager.dart`)** — add a case for one new Pigeon code (`bluey-unknown`), routed to `BlueyPlatformException`. Existing `gatt-*` translation is unchanged.
3. **Core library (`bluey/`)** — extend `BlueyPlatformException` with a `code` field; add a defence-in-depth catch-all in `_runGattOp` that wraps any residual `PlatformException` as `BlueyPlatformException(code, cause)`. Remove the now-dead legacy `PlatformException(code:'notFound'|'notConnected')` branch from `LifecycleClient._isDeadPeerSignal`.
4. **Example app (`bluey/example/`)** — every stress test prologue calls `connection.requestMtu(247)` before the existing `ResetCommand` write. `ResultsPanel` displays the platform code for `BlueyPlatformException` failures.

Layering is strict: the lower the layer, the more authoritative its error taxonomy. Layer 1 is the source of truth for "what did CoreBluetooth / my Swift precondition say?"; layers 2–3 translate and wrap; layer 4 consumes the typed surface.

## Error Mapping

The full iOS-side translation table. Each row describes a native failure → wire code (Pigeon) → typed Dart exception. Status bytes follow the BLE ATT error code spec (Bluetooth Core Spec v5.3 Vol 3 Part F §3.4.1.1) so identical conceptual errors emit identical numeric codes on Android and iOS.

### `BlueyError` → `PigeonError` — context-aware

| Source enum case                  | Client-side (`CentralManagerImpl.swift`)          | Server-side (`PeripheralManagerImpl.swift`)          |
|-----------------------------------|---------------------------------------------------|------------------------------------------------------|
| `BlueyError.notFound`             | `gatt-disconnected`                               | `gatt-status-failed` w/ status `0x0A`                |
| `BlueyError.notConnected`         | `gatt-disconnected`                               | `gatt-status-failed` w/ status `0x0A` (never fires server-side today; kept for safety) |
| `BlueyError.unsupported`          | `gatt-status-failed` w/ status `0x06`             | `gatt-status-failed` w/ status `0x06`                |
| `BlueyError.timeout` (non-GATT)   | `gatt-timeout`                                    | n/a                                                  |
| `BlueyError.unknown`              | `bluey-unknown` (new)                             | `bluey-unknown`                                      |

**Rationale for context-aware mapping:** iOS's CoreBluetooth synchronously invalidates cached characteristic handles when the peer vanishes — before `didDisconnect` fires — so `BlueyError.notFound` on the client side legitimately signals a dead peer. On the server side, the same enum case means "I tried to respond for a char I never registered," which is a programming error, not a disconnect. Mapping both to `gatt-disconnected` would surface server programming errors as `DisconnectedException`, confusing callers and (if any code path ever fed such errors into a heartbeat write, however unlikely) potentially tripping `LifecycleClient`'s dead-peer counter.

Concretely, `BlueyError` gains two translation helpers:
```swift
extension BlueyError {
    func toClientPigeonError() -> PigeonError { /* left column */ }
    func toServerPigeonError() -> PigeonError { /* right column */ }
}
```
Each call site uses the one matching its file role. File-level separation means there is never ambiguity at any call site.

### `NSError` (CoreBluetooth) → `PigeonError`

All `NSError` instances with domain `CBATTErrorDomain` translate to `gatt-status-failed` with the corresponding BLE ATT status byte. Unknown domains / codes fall through to `bluey-unknown`.

| `CBATTError` code                     | ATT status byte | Typed Dart exception                  |
|---------------------------------------|-----------------|---------------------------------------|
| `.invalidHandle`                      | `0x01`          | `GattOperationFailedException(0x01)`  |
| `.readNotPermitted`                   | `0x02`          | `GattOperationFailedException(0x02)`  |
| `.writeNotPermitted`                  | `0x03`          | `GattOperationFailedException(0x03)`  |
| `.invalidPdu`                         | `0x04`          | `GattOperationFailedException(0x04)`  |
| `.insufficientAuthentication`         | `0x05`          | `GattOperationFailedException(0x05)`  |
| `.requestNotSupported`                | `0x06`          | `GattOperationFailedException(0x06)`  |
| `.invalidOffset`                      | `0x07`          | `GattOperationFailedException(0x07)`  |
| `.insufficientAuthorization`          | `0x08`          | `GattOperationFailedException(0x08)`  |
| `.attributeNotFound`                  | `0x0A`          | `GattOperationFailedException(0x0A)`  |
| `.attributeNotLong`                   | `0x0B`          | `GattOperationFailedException(0x0B)`  |
| `.invalidAttributeValueLength`        | `0x0D`          | `GattOperationFailedException(0x0D)`  |
| `.insufficientEncryption`             | `0x0F`          | `GattOperationFailedException(0x0F)`  |
| `.insufficientResources`              | `0x11`          | `GattOperationFailedException(0x11)`  |
| `NSError` with any other domain/code  | `bluey-unknown` | `BlueyPlatformException(code:'unknown')` |

Implemented as an `NSError` extension (`NSError+Pigeon.swift`, new file) with a `toPigeonError() -> PigeonError` method.

### Dart-side additions

| Pigeon code (new) | Dart translation                                        |
|-------------------|----------------------------------------------------------|
| `bluey-unknown`   | `BlueyPlatformException(message, code: 'unknown', cause: e)` |

Added as a new case in `ios_connection_manager.dart`. (Android emits no equivalent code today.)

### Core library backstop

| Residual input in `_runGattOp` | Output |
|-------------------------------|--------|
| Any `PlatformException` not translated upstream | `BlueyPlatformException(e.message, code: e.code, cause: e)` |

Runs in `bluey/lib/src/connection/bluey_connection.dart`. Defence-in-depth: if a future platform change introduces a new error code that neither the adapter nor the Swift mapper handle, the user still never sees a raw `PlatformException`.

## Data Flow

End-to-end for the stress-test MTU overflow case, before and after.

### Before

```
write(payload=21B)
  → Swift: peripheral.writeValue(...) withResponse
  → CoreBluetooth: peer returns ATT_INVALID_ATTRIBUTE_VALUE_LENGTH
  → Swift: didWriteValueFor:error: fires with NSError(CBATTErrorDomain, 0x0D)
  → Swift: completion(.failure(nsError))   [no translation]
  → Pigeon: pass-through → PlatformException(code: "<apple code>")
  → Dart: ios_connection_manager sees unrecognised code → rethrows
  → _runGattOp: doesn't catch PlatformException → rethrows
  → BlueyConnection.write: rethrows
  → StressTestRunner: catches Object → records typeName='PlatformException'
  → UI: shows "PlatformException × 28"      [opaque]
```

### After

```
write(payload=21B) — preceded by connection.requestMtu(247) in stress-test prologue
  (common case: peer accepts MTU, payload fits, no error fires)

  [if MTU negotiation fails or peer caps lower than 24]
  → Swift: peripheral.writeValue(...) withResponse
  → CoreBluetooth: peer returns ATT_INVALID_ATTRIBUTE_VALUE_LENGTH
  → Swift: didWriteValueFor:error: fires with NSError(CBATTErrorDomain, 0x0D)
  → Swift: nsError.toPigeonError() → PigeonError("gatt-status-failed", details: 0x0D)
  → Pigeon: PlatformException(code: "gatt-status-failed", details: 0x0D)
  → Dart: ios_connection_manager → GattOperationStatusFailedException(0x0D)
  → _runGattOp: catches typed → rethrows GattOperationFailedException("write", 0x0D)
  → BlueyConnection.write: rethrows
  → StressTestRunner: records typeName='GattOperationFailedException', status=0x0D
  → UI: shows "GattOperationFailedException × 28" + "Status codes: 0x0D × 28"
```

Users can now see exactly which BLE ATT error class caused each failure. The same translation applies to every other op type (read, discover, requestMtu, setNotification, etc.) — no per-op special case.

## Components

### Swift — `bluey_ios/ios/Classes/`

- **`BlueyError.swift`** (modify) — remove the unused `illegalArgument` case; keep the rest. Add an extension with `toClientPigeonError()` and `toServerPigeonError()` methods implementing the table above.
- **`NSError+Pigeon.swift`** (new) — extension on `NSError` with `toPigeonError() -> PigeonError` implementing the `CBATTErrorDomain` mapping.
- **`CentralManagerImpl.swift`** (modify) — replace every `completion(.failure(BlueyError.X))` with `completion(.failure(BlueyError.X.toClientPigeonError()))`. Replace every `completion(.failure(error))` where `error` is an `NSError` from CoreBluetooth with `completion(.failure(error.toPigeonError()))`.
- **`PeripheralManagerImpl.swift`** (modify) — same treatment using `toServerPigeonError()`.

Approximate change: ~30 edit sites across the two Impl files; all mechanical.

### Dart platform adapter — `bluey_ios/lib/src/ios_connection_manager.dart`

- Add a new case to the existing translation switch: `if (e.code == 'bluey-unknown') throw BlueyPlatformException(e.message ?? 'unknown', code: 'unknown', cause: e);`

### Core library — `bluey/`

- **`lib/src/shared/exceptions.dart`** — extend `BlueyPlatformException` with `final String? code` + update constructor to accept it as a named parameter. Backwards compatible.
- **`lib/src/connection/bluey_connection.dart`** — in `_runGattOp`, add a final `on PlatformException catch (e)` that rethrows `BlueyPlatformException(e.message ?? '<no message>', code: e.code, cause: e)`.
- **`lib/src/connection/lifecycle_client.dart`** — remove the legacy `PlatformException(code:'notFound'|'notConnected')` branch from `_isDeadPeerSignal`. The existing `GattOperationDisconnectedException` branch now catches those cases after Swift translation.

### Example app — `bluey/example/`

- **`features/stress_tests/infrastructure/stress_test_runner.dart`** — extract the existing reset prologue into a `_prologue(connection)` helper that first calls `connection.requestMtu(247)` (swallowing failure — not all peers support higher MTU and that's fine) and then writes `ResetCommand`. Every `run*` method uses the helper. ~8 LOC change per method × 7 methods.
- **`features/stress_tests/infrastructure/stress_test_runner.dart`** (same file as above) — in every `catch` block where an op failure is recorded, build the typename as `'${e.runtimeType}(${e.code})'` when the exception is a `BlueyPlatformException` (so the existing `failuresByType` count-aggregation displays e.g. `BlueyPlatformException(unknown) × 3`). No change needed in `StressTestResult` or `ResultsPanel`.

## Testing Strategy

### Swift

- **`BlueyErrorPigeonTests.swift`** (new) — table-driven test: each `BlueyError` case × each context (`client`, `server`) → expected `PigeonError` code and details.
- **`CBErrorPigeonTests.swift`** (new) — every `CBATTError` code → expected `gatt-status-failed` details with the right status byte. Includes a "unknown domain" negative case mapping to `bluey-unknown`.

### Dart — platform adapter

- **`bluey_ios/test/ios_connection_manager_test.dart`** (extend) — add a test for the new `bluey-unknown` code translating to `BlueyPlatformException(code:'unknown')`.

### Dart — core library

- **`bluey/test/shared/exceptions_test.dart`** (extend) — one test that `BlueyPlatformException(message, code:'x', cause:y)` exposes all three fields.
- **`bluey/test/connection/bluey_connection_test.dart`** (extend) — one test that a raw `PlatformException(code:'fictitious')` at the `_runGattOp` boundary becomes `BlueyPlatformException(code:'fictitious')` via the defensive catch-all.
- **`bluey/test/connection/lifecycle_client_test.dart`** (edit) — remove the two existing tests that feed `PlatformException(code:'notFound')` and `...('notConnected')` to verify dead-peer detection. Replace with asserts that `GattOperationDisconnectedException` triggers dead-peer (already covered by existing `gatt-disconnected` tests, so net effect is test removal).

### Regression guard for the false-disconnect risk

- **`bluey_ios/ios/Tests/PeripheralManagerErrorTests.swift`** (new) — a test verifying that a server-side `notFound` (via simulated peer request for an unregistered characteristic) produces `PigeonError("gatt-status-failed", details: 0x0A)`, explicitly **not** `gatt-disconnected`. Locks the client/server mapping distinction down so a future refactor can't conflate them.

### Manual / on-device verification

- **Smoke test:** connect iOS server from Android client, immediately run burst-write 50 ops × 20 bytes. Expected: all 50 succeed on first run.
- **Negative (forced failure) test:** set burst payload to 500 bytes, run. MTU probably caps below 503 needed; ATT error fires; UI shows `GattOperationFailedException × N` with `Status codes: 0x0D × N`. Diagnoseable at a glance.
- **MTU-refusing peer:** if peer doesn't honour `requestMtu(247)`, the prologue still proceeds (failure is ignored). Burst at default 20 bytes still fails cleanly with 0x0D. Acceptable — the goal was diagnosability, not guaranteed success against every peer.

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| False-positive disconnect from server-side `notFound` leaking as `DisconnectedException` | Context-aware Swift mapping. Regression test in `PeripheralManagerErrorTests`. |
| Some `CBATTError` case missed in the mapping | Unknown codes fall through to `bluey-unknown` → `BlueyPlatformException`, preserving the code in the message. User still sees diagnostic info. |
| `requestMtu(247)` fails on some peer, breaking the stress-test prologue | Swallow failure — MTU is best-effort. Prologue continues with the `ResetCommand` write. |
| Existing `_isDeadPeerSignal` test coverage gaps after removing legacy branches | The `gatt-disconnected` path is already comprehensively tested. Removing the legacy branch is covered by that path. |
| User code that happens to catch `on PlatformException` specifically stops matching | This is a breaking change in spirit but not in signature (no public method changed). Documented in the changelog; the intent was always to funnel everything through `BlueyException`. |

## Out of Scope (Future Work)

- In-flight GATT op cancellation (user-triggered abort of burst-write mid-test).
- Introducing new `BlueyException` subtypes for specific `BlueyPlatformException` codes once callers start pattern-matching on them.
- Android-side audit for parallel asymmetries (none observed today, but worth a follow-up check).

## Approval

Section 1 (architecture/scope), Section 2 (components), Section 3 (mapping table), Section 4 (data flow), Section 5 (testing), and Section 6 (false-disconnect safeguards) each approved by Joel on 2026-04-23.
