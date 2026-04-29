# Typed Error Translation Rewrite (I099 + I090 + I092)

**Status:** proposed
**Date:** 2026-04-29
**Scope:** `bluey` package — domain layer error-translation surface. No platform-interface change, no native change, no protocol change.
**Backlog entries:** [I099](../../backlog/I099-typed-error-translation-rewrite.md), [I090](../../backlog/I090-connect-disconnect-not-error-wrapped.md), [I092](../../backlog/I092-scan-errors-not-translated.md).

## Problem

Two error-translation paths coexist in `bluey/lib/src/`:

1. **Typed catch ladder** — `_runGattOp` in `bluey_connection.dart:46-96`. Catches `platform.GattOperation*Exception` / `PlatformPermissionDeniedException` by type and throws the corresponding `BlueyException` subtype. Threads optional `LifecycleClient?` for the I097 user-op accounting hooks.

2. **String-matching fallback** — `Bluey._wrapError` in `bluey.dart:854-891`. Inspects `error.toString().toLowerCase()` for substrings like `"permission"`, `"unauthorized"`, `"timeout"`, `"not connected"` and dispatches to `BlueyException` subtypes. Brittle: locale-sensitive, format-sensitive, dependent on every platform's free-text error messages, and *throws away* the typed exceptions the platform interface already produces.

Path (2) is used by:

- `Bluey.configure` (`bluey.dart:187`)
- `Bluey.state` getter (`bluey.dart:262`)
- `Bluey.requestEnable` (`bluey.dart:298`)
- `Bluey.authorize` / `Bluey.openSettings` (`bluey.dart:312, 321`)
- `Bluey.connect` (`bluey.dart:421`)
- `Bluey.bondedDevices` (`bluey.dart:701`)
- The state-stream `onError` hook (`bluey.dart:112`)

Plus path (2) is *also bypassed entirely* (raw `PlatformException` leaks unwrapped) at:

- `BlueyConnection.disconnect` (`bluey_connection.dart:402`)
- `BlueyConnection.bond` / `removeBond` (`bluey_connection.dart:443, 448`)
- `BlueyConnection.requestPhy` (`bluey_connection.dart:464`)
- `BlueyConnection.requestConnectionParameters` (`bluey_connection.dart:478`)
- `BlueyScanner.scan` `onError` (`bluey_scanner.dart:57-59`) — `addError(error)` forwards the platform's raw error onto the stream's error channel without translation.

A caller pattern-matching on `BlueyException` — the documented contract — misses every path-(2) site (gets the wrong typed subtype because string matching guessed wrong) and every bypass site (gets the raw platform exception).

## Goals

### In scope

- Single typed catch ladder shared across every domain-layer method that translates platform errors.
- Connect / disconnect / bond / removeBond / requestPhy / requestConnectionParameters route through the new helper (closes I090).
- Scanner stream errors translate before reaching subscribers (closes I092).
- `_wrapError` is removed; string-matching no longer drives error classification anywhere.
- I097's lifecycle-accounting hooks (`markUserOpStarted` / `recordActivity` / `recordUserOpFailure` / `markUserOpEnded`) preserved at every site that previously had them.

### Out of scope

