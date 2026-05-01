---
id: I311
title: Server-side methods bypass the I099 typed-translation helper
category: bug
severity: medium
platform: domain
status: fixed
last_verified: 2026-05-01
fixed_in: 013fb3c
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

Fixed in `013fb3c`. All six methods now wrap the platform call in
`withErrorTranslation`, mirroring the post-I099 client-side pattern.
The entry's original listing missed `indicateTo`; same bug class, same
fix landed.

For `respondToRead` / `respondToWrite`, kept the server-domain
`ServerRespondFailedException` shape: the wrapper post-processes the
translated `GattOperationFailedException` (the
`withErrorTranslation`-translated form of platform-interface
`GattOperationStatusFailedException`) into `ServerRespondFailedException`
with `clientId` + `characteristicId` context the client side doesn't
need.

Behavior shift for non-platform-interface error types:
`withErrorTranslation`'s defensive backstop now wraps any unrecognized
`Object` into `BlueyPlatformException` (preserving the original on
`.cause`). Pre-I311, raw `StateError` / `RuntimeError` thrown by the
platform layer leaked unchanged from server methods. Post-I311, they're
typed. Matches the I099 contract: no raw error type leaks past the
domain seam. The I079
`requestCompleted-fires-even-if-platform-respond-throws` test updated
accordingly.

I040 (iOS notification-throughput backpressure that produces
`bluey-unknown`) remains open — this fix governs the **wrapper type**
that carries the code. Notifications are still dropped under iOS TX
queue pressure; the upstream cause needs a separate Swift retry queue.
