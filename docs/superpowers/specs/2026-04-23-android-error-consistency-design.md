# Android Error Consistency — Design

**Date:** 2026-04-23
**Status:** Approved for implementation planning
**Related:** PR #10 (iOS error consistency + stress-test MTU prologue) — this spec mirrors that work on the Android side.

## Motivation

PR #10 closed the iOS-specific escape hatch where raw `PlatformException` reached user code for every `BlueyError` case and several `CBATTErrorDomain` `NSError` codes. After that merge the `BlueyException` sealed hierarchy became the full public error contract on iOS.

A stress test run immediately after the PR #10 merge revealed a symmetric gap on Android: the Kotlin plugin throws `IllegalStateException` ("Device not connected", "Characteristic not found", "No queue for connection", etc.) and `SecurityException` (permission denials) that surface to Dart as raw `PlatformException(code:'IllegalStateException'|'SecurityException')`. The core library's defensive `_runGattOp` catch-all in `bluey/lib/src/connection/bluey_connection.dart` currently wraps them as `BlueyPlatformException(code:'IllegalStateException', ...)` so nothing reaches user code as raw `PlatformException`, but the catch-all is a backstop — not a translation. The resulting exceptions are diagnosable but not pattern-matchable (user code catches `on BlueyPlatformException` with a stringly-typed `code` field, rather than `on DisconnectedException` / `on PermissionDeniedException` / etc.).

Closing the Android escape hatch at the source makes Android symmetric with iOS: both platforms funnel every native error through exactly five known Pigeon codes (`gatt-timeout`, `gatt-disconnected`, `gatt-status-failed`, `bluey-unknown`, `bluey-permission-denied`), the Dart adapter translates each to a platform-interface exception, and `_runGattOp` translates those to the public `BlueyException` sealed hierarchy. User code that catches `on DisconnectedException` / `on GattOperationFailedException` / `on PermissionDeniedException` works identically on both platforms.

## Goals

