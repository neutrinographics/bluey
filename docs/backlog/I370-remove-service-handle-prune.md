---
id: I370
title: Prune the server's local handle table on removeService
category: bug
severity: medium
platform: domain
status: open
last_verified: 2026-07-10
related: [I086]
---

## Symptom

`_localCharHandles` is written on `addService` and read by
`notify`/`indicate` but never pruned: after `removeService`, a notify
resolves a stale handle and fails at the platform (audit DA-28 — the
live Dart-side face of the still-open iOS race
[I086](I086-remove-service-race-with-notify.md)).

## Location

`bluey/lib/src/gatt_server/bluey_server.dart`.

## Notes

Evict the removed service's entries; a re-added same-UUID service must
mint fresh handles. Directly testable with the fake.
