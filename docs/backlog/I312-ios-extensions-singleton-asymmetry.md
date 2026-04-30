---
id: I312
title: "`_IosConnectionExtensionsImpl` is a top-level const singleton; `_AndroidConnectionExtensionsImpl` is per-connection"
category: limitation
severity: low
platform: domain
status: open
last_verified: 2026-04-30
related: [I089]
---

## Symptom

`bluey/lib/src/connection/bluey_connection.dart` declares the two
platform-tagged extension impls asymmetrically:

- `_AndroidConnectionExtensionsImpl` is constructed per-connection
  (`_androidExtensions ??= _AndroidConnectionExtensionsImpl(this)` at
  line ~537) and holds a back-reference to its `BlueyConnection`.
- `_IosConnectionExtensionsImpl` is a top-level `const` singleton
  (`const _iosExtensions = _IosConnectionExtensionsImpl();` at line ~1280)
  with no instance state.

The `connection.ios` getter returns the same singleton for every
`BlueyConnection`, while `connection.android` returns a per-connection
facade.

## Location

- `bluey/lib/src/connection/bluey_connection.dart:537` — Android
  per-connection cache.
- `bluey/lib/src/connection/bluey_connection.dart:545` — iOS singleton
  return.
- `bluey/lib/src/connection/bluey_connection.dart:1276-1280` —
  `_IosConnectionExtensionsImpl` class and `_iosExtensions` const.

## Root cause

The iOS extensions class was introduced as an empty placeholder by I089
(platform-tagged extensions). With no instance members to expose and no
need for a `BlueyConnection` back-reference, a top-level const was the
minimum-overhead implementation.

## Notes

The current asymmetry is harmless today — `IosConnectionExtensions` has
no abstract members, so the singleton can never observe per-connection
state. The footgun materializes if iOS extensions ever gain methods that
need `this`:

- A future maintainer adds an `Future<void> setEncryptionRequired(...)`
  to `IosConnectionExtensions`.
- They implement it on `_IosConnectionExtensionsImpl` and reach for
  `_conn._platform.X(...)`.
- But there is no `_conn` field — the singleton has no per-connection
  context. They have to refactor to a per-connection construction
  pattern (mirroring the Android side) before they can land their
  feature.

Fix shape (when the need arises): refactor `_IosConnectionExtensionsImpl`
to take a `BlueyConnection` argument and cache it per-connection on
`BlueyConnection._iosExtensions`, mirroring the Android pattern.
Pre-emptive doing-it-now is YAGNI; documenting the trap in this entry
is sufficient until the first iOS-specific method materializes.

Recommend leaving a one-line comment near `_iosExtensions` referencing
this entry, so the next person who reaches for `_conn` sees the trap
before they hit it.
