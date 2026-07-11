---
id: I371
title: Defensive-copy byte buffers and unify DTO value equality
category: bug
severity: low
platform: domain
status: open
last_verified: 2026-07-10
---

## Symptom

`ManufacturerData` and `Advertisement.serviceData` store and return
`Uint8List` buffers by reference while defining equality over those
bytes — post-construction mutation silently corrupts equality/hash
(audit DA-29, latent). Separately, 12 of 17 `@immutable` platform DTOs
have reference equality while 5 define value equality, with no
documented rule (DA-30).

## Notes

Copy on construction (`Uint8List.fromList` / `List.unmodifiable`);
add uniform value equality matching the exemplary `PlatformLogEvent`,
or document the input-vs-output split.
