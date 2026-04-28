---
id: I088
title: Rewrite Pigeon GATT schema to thread service/characteristic context through every call
category: bug
severity: critical
platform: platform-interface
status: fixed
last_verified: 2026-04-28
fixed_in: 73656b4
related: [I010, I011, I016]
---

## Symptom

I010, I011, and I016 all stem from the same root cause: the Pigeon schema for GATT operations carries only `(deviceId, characteristicUuid)` or `(deviceId, descriptorUuid)` tuples, not the full identity context. On peripherals with multiple services exposing characteristics with the same UUID, or multiple notifiable characteristics (each carrying a CCCD `0x2902`), operations are non-deterministically routed to the wrong attribute.

This is a wire-protocol-level identity-loss problem affecting every GATT operation. The current backlog tracks the consequences as separate critical entries; this entry exists to track the coherent rewrite.

## Location

- `bluey_android/pigeons/messages.dart` — the schema declarations (e.g. `readCharacteristic(String deviceId, String characteristicUuid)`).
- `bluey_ios/pigeons/messages.dart` — same schema.
- `bluey_platform_interface/lib/src/platform_interface.dart` — abstract methods mirror the schema.
- All Android/iOS implementations — receivers of the calls.

## Root cause

Initial schema design conflated UUID identity with attribute identity. UUIDs are not unique within a peripheral's GATT database; (service, characteristic, instance) is the unique identity.

## Notes

Two viable schemas:

**Option A — explicit service/characteristic context tuples:**

```dart
@async
Uint8List readCharacteristic(
  String deviceId,
  String serviceUuid,
  String characteristicUuid,
);

@async
void writeDescriptor(
  String deviceId,
  String serviceUuid,
  String characteristicUuid,
  String descriptorUuid,
  Uint8List value,
);
```

Pros: simple, language-portable. Cons: can't disambiguate two characteristics with the same UUID *within* the same service (rare but spec-allowed).

**Option B — opaque platform handles (preferred for "perfection"):**

The platform side assigns an opaque integer or string handle to each discovered attribute (e.g., Android's `BluetoothGattCharacteristic.getInstanceId()`). The handle is returned in `discoverServices` results and used as the key in subsequent ops. The Dart side never tries to identify attributes by UUID alone — it carries handles.

```dart
class CharacteristicDto {
  final String uuid;
  final int handle;     // <- opaque, platform-assigned
  // ...
}

@async
Uint8List readCharacteristic(String deviceId, int characteristicHandle);
```

Pros: spec-correct, robust to duplicate UUIDs at any level. Cons: handles must be lifetime-managed (invalidated on Service Changed, disconnect); requires platform-side handle table.

**Recommended path:** Option B. The reference implementation pattern is `bluetooth_low_energy_android` (mentioned in I010 notes) which uses `getInstanceId()`. This is the spec-faithful approach.

This rewrite is breaking. Plan as a major version bump, with a migration guide.

**Spec hand-off.** This entry is intended to be expanded into a full spec under `docs/superpowers/specs/`. Suggested spec name: `2026-XX-XX-pigeon-gatt-handle-rewrite-design.md`.

External references:
- Android [`BluetoothGattCharacteristic.getInstanceId()`](https://developer.android.com/reference/android/bluetooth/BluetoothGattCharacteristic#getInstanceId()).
- BLE Core Specification 5.4, Vol 3, Part G, §3.2.2: characteristic declaration uniqueness within a service.
- [`bluetooth_low_energy_android`](https://github.com/yanshouwang/bluetooth_low_energy) reference impl — search for `instanceId` usage in their characteristic lookup.

## Resolution

Fixed in the bundled handle-rewrite (Option B from the notes above): every GATT attribute is now identified on the wire by an opaque platform-assigned `int handle` wrapped in the `AttributeHandle` value object. Android characteristic handles come from `BluetoothGattCharacteristic.getInstanceId()`; descriptor handles, iOS characteristic handles, and iOS descriptor handles are minted client-side via a per-device monotonic counter. Handles are connection-scoped and invalidated on disconnect or Service Changed, surfacing stale-handle ops as `AttributeHandleInvalidatedException`. This bundle subsumes I010, I011, and I016. See `docs/superpowers/specs/2026-04-28-pigeon-gatt-handle-rewrite-design.md` for the full design and `docs/superpowers/plans/2026-04-28-pigeon-gatt-handle-rewrite.md` for the execution sequence.
