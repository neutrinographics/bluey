# Changelog

## 0.4.0

**Breaking changes:**

- `Capabilities` constructor now requires `platformKind: PlatformKind`.
- `BlueyPlatform.disconnectCentral` removed.

**New:**

- `PlatformKind` enum + `Capabilities.platformKind` field.
- `Capabilities.canAdvertiseManufacturerData` flag.
- `Capabilities.fake` preset.

## 0.3.0

**Structured logging pipeline (I307):**

- New abstract `Stream<PlatformLogEvent> get logEvents` and `Future<void> setLogLevel(PlatformLogLevel level)` on `BlueyPlatform`.
- New types: `PlatformLogEvent`, `PlatformLogLevel`. Platform implementations forward native log events through this stream.

## 0.2.0

**Breaking changes (I088, I089, I066, I300, I301)** — bundled major-version rewrite. Platform-interface changes only; consult `bluey/CHANGELOG.md` for the full domain-side surface.

- **GATT method signatures route by handle (I088, I011).** The abstract `BlueyPlatform` GATT methods — `readCharacteristic`, `writeCharacteristic`, `setNotification`, `readDescriptor`, `writeDescriptor`, `notifyCharacteristic`, `notifyCharacteristicTo` — now take `int characteristicHandle` (and `int descriptorHandle` where applicable). UUID parameters are removed from these methods. Implementers must route entirely by handle.
- **Discovery DTOs carry handles.** `RemoteServiceDto`, `RemoteCharacteristicDto`, and `RemoteDescriptorDto` gain non-null `int handle` fields. UUIDs are retained for navigation/display.
- **`addService` returns populated handles.** The platform-side `addService` result now carries the platform-assigned handles for the registered local service tree, so the server side can route notifications by handle as well.
- **New error code `gatt-handle-invalidated`.** Platform implementations must raise this Pigeon error when a handle is non-null but absent from the per-connection handle table. The Dart side translates it to `AttributeHandleInvalidatedException`.
- **MTU is a value object (I301).** `requestMtu` and the `mtu` field on connection-state DTOs use `Mtu` rather than raw `int`.
- **Connection-extension methods relocated (I089/I066).** Bond, PHY, connection-parameters, connection-priority, and `refreshGattCache` are no longer on the cross-platform `BlueyPlatform` surface; Android moves them to the Android implementation; iOS stub removed.

See `docs/superpowers/specs/2026-04-28-pigeon-gatt-handle-rewrite-design.md` for the full design.
