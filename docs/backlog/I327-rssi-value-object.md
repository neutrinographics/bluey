---
id: I327
title: Wrap `Connection.rssi` in a value object
category: enhancement
severity: low
platform: domain
status: open
last_verified: 2026-05-05
related: [I325, I301]
---

## Symptom

`Connection.rssi` returns a raw `int`. This is the only remaining GATT-spec primitive in the `Connection` aggregate that is not wrapped in a value object — `Mtu`, `ConnectionInterval`, `PeripheralLatency`, `SupervisionTimeout`, and `AttributeHandle` are all wrapped (per I301), and I325 added `WritePayloadLimit` to the same pattern. RSSI is the odd one out.

CLAUDE.md mandates: "Value objects are immutable with equality by value." A bare `int` representing a signed signal strength in dBm is primitive obsession at the GATT-spec boundary.

## Location

- `bluey/lib/src/connection/connection.dart` — abstract `int get rssi` on `Connection`.
- `bluey/lib/src/connection/bluey_connection.dart` — concrete impl.
- `bluey_platform_interface/lib/src/platform_interface.dart` — `Future<int> readRssi(String deviceId)` (stays raw int below the seam, per the pattern).

## Proposed API

```dart
@immutable
class Rssi {
  factory Rssi(int dbm) {
    // BLE spec: RSSI is reported in dBm, signed. Spec range is roughly
    // -127 to +20 dBm, with -127 indicating "no value".
    if (dbm < -127 || dbm > 20) {
      throw ArgumentError.value(dbm, 'dbm', 'RSSI out of BLE-spec range');
    }
    return Rssi._(dbm);
  }

  factory Rssi.fromPlatform(int dbm) => Rssi._(dbm);

  const Rssi._(this.dbm);

  final int dbm;

  // equality, hashCode, toString
}
```

`Connection.rssi` becomes `Future<Rssi> get rssi` (or stays as method since it's already async-ish). `Rssi.fromPlatform` bypasses validation for platform reads, mirroring the `Mtu.fromPlatform` pattern.

## Migration

Touch `Connection.rssi` readers (a small handful in tests + example UI) and update them to call `.dbm` on the value object.

## Why low severity

- Cosmetic / consistency fix. No correctness implications.
- Bare `int` already works; no consumer is harmed.
- Worth doing for the value-object consistency cited in CLAUDE.md, but not urgent.

## Notes

- I301 introduced the value-object pattern for the rest of the Connection aggregate; this entry closes the gap.
- Bundle with any other Connection-aggregate value-object work if a future ticket touches the same area; otherwise standalone.
