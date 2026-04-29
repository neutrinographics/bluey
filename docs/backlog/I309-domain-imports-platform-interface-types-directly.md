---
id: I309
title: Domain layer imports `bluey_platform_interface` types directly instead of going through an abstract repository
category: limitation
severity: low
platform: domain
status: open
last_verified: 2026-04-29
related: [I308, I099]
---

## Symptom

`bluey/lib/src/connection/bluey_connection.dart:1`, `bluey/lib/src/bluey.dart:3`, `bluey/lib/src/gatt_server/bluey_server.dart:4`, plus the post-I099 unified `error_translation.dart` all directly import `package:bluey_platform_interface/bluey_platform_interface.dart` and pattern-match against its concrete types (`GattOperationTimeoutException`, `PlatformDevice`, `PlatformService`, etc.).

Per Clean Architecture: dependencies should point inward — the domain layer defines the abstractions it needs (e.g. abstract `BleConnectionRepository`), and outer layers (platform-interface, native) implement them. In Bluey today, the *platform-interface* layer defines the abstractions and the domain depends on it directly. This makes the domain non-portable: replacing the platform-interface package means rewriting the domain's imports and catch ladders.

## Location

Spread across the bluey-domain package — every file that imports `bluey_platform_interface` and references its types.

## Root cause

The package was designed with the platform-interface as the dependency seam, not as an implementation of a domain-defined abstraction. When `bluey_platform_interface` was extracted, the existing direct dependencies in bluey-domain were preserved rather than rewired through abstract domain interfaces.

## Notes

Proper fix shape (multi-day, breaking-internal):

1. **Define abstract domain repositories** in `bluey/lib/src/repositories/` (or similar): `BleConnectionRepository`, `BleScannerRepository`, `BleServerRepository`. These declare the operations the domain needs in domain-language terms — no `Platform*` prefixes, no platform-typed exceptions.
2. **Define a domain-side exception hierarchy at the seam** — already present (`BlueyException`); the new repositories throw these directly, never platform-interface types.
3. **Implement the repositories** in `bluey/lib/src/infrastructure/` as adapters that delegate to `bluey_platform_interface`. The translation (I099 helper) lives here, behind the seam.
4. **Domain code (`Bluey`, `BlueyConnection`, `BlueyServer`, etc.)** depends only on the abstract repositories. Platform-interface imports vanish from every domain file.

After the refactor: the bluey-domain package compiles without `bluey_platform_interface` as a direct import (it's transitively required at the implementation layer only). The same domain logic could be reused with a different platform-interface implementation by writing different adapters.

Cost-benefit: low severity. The current setup is "Clean Architecture-light" and works fine for the single-platform-interface reality. Real benefit accrues only if (a) we want a second platform-interface implementation (e.g. mock-only test backend that doesn't go through Pigeon), (b) we want to publish the bluey-domain package independently, or (c) we ever hit a refactoring scenario where platform-interface evolution is blocked by domain coupling.

Related to I308 — both are facets of "domain layer has implementation-detail dependencies it shouldn't carry." A coordinated fix could address both in one architectural pass.
