---
id: I367
title: Hoist the quadruplicated BluetoothState mapper into shared
category: refactor
severity: low
platform: domain
status: open
last_verified: 2026-07-10
---

## Symptom

The identical 5-case platform-to-domain `BluetoothState` switch is
duplicated verbatim in `bluey.dart`, `bluey_connection.dart`,
`bluey_server.dart`, and `bluey_scanner.dart` — contradicting the
codebase's own rule that ACL mappings live in exactly one place
(audit DA-24).

## Notes

One `mapBluetoothState` in `shared/`, four call sites updated. Pure
mechanical refactor behind existing tests.
