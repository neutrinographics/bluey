---
id: I065
title: Capabilities matrix is decorative; no production code consults it
category: bug
severity: medium
platform: domain
status: open
last_verified: 2026-04-26
related: [I053, I035, I066]
---

## Symptom

The `Capabilities` value object exists on `Bluey.capabilities` and on the platform interface. It documents what the platform supports. But almost no production code reads it before calling a feature. A consumer call to `connection.requestPhy(...)` on iOS does not check `capabilities.canRequestPhy` — it just calls through and silently no-ops or throws an obscure error.

The single existing check is `Bluey.server()` returning null when `!capabilities.canAdvertise`. That's it.

## Location

- `bluey/lib/src/bluey.dart:502` — only production capability check.
- `bluey_platform_interface/lib/src/capabilities.dart` — matrix declaration.

## Root cause

Capability flags were modeled and populated, but the discipline of "check capability before delegating to platform" was not established as a coding standard. New methods get added without adding their corresponding capability flag or check.

## Notes

Three-part fix:

1. **Expand the matrix** to cover every real asymmetry. Currently 8 flags; should be ~25 (see I053). Suggested additions:
   - `canRequestPhy: bool`
   - `canRequestConnectionParameters: bool`
   - `canRequestConnectionPriority: bool`
   - `canForceDisconnectRemoteCentral: bool`
   - `canRefreshGattCache: bool`
   - `canAdvertiseManufacturerData: bool`
   - `canAdvertiseInBackgroundWithName: bool`
   - `canFilterScanByName: bool`
   - `canFilterScanByManufacturerData: bool`
   - `canRetainPeripheralAcrossReinstall: bool`
   - `canDoExtendedAdvertising: bool`
   - `canDoCodedPhy: bool`
   - `canL2capCoc: bool`
   - `canStateRestoration: bool`

2. **Establish a capability-gating helper** in domain code:

   ```dart
   T _requireCapability<T>(bool flag, String op, T Function() body) {
     if (!flag) throw UnsupportedOperationException(op, _platformName());
     return body();
   }
   ```

3. **Consult capability flags from every cross-platform method** that might not be supported. `Connection.requestPhy`, `bond`, etc. should wrap their delegation in `_requireCapability`. (See also I066, which recommends the more invasive structural fix of moving these methods off `Connection` entirely.)

Without (3), the matrix is documentation only. With (3), the matrix becomes load-bearing and consumers can rely on it.

Partial overlap with I053 (capabilities matrix incomplete); may consolidate.