- **Protocol-level changes.** No new platform-interface exception types. The mapping is platform-typed → domain-typed only.
- **Native error-code coverage expansion.** I091 (unmapped iOS `CBATTError` codes) and I013 (Android `onScanFailed` error code dropped) remain separate native-side fixes.
- **Moving the catch ladder out of the domain.** This rewrite consolidates ACL inside the bluey-domain package; it does not rewire the bounded-context dependencies. Two pre-existing concerns are filed as follow-ups for a separate architectural pass: [I308](../../backlog/I308-domain-catches-flutter-platform-exception.md) (domain catches Flutter `PlatformException` directly) and [I309](../../backlog/I309-domain-imports-platform-interface-types-directly.md) (domain depends on platform-interface concretes instead of abstract repositories). Both are low-severity DDD/Clean Architecture refinements.
- **`recordUserOpFailure` filter semantics.** I097 deliberately filters in `recordUserOpFailure` so only `GattOperationTimeoutException` is treated as a peer-silence signal — `statusFailed` errors (auth, write-not-permitted, etc.) are user-op failures, not peer-death signals. The rewrite preserves this behavior verbatim.
- **New domain exception types.** The existing hierarchy in `shared/exceptions.dart` covers what we need: `ConnectionException`, `GattTimeoutException`, `GattOperationFailedException`, `DisconnectedException`, `PermissionDeniedException`, `BluetoothDisabledException`, `BluetoothUnavailableException`, `AttributeHandleInvalidatedException`, `BlueyPlatformException`. Plus a new `ScanException` — see "Decisions" below.

## Decisions

