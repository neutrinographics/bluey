---
id: I308
title: Domain layer catches Flutter `PlatformException` directly (framework dependency leak)
category: limitation
severity: low
platform: domain
status: open
last_verified: 2026-04-29
related: [I309, I099]
---

## Symptom

`bluey/lib/src/connection/bluey_connection.dart:83` (and the post-I099 unified helper `bluey/lib/src/shared/error_translation.dart`) catches `PlatformException` from `package:flutter/services.dart`. CLAUDE.md states "Domain layer has zero framework dependencies" — but the bluey-domain package both imports `package:flutter/services.dart` and pattern-matches against `PlatformException` as part of its anti-corruption ladder.

Strictly: a Flutter type appears in the domain layer's catch ladder. A future port of the domain logic to a non-Flutter Dart context (server-side BLE bridge, CLI tool, isolate worker) would inherit a hard Flutter dependency for no domain-modeling reason.

## Location

- `bluey/lib/src/shared/error_translation.dart` — the catch ladder includes `PlatformException` as a defensive backstop.
- `bluey/pubspec.yaml` — declares `flutter: sdk: flutter`.

## Root cause

Pigeon-generated bindings on the platform-interface side surface failures as `PlatformException`. The translation has historically happened at the bluey-domain layer rather than at the platform-interface boundary, so `PlatformException` leaks across the seam.

## Notes

Fix shape: move the Pigeon-`PlatformException` wrapping into the platform adapters (`bluey_android` / `bluey_ios`) so anything reaching the platform-interface API is already typed as a `bluey_platform_interface` exception (`GattOperationUnknownPlatformException` or similar). The bluey-domain catch ladder then only sees platform-interface types, never Flutter types. The platform-interface package would carry the Flutter dependency, the domain would not.

Cost-benefit: low severity. The current setup works; the dependency leak is purely architectural. Worth fixing if a non-Flutter Dart consumer of the domain layer ever materializes, or as part of a broader DDD pass on bounded-context dependencies.

Related to I309 — both are facets of "domain layer has implementation-detail dependencies it shouldn't carry."
