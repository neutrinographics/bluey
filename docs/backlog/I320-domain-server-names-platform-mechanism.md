---
id: I320
title: BlueyServer constructs PlatformAdvertiseConfig naming platform mechanisms (`scanResponseServiceUuids`) instead of expressing intent
category: limitation
severity: low
platform: domain
status: open
last_verified: 2026-05-04
related: [I313]
---

## Symptom

`BlueyServer.startAdvertising` (domain layer) splits the user-supplied
service UUIDs from the lifecycle control UUID and stuffs each into a
specific platform-interface field by name:

```dart
// bluey/lib/src/gatt_server/bluey_server.dart
final scanResponseUuids = <String>[
  if (peerDiscoverable &&
      !primaryUuids.contains(lifecycle.controlServiceUuid))
    lifecycle.controlServiceUuid,
];
final config = platform.PlatformAdvertiseConfig(
  serviceUuids: primaryUuids,
  scanResponseServiceUuids: scanResponseUuids,
  // ...
);
```

"Scan response" is BLE-spec / Android-platform vocabulary. The domain
layer is reaching across the seam and naming a transport mechanism
rather than expressing the domain intent ("the control UUID is part of
peer-discoverability").

## Location

- `bluey/lib/src/gatt_server/bluey_server.dart:330-345` — direct DTO
  construction with `scanResponseServiceUuids`.

## Root cause

I313 (which routes the control UUID through Android's scan-response
slot) added the field at the platform-interface layer using BLE-spec
vocabulary, consistent with the project convention documented in
`CLAUDE.md`:

> The platform-interface layer uses BLE-spec-aligned vocabulary
> (`Central`, `Peripheral`, `PlatformDevice`). The seam between them
> translates intentionally.

The DDD-correct place for that translation is **at the seam itself**,
not inside `BlueyServer`. The domain layer should express the WHAT
("this UUID is flagged for peer discovery") and let the
platform-interface layer translate to the WHERE ("scan response on
Android, overflow on iOS via prepended position").

Today's shape works correctly — every consumer is in this monorepo and
the field name doesn't leak past `bluey_server.dart` — but it's a soft
boundary violation that will compound when more advertising knobs land
(I051, I318, etc.).

## Notes

**Sketch of the cleaner shape:**

1. Add a small intent-bearing struct at the seam:

   ```dart
   // bluey_platform_interface/lib/src/platform_interface.dart
   class PlatformAdvertiseConfig {
     factory PlatformAdvertiseConfig.from({
       required List<String> serviceUuids,
       List<String> peerDiscoveryServiceUuids = const [],
       // …other knobs…
     }) {
       // Translates intent → wire fields. Android puts
       // peerDiscoveryServiceUuids in scan response; iOS folds them into
       // the unified advertisement UUID list with primary-slot priority.
       return PlatformAdvertiseConfig._wire(
         serviceUuids: serviceUuids,
         scanResponseServiceUuids: peerDiscoveryServiceUuids,
         // …
       );
     }
     // wire-shape constructor stays for the platform plugins.
   }
   ```

2. Refactor `BlueyServer.startAdvertising` to use the intent-bearing
   factory, with no knowledge of "scan response" as a transport
   concept:

   ```dart
   final config = platform.PlatformAdvertiseConfig.from(
     serviceUuids: primaryUuids,
     peerDiscoveryServiceUuids: peerDiscoverable
         ? const [lifecycle.controlServiceUuid]
         : const [],
     // …
   );
   ```

3. Optional follow-on: rename `scanResponseServiceUuids` itself to
   `peerDiscoveryServiceUuids` at the platform-interface level, since
   the field's purpose is platform-independent even if the wire
   mechanism differs. The trade-off is losing some BLE-spec vocabulary
   alignment per `CLAUDE.md`, gaining a more honest abstraction. Worth
   discussing.

**Why low severity:** the current code is correct and self-contained.
This is a tax on future contributors who will see "scan response" in
domain code and reasonably wonder whether the domain has gained
platform-mechanism knowledge it shouldn't have.

**Test impact:** the existing tests assert on `scanResponseServiceUuids`
on the fake platform recorder. After this refactor they would assert on
the same wire-level field (since the fake mirrors the wire DTO) — but
the call site under test would be the intent-bearing factory, not
direct field naming.
