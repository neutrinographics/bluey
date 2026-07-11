---
id: I357
title: Translate errors on domain streams and the server write-respond path
category: bug
severity: medium
platform: domain
status: open
last_verified: 2026-07-10
---

## Symptom

Consumers can receive a raw `PlatformException` where the sealed
`BlueyException` contract is promised: `stateChanges` /
`bondStateChanges` / `phyChanges` / `notifications` re-emit platform
errors untranslated, and the iOS server's `respondToWriteRequest`
lacks the `bluey-not-found` translation its read counterpart has
(audit DA-08, DA-09 — including the `StateError` a client-gone race
throws into `readRequests`/`writeRequests`).

## Location

`bluey/lib/src/connection/bluey_connection.dart` stream `onError`
sites; `bluey/lib/src/gatt_server/bluey_server.dart` request mapping.

## Notes

Route stream `onError` through `translatePlatformException`; give
write-respond the read path's translation; capture the `Client` at the
eviction chokepoint so orphaned requests are dropped or respond-error'd
instead of throwing into the consumer's stream.
