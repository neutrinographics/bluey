# Changelog

## 0.3.0

**Structured logging pipeline (I307):**

- New `BlueyLog` Kotlin singleton with native-side level filter + Pigeon bridge to Dart. Native log events flow into the unified `bluey.logEvents` stream as the single source of truth.
- All internal `Log.d/i/w/e` calls replaced. Logs are no longer written to `logcat` directly — consumers route the unified Dart stream wherever they want.
- `setLogLevel` HostApi method honors the Dart-set level — no Pigeon traffic for filtered events.

## 0.2.0

**Breaking changes (I088, I089, I066, I300, I301)** — bundled major-version rewrite. Android-implementation changes; consult `bluey/CHANGELOG.md` for the full domain-side surface.

- **Pigeon GATT methods routed by handle (I088, I011).** `readCharacteristic` / `writeCharacteristic` / `setNotification` / `readDescriptor` / `writeDescriptor` / `notifyCharacteristic` / `notifyCharacteristicTo` route entirely by `int characteristicHandle` (and `int descriptorHandle` where applicable). The Kotlin side resolves attribute objects via a per-`BluetoothGatt` handle table; the legacy UUID-keyed lookup paths are removed.
- **Characteristic handles use `BluetoothGattCharacteristic.getInstanceId()`.** Descriptor handles are minted client-side via a per-device monotonic counter, since `BluetoothGattDescriptor.getInstanceId()` is `@hide` in AOSP.
- **Handle table populated in `onServicesDiscovered`** (gated on `GATT_SUCCESS`). **Cleared on `STATE_DISCONNECTED`** and on **`onServiceChanged`** before re-discovery.
- **Stale-handle ops return Pigeon error `gatt-handle-invalidated`,** which the Dart side translates to `AttributeHandleInvalidatedException`.
- **`AndroidConnectionExtensions` (I089).** Bond, PHY, connection-parameters, connection-priority, and `refreshGattCache` are now exposed via the Android-only extension surface (`connection.android` on the Dart side); not declared on the cross-platform `Connection` interface.
- **`addService` (server side) returns populated handles** for the local service tree, used for handle-routed `notifyCharacteristic` / `notifyCharacteristicTo`.

See `docs/superpowers/specs/2026-04-28-pigeon-gatt-handle-rewrite-design.md` for the full design.
See `ANDROID_BLE_NOTES.md` "Handle lifetime" section for operational details.