1. **Cross-platform API symmetry:** every native GATT-op error on Android surfaces as a typed `BlueyException` subclass, identical to iOS post-PR-#10. No user code path sees raw `PlatformException`.
2. **Compiler-enforced throw discipline:** Kotlin throws use a sealed `BlueyAndroidError` hierarchy (mirror of iOS's `BlueyError`) rather than `IllegalStateException` with message strings, so the mapping is exhaustively pattern-matched by the compiler.
3. **Runtime permission support:** Android-specific `SecurityException` path surfaces as the existing `PermissionDeniedException`, enabling idiomatic "catch → prompt user → retry" flows that weren't previously pattern-matchable.
4. **Defence in depth:** unexpected `Throwable` instances (e.g. a future `NullPointerException`) fall through to `bluey-unknown` so raw `PlatformException` can never reach user code regardless of future regressions.

## Non-Goals

- Reworking iOS (done in PR #10).
- Example app changes. Failure display already handles typed exceptions; no UI work needed.
- New public `BlueyException` subtypes beyond the existing hierarchy.
- The adjacent iOS-client → Android-server stress-test hang (separate debugging session).
- Converting iOS to emit `bluey-permission-denied` when `CBManagerState.unauthorized` (documented asymmetry; users use `bluey.state` stream on iOS).
- Auditing Bluetooth-adapter-state handling across ops (currently routes to `bluey-unknown`; proactive Dart-side state check is the primary user-facing pattern).

## Architecture

Three layers of change, layer-correct (no circular deps, mirror of PR #10's layering):

1. **Kotlin native (`bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/`)** — New `BlueyAndroidError` sealed hierarchy replaces `IllegalStateException` / `SecurityException` throws. Two context-aware extension helpers translate `BlueyAndroidError` (plus any residual `Throwable`) into `FlutterError` with a known Pigeon code. `BlueyPlugin.kt` wraps each Pigeon-facing method with `try { ... } catch (e: Throwable) { throw e.toClientFlutterError() }` (client-role methods) or `... .toServerFlutterError()` (server-role methods).
2. **Dart platform adapter (`bluey_android/lib/src/android_connection_manager.dart`)** — Add one new case: `bluey-permission-denied` → throws the new `PlatformPermissionDeniedException` (added to `bluey_platform_interface`). Existing `gatt-timeout` / `gatt-disconnected` / `gatt-status-failed` translations unchanged.
3. **Core library (`bluey/`)** — `_runGattOp` gains a branch translating `PlatformPermissionDeniedException` to the existing user-facing `PermissionDeniedException`. No new public exception types. `BlueyPlatformException` already has a `code` field from PR #10.

Layering: Kotlin is the authoritative source of the error taxonomy; Dart adapter translates Pigeon codes; core library translates platform-interface exceptions to the public API. No cross-layer imports beyond the existing `bluey_android → bluey_platform_interface` dependency.

## Error Mapping

Every Kotlin throw falls into exactly one row.

### `BlueyAndroidError` → `FlutterError` — context-aware

| `BlueyAndroidError` case | Client helper (`CentralManagerImpl` role) | Server helper (`GattServer` role) |
|---|---|---|
| `DeviceNotConnected`                   | `gatt-disconnected`               | (N/A — server doesn't use) |
| `NoQueueForConnection`                 | `gatt-disconnected`               | (N/A) |
| `CharacteristicNotFound(uuid)`         | `gatt-disconnected`               | `gatt-status-failed` w/ status `0x0A` |
| `DescriptorNotFound(uuid)`             | `gatt-disconnected`               | (N/A — server doesn't look up descriptors this way) |
| `CentralNotFound(id)`                  | (N/A)                             | `gatt-status-failed` w/ status `0x0A` |
| `ConnectionTimeout`                    | `gatt-timeout`                    | (N/A) |
| `GattConnectionCreationFailed`         | `bluey-unknown`                   | (N/A) |
| `SetNotificationFailed(uuid)`          | `gatt-status-failed` w/ status `0x01` | (N/A — server uses notify via response path) |
| `FailedToOpenGattServer`               | (N/A)                             | `bluey-unknown` |
| `FailedToAddService(uuid)`             | (N/A)                             | `bluey-unknown` |
| `BluetoothAdapterUnavailable`          | `bluey-unknown`                   | `bluey-unknown` |
| `BluetoothNotAvailableOrDisabled`      | `bluey-unknown`                   | `bluey-unknown` |
| `BleScannerNotAvailable`               | `bluey-unknown`                   | (N/A) |
| `BleAdvertisingNotSupported`           | (N/A)                             | `bluey-unknown` |
| `InvalidDeviceAddress(address)`        | `bluey-unknown`                   | (N/A) |
| `AdvertisingStartFailed(reason)`       | (N/A)                             | `bluey-unknown` |
| `NotInitialized(component)`            | `bluey-unknown`                   | `bluey-unknown` |
| `PermissionDenied(permission)`         | `bluey-permission-denied` w/ `details=permission` | `bluey-permission-denied` w/ `details=permission` |
| Any other `Throwable` (catch-all)      | `bluey-unknown` with `javaClass.simpleName` | `bluey-unknown` with `javaClass.simpleName` |

### Rationale for `CharacteristicNotFound` client vs server split

On the client side, `CharacteristicNotFound` fires when `ConnectionManager` looks up a characteristic in its cache and finds nothing. In practice this means the peer disconnected and Android invalidated the service layout — semantically equivalent to the iOS `BlueyError.notFound` → `gatt-disconnected` mapping. On the server side, the same sealed case fires when a peer's GATT request references a characteristic the user never registered on the hosted service — a programming error, not a disconnect. Mapping both to `gatt-disconnected` would turn server programming errors into fake `DisconnectedException` events on the Dart side. Same split as iOS's `toClientPigeonError` / `toServerPigeonError`.

File-level separation enforces the distinction: `BlueyPlugin.kt` wraps `connectionManager.xxx` calls with `.toClientFlutterError()` and `gattServer.xxx` calls with `.toServerFlutterError()`. No call site ever chooses the wrong mapping.

### Dart-side additions

| Pigeon code (new) | Platform-interface translation | Core library translation in `_runGattOp` |
|---|---|---|
| `bluey-permission-denied` | Throws new `PlatformPermissionDeniedException(permission)` where `permission` is the single missing permission name from Pigeon's `details` field | `PermissionDeniedException([permission])` — wraps the single permission in a one-element list to match the existing public class's `List<String>` shape |

### Defensive backstops (unchanged from PR #10)

- `_runGattOp` catches any residual `PlatformException` → wraps as `BlueyPlatformException(code:e.code, message, cause)`. Still the final safety net; the Android sealed hierarchy makes this branch effectively unreachable for known code paths, but it remains for defence in depth.

## Data Flow

### Before

```
connection.writeCharacteristic(...)
  → Kotlin: throw IllegalStateException("Device not connected")
  → Pigeon: serialises as PlatformException(code:"IllegalStateException")
  → Dart adapter: doesn't match any gatt-* code → rethrows
  → _runGattOp: catches PlatformException → wraps as BlueyPlatformException(code:"IllegalStateException")
  → User code: catches as BlueyPlatformException, must switch on code string
```

### After

```
connection.writeCharacteristic(...)
  → Kotlin: throw BlueyAndroidError.DeviceNotConnected
  → BlueyPlugin.kt catch(Throwable) → e.toClientFlutterError() → FlutterError("gatt-disconnected", msg, null)
  → Pigeon: PlatformException(code:"gatt-disconnected")
  → Dart adapter: translates → GattOperationDisconnectedException
  → _runGattOp: translates → DisconnectedException(deviceId, DisconnectReason.linkLoss)
  → User code: catches as `on DisconnectedException` (same contract as iOS)
```

### Permission-denial flow (new)

```
connection.writeCharacteristic(...) — user revoked BLUETOOTH_CONNECT mid-session
  → Kotlin: throw BlueyAndroidError.PermissionDenied("BLUETOOTH_CONNECT")
  → BlueyPlugin.kt → .toClientFlutterError() → FlutterError("bluey-permission-denied", msg, "BLUETOOTH_CONNECT")
  → Pigeon: PlatformException(code:"bluey-permission-denied", message:msg, details:"BLUETOOTH_CONNECT")
  → Dart adapter: translates → PlatformPermissionDeniedException(permission:"BLUETOOTH_CONNECT")
  → _runGattOp: translates → PermissionDeniedException(["BLUETOOTH_CONNECT"])
  → User code: `on PermissionDeniedException catch (e) { showRationale(); requestPermission(); }`
```

## Components

### Kotlin — `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/`

- **`BlueyAndroidError.kt`** (new) — sealed class hierarchy covering every current `IllegalStateException` / `SecurityException` throw. Each case is either an `object` (no payload) or a `data class` (carrying a UUID, permission name, or similar context).
- **`Errors.kt`** (new) — extension file with two `internal fun Throwable.toClientFlutterError()` / `toServerFlutterError()` helpers implementing the table above via exhaustive `when` over the sealed hierarchy.
- **`ConnectionManager.kt`** (modify) — replace every `throw IllegalStateException("X")` with `throw BlueyAndroidError.X` (with context fields where relevant). Approximate 17 sites.
- **`Scanner.kt`** (modify) — replace the 3 throws.
- **`Advertiser.kt`** (modify) — replace the 4 throws (including `onStartFailure` callback path).
- **`GattServer.kt`** (modify) — replace the ~8 throws.
- **`BlueyPlugin.kt`** (modify) — wrap every Pigeon-facing method body in `try { ... } catch (e: Throwable) { throw e.toClientFlutterError() }` (or `.toServerFlutterError()` for `GattServer`-delegating methods). Replace the ~10 `IllegalStateException("X not initialized")` throws with `throw BlueyAndroidError.NotInitialized("X")`.

### Platform interface — `bluey_platform_interface/lib/src/exceptions.dart`

- Add `PlatformPermissionDeniedException(String permission)` — mirrors the existing `GattOperationUnknownPlatformException` pattern. Internal platform-interface signal, not part of the `BlueyException` hierarchy. Carries the single permission name (e.g. `"BLUETOOTH_CONNECT"`) that was missing.

### Dart platform adapter — `bluey_android/lib/src/android_connection_manager.dart`

- Add one new case to `_translateGattPlatformError` (or whatever the file's equivalent helper is named) for `bluey-permission-denied` → throws `PlatformPermissionDeniedException`.

### Core library — `bluey/`

- `lib/src/connection/bluey_connection.dart` — `_runGattOp` gains a branch `on platform.PlatformPermissionDeniedException catch (e) { throw PermissionDeniedException([e.permission]); }` before the existing `PlatformException` backstop.

## Testing Strategy

### Kotlin

- **`bluey_android/android/src/test/kotlin/com/neutrinographics/bluey/ErrorsTest.kt`** (new) — table-driven unit tests:
  - `toClientFlutterError`: one test per `BlueyAndroidError` case, asserting expected `code` and `details` (status byte where relevant). Plus a "random `RuntimeException` → `bluey-unknown` with class name" case.
  - `toServerFlutterError`: same pattern for the server-applicable cases plus the key regression: `BlueyAndroidError.CharacteristicNotFound` server-side MUST map to `gatt-status-failed(0x0A)`, NOT `gatt-disconnected`. Locks the client/server distinction down (analogue of iOS's `PeripheralManagerErrorTests.swift`).
- Run via `cd bluey_android/android && ./gradlew test` (same harness as existing `GattOpQueueTest.kt`).

### Dart — platform adapter

- **`bluey_android/test/android_connection_manager_test.dart`** (extend) — one new test: `PlatformException(code:'bluey-permission-denied')` → `PlatformPermissionDeniedException`.

### Dart — core library

- **`bluey/test/connection/bluey_connection_test.dart`** (extend) — one new test: injected `PlatformPermissionDeniedException` at the `_runGattOp` boundary surfaces as `PermissionDeniedException`. Use the existing `FakeBlueyPlatform.simulateReadError` hook added in PR #10.

### Swift / iOS

- No changes. iOS tests from PR #10 remain green.

### Manual / on-device verification

- **Smoke test A:** revoke `BLUETOOTH_CONNECT` at the OS level mid-session, attempt a stress test. Expected: `PermissionDeniedException` caught by example app and displayed. Previously would have been `BlueyPlatformException(IllegalStateException)` / similar.
- **Smoke test B:** re-run the original post-PR-10 stress scenario (burst / failure-injection against Android as client). Expected: the `BlueyPlatformException(IllegalStateException) × 8` entries disappear — failures are now typed (`DisconnectedException` or `GattOperationFailedException` with a known status).
- **Regression:** all stress tests that passed after PR #10 continue to succeed. Swift tests still green.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| 30+ Kotlin throw sites mechanically rewritten; a miss leaves raw `IllegalStateException` leaking | Post-refactor `grep` for `throw IllegalStateException\|throw SecurityException\|throw RuntimeException` in Kotlin sources must return zero hits. Also, the `Throwable`-level safety net in `toClientFlutterError` / `toServerFlutterError` funnels anything unexpected to `bluey-unknown`. |
| Server-side `CharacteristicNotFound` routed through `toClientFlutterError` | File-level context in `BlueyPlugin.kt` wrapping. `ErrorsTest.kt` asserts server-side mapping produces `gatt-status-failed(0x0A)`, not `gatt-disconnected`. Analogue of iOS's `PeripheralManagerErrorTests`. |
| Kotlin message strings evolve (they cross the wire via Pigeon's `message` field) | Messages are developer diagnostics; Dart-side code parses only `code` + `details`. Messages may change freely. |
| User code catching `on PlatformException` specifically stops matching | Breaking change in spirit, not in signature. Same situation as PR #10 on iOS. Document in PR description. |
| New Pigeon code `bluey-permission-denied` predates old Dart adapter versions | Monorepo workspace resolves from a single lockfile. N/A for this release cadence. |
| iOS asymmetry: no `PermissionDeniedException` from iOS GATT ops | Document in README / CLAUDE.md platform-differences section. iOS users handle unauthorized state via `bluey.state` stream (existing pattern). |

## Out of Scope (Future Work)

- iOS emitting `bluey-permission-denied` when `CBManagerState.unauthorized`.
- Investigating the iOS-client → Android-server stress-test hang (separate debugging session).
- Typed exceptions for Bluetooth-adapter-state changes mid-op.
- Converting the rest of the library's pre-existing `throw Exception('...')` internal paths (e.g. in the example app) to the new sealed hierarchy — those don't cross the FFI boundary so they don't leak `PlatformException`.

## Approval

Sections 1 (architecture/scope), 2 (mapping table), 3 (implementation pattern — option b, sealed hierarchy), 4 (testing), and 5 (risks) approved by Joel on 2026-04-23.
