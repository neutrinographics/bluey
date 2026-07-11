---
id: I355
title: Let server notify address a characteristic hosted under two services
category: bug
severity: medium
platform: domain
status: open
last_verified: 2026-07-10
related: [I088]
---

## Symptom

`Server.notify`/`indicate` resolve the characteristic by UUID alone and
take the first match, so a characteristic UUID hosted under two
services cannot be addressed individually — the exact collapse the
handle table was built to prevent (audit DA-05, latent).

## Location

`bluey/lib/src/gatt_server/bluey_server.dart` — `_resolveLocalHandle`
first-match on UUID.

## Notes

Mirror the client-side policy: throw `AmbiguousAttributeException` on
duplicate matches and add a service-scoped (or handle-typed) overload
as the disambiguation path.
