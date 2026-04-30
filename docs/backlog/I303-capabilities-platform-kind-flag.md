---
id: I303
title: Replace iOS-detection heuristic on `Connection.ios` with a precise capability flag
category: limitation
severity: low
platform: domain
status: fixed
last_verified: 2026-04-30
fixed_in: e177f1d
related: [I089, I053, I065, I069]
---

## Symptom

`BlueyConnection.ios` returns the `IosConnectionExtensions` singleton when ALL of `Capabilities.canBond`, `Capabilities.canRequestPhy`, and `Capabilities.canRequestConnectionParameters` are false (heuristic introduced by I089/B.2). The intent is "iOS-flavored capabilities → expose iOS extensions; non-iOS → null." The heuristic is correct for today's two real platforms (Android = at least one of the three flags true; iOS = all three false), but it conflates "no Android-only features" with "iOS."

A future hypothetical platform — a stub/test backend, a future BLE-over-web implementation, or a third-party platform plugin — that has all three Android flags false would falsely advertise `connection.ios != null` even though it isn't iOS. Same trap on `FakeBlueyPlatform` if a test configures it with a custom `Capabilities` that happens to have all three flags false.

## Location

- `bluey/lib/src/connection/bluey_connection.dart:495-509` — the `ios` getter that uses the heuristic.
- `bluey/lib/src/connection/bluey_connection.dart:484-493` — symmetric `android` getter (less fragile because at least one Android-only flag is required).

## Root cause

`Capabilities` does not carry a platform-kind discriminator (e.g. `Capabilities.platformKind: PlatformKind { android, ios, web, fake, ... }` or a `Capabilities.isIos: bool` flag). The B.2 design used absence-of-Android-flags as a proxy.

## Notes

The fix has two shapes:

**Option A — `bool isIos` flag.** Minimal: add `final bool isIos` to `Capabilities`, default false, set true on iOS preset. The `ios` getter checks `caps.isIos` directly. Symmetric option for Android (`isAndroid`) is also reasonable.

**Option B — `PlatformKind` enum.** More extensible:
```dart
enum PlatformKind { android, ios, fake, unknown }

class Capabilities {
  final PlatformKind platformKind;
  // ...
}
```
The `android` and `ios` getters then dispatch on the enum. This makes adding future platforms (web BLE, etc.) straightforward.

**Recommendation:** Option B if the project ever expects to support more platforms; Option A is a defensible minimum.

This is best done alongside I053 (capabilities matrix expansion) and I065 (capabilities load-bearing) since all three touch `Capabilities`.

External references:
- Apple Accessory Design Guidelines, R8 (BLE) — confirms the iOS-side feature absence the heuristic relies on.
- The original I089 spec at `docs/superpowers/specs/2026-04-28-pigeon-gatt-handle-rewrite-design.md` calls out this heuristic as provisional.

## Resolution

Resolved 2026-04-30 with Option B from the entry: introduced
`PlatformKind { android, ios, fake, other }` enum and a required
`Capabilities.platformKind` field. `BlueyConnection.android` /
`BlueyConnection.ios` getters now dispatch on `platformKind` instead
of inferring from absent Android-only flags.
