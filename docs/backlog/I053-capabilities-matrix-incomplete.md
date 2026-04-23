---
id: I053
title: "`Capabilities` matrix incomplete"
category: unimplemented
severity: medium
platform: platform-interface
status: open
last_verified: 2026-04-23
related: [I030, I031, I032, I033, I034, I051, I052]
---

## Symptom

`Capabilities` (in `bluey_platform_interface/lib/src/capabilities.dart`) describes a minimal set of platform features. It doesn't say anything about:

- **Scan**: RSSI threshold, manufacturer-data filtering, scan-mode selection, allow-duplicates, TX-power filtering.
- **Advertising**: manufacturer-data support (iOS=no, Android=yes), connectable toggle, advertise-mode, extended advertising.
- **Server**: read/write authorization, indication vs notification, prepared-write support, MTU-change notification, subscription confirmation.
- **Connection**: can-bond, can-request-phy, can-request-connection-priority, can-request-connection-parameters.

Without capability flags, domain code can't gate API calls or provide polite `UnsupportedOperationException` messages; callers must already know the platform's quirks. The iOS bonding/PHY/connection-parameter stubs (which correctly return empty because the platform can't support them — see I200) would be cleaner if they threw `UnsupportedOperationException` guarded by a capability check instead.

## Location

`bluey_platform_interface/lib/src/capabilities.dart:8-125`.

## Root cause

Initial cut shipped a narrow capability set. As the library grew and divergence between iOS and Android deepened, new flags weren't added.

## Notes

Fix direction:

1. Expand `Capabilities` to cover the above.
2. Populate from each platform's `bluey_android` / `bluey_ios` main class (both already provide a `Capabilities` — extend there).
3. Use capability checks inside the domain layer: each advertised-but-sometimes-unavailable method (bond, requestPhy, requestConnectionPriority, manufacturer data in advertising, etc.) should gate on the flag and throw `UnsupportedOperationException(operation, platform)` when not supported.

This turns silent no-ops on platforms-where-it's-impossible into loud errors. Complements I030–I034 (which fix Android-side stubs that *are* implementable) and I200 (iOS platform limits that aren't).

Closely related to an existing deprecation direction: the "silent stub returning default value" pattern is the worst case. Preferred ordering:

- If platform can do it, implement it.
- If platform can't do it ever, throw `UnsupportedOperationException`.
- Never return a lie.
