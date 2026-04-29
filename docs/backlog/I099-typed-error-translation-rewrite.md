---
id: I099
title: Replace string-matching error wrapping with typed catch ladder throughout domain layer
category: bug
severity: high
platform: domain
status: fixed
last_verified: 2026-04-29
fixed_in: 6427cc8
related: [I090, I092]
---

> **Fixed 2026-04-29** across 5 commits (`0a72a42..6427cc8`) per the spec at `docs/superpowers/specs/2026-04-29-typed-error-translation-rewrite-design.md`. New helper `bluey/lib/src/shared/error_translation.dart` provides `translatePlatformException` (pure) + `withErrorTranslation` (Future sugar with optional LifecycleClient accounting). All `_wrapError` sites in `Bluey` migrated; `BlueyConnection.disconnect/bond/removeBond/requestPhy/requestConnectionParameters` no longer bypass translation; scanner `onError` translates platform errors. `Bluey.errorStream` removed (breaking). 23 new tests; 812 bluey tests pass.

## Symptom

`Bluey._wrapError` uses `error.toString().toLowerCase().contains(...)` to classify errors into domain exceptions. This is brittle (locale-sensitive, format-sensitive, dependent on every platform's error string), and it discards the typed exceptions that the platform interface already produces (`GattOperationTimeoutException`, etc.). The right path through `_runGattOp` exists for GATT operations, but `connect`, `disconnect`, `bond`, `removeBond`, `requestPhy`, `requestConnectionParameters`, `requestEnable`, `authorize`, `openSettings`, `bondedDevices`, `configure` all bypass it.

## Location

- `bluey/lib/src/bluey.dart:607-644` — `_wrapError`.
- `bluey/lib/src/bluey.dart:173-275, 366, 462` — methods that call `_wrapError` instead of typed translation.
- `bluey/lib/src/connection/bluey_connection.dart:402, 443, 448, 464, 478` — `disconnect`, `bond`, `removeBond`, `requestPhy`, `requestConnectionParameters` bypass `_runGattOp`.

## Root cause

Two error-translation paths emerged: a typed catch ladder (`_runGattOp`) for GATT operations, and a string-matching fallback (`_wrapError`) for everything else. The string-matching path predates the typed platform-interface exception hierarchy and was never retired.

## Notes

Coherent fix:

1. **Extract the `_runGattOp` catch ladder into a shared helper** in `bluey/lib/src/shared/error_translation.dart` or similar. Make it operation-agnostic; `_runGattOp` becomes a thin wrapper that adds the lifecycle-accounting side effects.

2. **Replace every `_wrapError` call with the typed helper.** `_wrapError` is deleted; the `_errorController.add(...)` side effect is inlined where it's actually wanted (probably only at the top-level Bluey error stream, not at every operation).

3. **Extend `BlueyConnection.disconnect/bond/removeBond/requestPhy/requestConnectionParameters` to use the typed helper too.** This is I090 generalized.

4. **Add typed translation to `Scanner` operations (I092 currently open).** Same helper, same path.

5. **Preserve the lifecycle-accounting hook from I097.** `_runGattOp` does typed exception translation *and* lifecycle accounting (`markUserOpStarted` / `markUserOpEnded` / `recordActivity` / `recordUserOpFailure`) through one funnel. Any extracted helper must thread an optional `LifecycleClient?` parameter through so the lifecycle accounting is preserved at every call site that uses it. The extraction shape is roughly:

   ```dart
   // In bluey/lib/src/shared/error_translation.dart:
   Future<T> translateGattErrors<T>(
     UUID deviceId,
     String operation,
     Future<T> Function() body, {
     LifecycleClient? lifecycleClient,  // <- preserved
   }) async {
     lifecycleClient?.markUserOpStarted();
     try {
       final result = await body();
       lifecycleClient?.recordActivity();
       return result;
     } on platform.GattOperationTimeoutException catch (e) {
       lifecycleClient?.recordUserOpFailure(e);
       throw GattTimeoutException(operation);
     }
     // ... rest of catch ladder ...
     finally {
       lifecycleClient?.markUserOpEnded();
     }
   }
   ```

   Call sites that don't have a lifecycle (e.g., `Bluey.requestEnable`, `Scanner.scan`) pass `lifecycleClient: null` and the accounting is skipped — only the exception translation runs. The single helper serves both populations.

6. **Maintain the `recordUserOpFailure` filter.** I097 deliberately filters in `recordUserOpFailure` to only treat `GattOperationTimeoutException` as a peer-silence signal — user-op `statusFailed` errors (auth, write-not-permitted, etc.) are not peer-death signals. The rewrite must not break this distinction.

**Spec hand-off.** Suggested spec name: `2026-XX-XX-typed-error-translation-rewrite-design.md`.

External references:
- Effective Dart, [Use exception types that are documented and enforce a sealed hierarchy](https://dart.dev/effective-dart/usage#avoid-catches-without-on-clauses).
