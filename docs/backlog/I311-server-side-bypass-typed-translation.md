---
id: I311
title: Server-side methods bypass the I099 typed-translation helper
category: bug
severity: medium
platform: domain
status: open
last_verified: 2026-04-30
related: [I099, I040, I308]
---

## Symptom

Five public methods on `BlueyServer` call the platform interface directly
without routing through `withErrorTranslation`:

- `notify` / `notifyTo`
- `indicate`
- `respondToWrite` / `respondToRead`

Raw `PlatformException` (from `package:flutter/services.dart`) leaks
unchanged to consumers. Two visible consequences:

1. **Public type contract is unstable.** Every other path on `Bluey` /
   `BlueyConnection` produces a `BlueyException` subtype (post-I099). The
   server-side methods produce `PlatformException` instead, breaking
   `try { ... } on BlueyException catch (e) { ... }` patterns.
2. **DDD seam violation.** Domain layer is surfacing a Flutter framework
   type to its consumers — exactly the leak that I308 / I309 flag elsewhere
   and that I099 was supposed to close everywhere.

`respondToWrite` and `respondToRead` already do *partial* manual
translation (catching `GattOperationStatusFailedException` to throw
`ServerRespondFailedException`), but anything outside that single typed
case — including `BlueyError.unknown` from the iOS plugin's notify-queue
backpressure path (see I040) — escapes as raw `PlatformException`.

## Location

`bluey/lib/src/gatt_server/bluey_server.dart`:
- `notify` (~line 352): `await _platform.notifyCharacteristic(handle, data)` — no wrapper.
- `notifyTo` (~line 386): `await _platform.notifyCharacteristicTo(...)` — no wrapper.
- `indicate` (~line 412): `await _platform.indicateCharacteristic(...)` — no wrapper.
- `respondToRead` (~line 492): inline manual catch of one typed exception; no wrapper.
- `respondToWrite` (~line 519): inline manual catch of one typed exception; no wrapper.

## Root cause

I099 (typed-error-translation rewrite) covered the client-side surface
(`BlueyConnection`, scan, connect/disconnect, extension methods) but did
not extend to the server-side `BlueyServer` calls. The omission predates
I099's scope decision and was not flagged in its design review.

## Notes

Fix sketch:

1. Wrap each of the five calls in `withErrorTranslation` (the helper from
   `bluey/lib/src/shared/error_translation.dart` introduced in I099).
2. Fold `respondToWrite` / `respondToRead`'s manual
   `GattOperationStatusFailedException` catch into the helper call —
   either by catching it on the outside (preserving `ServerRespondFailedException`)
   or by extending the helper to accept a typed-translation hook.
3. Add tests for each method asserting the typed exception type. The
   pattern from `bluey/test/connection/error_translation_test.dart` (or
   wherever the I099 tests live) is the model.

Estimated 1-2 hours. Pure follow-up — no behavioral change to the success
path, only a uniform exception-type contract on the failure path.

This is a clean small bundle on its own; it can also fold into the I040
fix bundle since the two surface together (I040 produces the `bluey-unknown`
code; I311 governs the wrapper type that carries the code).