1. **Two-layer extraction:** a pure mapping function plus a Future sugar.

   ```dart
   // Pure: usable from sync error handlers, stream onError callbacks,
   // and as the body of the Future sugar. No async, no lifecycle hooks.
   BlueyException translatePlatformException(
     Object error, {
     required String operation,
     UUID? deviceId,  // optional: connect/scan don't have one
   });

   // Sugar over try / catch + translate, with optional lifecycle accounting.
   Future<T> withErrorTranslation<T>(
     Future<T> Function() body, {
     required String operation,
     UUID? deviceId,
     LifecycleClient? lifecycleClient,
   });
   ```

   The pure function lets `BlueyScanner` and any future stream-based error path share the *same* mapping that GATT ops use, without forcing them through Future-shaped sugar. Critical for I092 (scan onError — pure-sync; can't use the Future helper).

   Naming note: the sugar is `withErrorTranslation` (not `translateGattErrors`) because it's used for non-GATT ops too — `Bluey.connect`, `Bluey.requestEnable`, `Bluey.bondedDevices`, plus scanner where we use the pure form. "GATT" in the old name would mislead readers into thinking the helper is GATT-specific; the *operation* arg is what carries that semantic.

   `operation: String` is a diagnostic label only — it lands in exception messages and log lines, never in control flow. Callers should not branch on its value. (If we ever need typed branching on operation kind, we promote it to a value object then; pre-1.0 we keep it loose.)

2. **`_runGattOp` becomes a thin wrapper.** Identical signature; body is `withErrorTranslation(...)`. Existing call sites unchanged. `_loggedGattOp` integration unchanged.

   **SRP trade-off (deliberate).** `withErrorTranslation` bundles two concerns: ACL (translate platform errors → domain exceptions) and lifecycle accounting (`markUserOpStarted` / `recordActivity` / `recordUserOpFailure` / `markUserOpEnded`). A strict reading of SRP would split them. We keep them bundled because (a) the optional `lifecycleClient: null` makes lifecycle accounting opt-in at zero cost for non-peer call sites, and (b) splitting forces every peer-aware call site to manually wrap the helper with try/finally for the lifecycle hooks — exactly the boilerplate the helper exists to eliminate. Pure-translation callers (scanner, connect, requestEnable) pass `lifecycleClient: null` and pay only for the catch-and-translate.

3. **`_wrapError` is deleted.** Every call site adopts `translateGattErrors`. The `_errorController.add(...)` side effect is *not* preserved — see decision (4).

4. **`Bluey.errorStream` is removed (breaking).** It was only ever populated by `_wrapError`. Callers should pattern-match on the typed `BlueyException` thrown from the failing call, or subscribe to `bluey.logEvents` for observability. Existing alternatives:
   - **Control flow** → typed exceptions (already documented contract).
   - **Observability** → `bluey.logEvents` (post-I307 structured logging stream, already shipping).
   - **App-level error funnels** → caller's responsibility, not the library's.

   The CHANGELOG entry covers this as a breaking change in the unreleased section.

5. **`ScanException` added.** A new sealed `BlueyException` subtype for scanner errors (covers `BluetoothDisabledException`, `PermissionDeniedException`, and a generic `ScanException(reason)` fallback). Closes I092 at the domain-type boundary.

6. **`onError` of the state stream:** the wrapper at `bluey.dart:112` translates and re-emits the typed exception on the *state-stream's* error channel — same as scanner. State-stream subscribers already have `onError` plumbing; just need typed errors there.

## Architecture

### New file: `bluey/lib/src/shared/error_translation.dart`

```dart
import 'package:bluey_platform_interface/bluey_platform_interface.dart' as platform;
import 'package:flutter/services.dart' show PlatformException;

import '../connection/lifecycle_client.dart';
import 'exceptions.dart';
import 'uuid.dart';

/// Pure mapping from platform-interface exceptions to the domain
/// [BlueyException] hierarchy. No async, no lifecycle hooks. Safe to
/// call from stream `onError` handlers, sync catch blocks, and the
/// body of [translateGattErrors].
///
/// [operation] is included in messages for diagnostics. [deviceId] is
/// optional — non-GATT call sites (connect, scan) pass `null`.
BlueyException translatePlatformException(
  Object error, {
  required String operation,
  UUID? deviceId,
}) {
  if (error is BlueyException) return error;

  if (error is platform.GattOperationTimeoutException) {
    return GattTimeoutException(operation);
  }
  if (error is platform.GattOperationDisconnectedException) {
    return DisconnectedException(
      deviceId ?? UUID.short(0x0000),
      DisconnectReason.linkLoss,
    );
  }
  if (error is platform.GattOperationStatusFailedException) {
    return GattOperationFailedException(operation, error.status);
  }
  if (error is platform.GattOperationUnknownPlatformException) {
    if (error.code == 'gatt-handle-invalidated') {
      return AttributeHandleInvalidatedException();
    }
    return BlueyPlatformException(
      error.message ?? 'unknown platform error (${error.code})',
      code: error.code,
      cause: error,
    );
  }
  if (error is platform.PlatformPermissionDeniedException) {
    return PermissionDeniedException([error.permission]);
  }
  if (error is PlatformException) {
    return BlueyPlatformException(
      error.message ?? 'platform error (${error.code})',
      code: error.code,
      cause: error,
    );
  }
  // Defensive backstop: anything else gets wrapped, never leaked raw.
  return BlueyPlatformException(error.toString(), cause: error);
}

/// Future-shaped sugar over [translatePlatformException], with optional
/// lifecycle-accounting hooks (preserves I097 user-op accounting).
///
/// Lifecycle hooks fire iff [lifecycleClient] is non-null:
/// - `markUserOpStarted()` before the body
/// - `recordActivity()` on success
/// - `recordUserOpFailure(originalError)` before re-throw on caught failure
/// - `markUserOpEnded()` in finally
///
/// Note: [recordUserOpFailure] is called with the *original* platform
/// exception (not the translated domain exception), because the I097
/// filter inside `recordUserOpFailure` examines the platform-side type.
///
/// [operation] is a diagnostic label only — used in exception messages
/// and log lines, never in control flow. Do not branch on its value.
Future<T> withErrorTranslation<T>(
  Future<T> Function() body, {
  required String operation,
  UUID? deviceId,
  LifecycleClient? lifecycleClient,
}) async {
  lifecycleClient?.markUserOpStarted();
  try {
    final result = await body();
    lifecycleClient?.recordActivity();
    return result;
  } catch (error) {
    lifecycleClient?.recordUserOpFailure(error);
    throw translatePlatformException(
      error,
      operation: operation,
      deviceId: deviceId,
    );
  } finally {
    lifecycleClient?.markUserOpEnded();
  }
}
```

### `_runGattOp` collapses to a wrapper

```dart
Future<T> _runGattOp<T>(
  UUID deviceId,
  String operation,
  Future<T> Function() body, {
  LifecycleClient? lifecycleClient,
}) {
  return withErrorTranslation(
    body,
    operation: operation,
    deviceId: deviceId,
    lifecycleClient: lifecycleClient,
  );
}
```

(`_loggedGattOp` is unchanged — it still calls `_runGattOp`.)

### `_wrapError` is deleted

Every call site rewrites:

```diff
- try {
-   await _platform.connect(device.address, config);
- } catch (e) {
-   throw _wrapError(e);
- }
+ await withErrorTranslation(
+   () => _platform.connect(device.address, config),
+   operation: 'connect',
+ );
```

Specific replacements (all in `bluey/lib/src/bluey.dart`):

| Site | Operation arg | deviceId arg |
|---|---|---|
| `configure` | `'configure'` | none |
| `state` getter | `'getState'` | none |
| `requestEnable` | `'requestEnable'` | none |
| `authorize` | `'authorize'` | none |
| `openSettings` | `'openSettings'` | none |
| `connect` | `'connect'` | `device.id` |
| `bondedDevices` | `'getBondedDevices'` | none |

State-stream `onError` (line 112): translated via the pure `translatePlatformException`, then `_stateController.addError`.

### `BlueyConnection` non-GATT methods adopt the helper

The five methods at `bluey_connection.dart:402, 443, 448, 464, 478` get the same treatment as GATT ops. They aren't activity-bearing in the lifecycle-accounting sense (disconnect / bond / PHY are out-of-band), so they pass `lifecycleClient: null` even on a peer connection — pure translation only.

| Method | operation arg |
|---|---|
| `disconnect` | `'disconnect'` |
| `bond` | `'bond'` |
| `removeBond` | `'removeBond'` |
| `requestPhy` | `'requestPhy'` |
| `requestConnectionParameters` | `'requestConnectionParameters'` |

### `BlueyScanner` errors

`bluey_scanner.dart:57-59` becomes:

```dart
onError: (Object error) {
  controller.addError(translatePlatformException(
    error,
    operation: 'scan',
  ));
},
```

If `translatePlatformException` returns `BlueyPlatformException` for an error that should really be `ScanException` (e.g., a future native error code we don't yet handle), that's fine: callers still catch on `BlueyException`. Specific `ScanException` cases (Bluetooth off, unauthorized) are typically already typed at the platform side and surface as `BluetoothDisabledException` / `PermissionDeniedException` via the existing branches.

If we discover a scan-specific platform error that needs typed routing, we add a `platform.PlatformScanException` (or similar) at the platform-interface layer in a follow-up. Out of scope here.

### `Bluey.errorStream` removal

```diff
- /// Stream of errors from Bluey operations.
- Stream<BlueyException> get errorStream => _errorController.stream;
- final StreamController<BlueyException> _errorController = ...;
```

Plus `dispose()` no longer closes it.

### New domain type: `ScanException`

```dart
sealed class ScanException extends BlueyException { ... }
```

Implementation deferred until we have a concrete scan-only failure mode that doesn't fit the existing exception types. For this rewrite, we don't add it preemptively. **Update I092 entry**: closed when scan errors translate via the typed helper, regardless of whether `ScanException` is added.

## Migration / breaking changes

For the unreleased changelog section:

> **Breaking:** `Bluey.errorStream` is removed. Pattern-match on the typed `BlueyException` thrown from the failing call, or subscribe to `bluey.logEvents` for observability.
>
> **Breaking (in spirit, not in API shape):** several call sites that previously yielded `BlueyPlatformException` (the catch-all from `_wrapError`) now yield more-specific subtypes — e.g., `Bluey.connect` failures with platform timeout now throw `GattTimeoutException` instead of `BlueyPlatformException`. Callers using `is` checks against the specific subtypes will see different (more accurate) types post-upgrade.

## Testing

TDD-driven, one site per failing test → impl pair. Helper module gets its own unit test file.

### `test/shared/error_translation_test.dart` (new)

Pure-function tests for `translatePlatformException`. One test per platform exception type → expected domain type. Plus a defensive-backstop test that an arbitrary `Object` passed in produces `BlueyPlatformException` and never leaks raw.

### `test/shared/with_error_translation_test.dart` (new)

Future-sugar tests:
- Success path: `recordActivity` fires once, `markUserOpEnded` fires once.
- Failure path: `recordUserOpFailure` fires with the *original* platform exception (not the translated one); the translated exception is what's thrown.
- No-lifecycle path: passing `lifecycleClient: null` translates errors but skips all hooks.

### Existing `bluey_connection_test.dart` / cousins

Unchanged in spec, but expected to pass post-rewrite because `_runGattOp` is functionally identical.

### `test/bluey_test.dart` (additions)

For each `_wrapError` replacement:
- Inject a fake platform that throws a typed platform exception (e.g., `platform.GattOperationTimeoutException` from `_platform.connect`).
- Assert the domain method throws the correct typed `BlueyException` subtype.

### `test/connection/bluey_connection_disconnect_test.dart`, etc.

Add tests for the five `BlueyConnection` non-GATT methods that previously bypassed translation.

### `test/discovery/bluey_scanner_test.dart`

Add a test that fakes a platform scan error and asserts the typed exception lands on the scan stream's error channel.

## Phasing / commit plan

Five commits, each shippable independently:

1. `feat(bluey): extract translatePlatformException + translateGattErrors helper` — new file, unit tests, no call-site changes. _runGattOp thin-wraps the helper.
2. `feat(bluey): replace _wrapError in Bluey facade with typed helper` — 7 call sites, per-site failing test → pass.
3. `feat(bluey): translate errors on BlueyConnection.{disconnect,bond,removeBond,requestPhy,requestConnectionParameters} (I090)` — 5 sites.
4. `feat(bluey): translate scanner stream errors (I092)` — `BlueyScanner.scan` onError.
5. `feat(bluey)!: remove Bluey.errorStream` — last commit, includes CHANGELOG breaking-change entry, deletes `_errorController`, swaps the example app's debug-print sink (`example/lib/main.dart:40`) to `bluey.logEvents` filtered to `level >= warn`.

Backlog updates:
- I099: `status: fixed`, `fixed_in: <commit-sha-of-5>`.
- I090: `status: fixed`, `fixed_in: <commit-sha-of-3>`.
- I092: `status: fixed`, `fixed_in: <commit-sha-of-4>`.

## Risks

- **Behavioral regression on undocumented strings.** Some callers may be pattern-matching on the *string content* of `BlueyPlatformException.message`. The new typed paths produce different message text. Mitigated by the typed-subtype API being the documented contract; string content was never stable.
- **Stream-error channel UX.** Subscribers to scan / state streams now see typed exceptions on `onError`. Subscribers that ignored `onError` entirely are unaffected. Subscribers that did `if (e is PlatformException)` will need to update — but they were broken anyway, since the platform-side exceptions vary by adapter.
- **`recordUserOpFailure` filter regression.** The I097 invariant (only `GattOperationTimeoutException` is a peer-silence signal) lives inside `recordUserOpFailure`, not in our translation helper. The rewrite passes the *original* platform exception to that hook to preserve the invariant. New unit test in `translate_gatt_errors_test.dart` pins this contract down.

## Open questions

- **`Bluey.errorStream` deprecation vs. removal.** The spec proposes immediate removal. Alternative: deprecate in this version, remove in a later one. Counterargument: pre-1.0; we've been making breaking changes freely. There is one consumer (`bluey/example/lib/main.dart:40` — a `debugPrint` sink), trivially replaceable by subscribing to `bluey.logEvents` filtered to `level >= warn`. Going with removal; the example app is updated as part of commit 5.

- **Whether to add `ScanException` now.** Spec says no — wait until we have a concrete scan-only failure mode that doesn't fit existing types. Closes I092 at the typed-helper level rather than at the new-type level.
