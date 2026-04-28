# Changelog

## 0.2.0

**Breaking changes (I088, I089, I066, I300, I301)** — bundled major-version rewrite:

- **GATT routing by opaque handle (I088, I011).** `readCharacteristic` / `writeCharacteristic` / `setNotification` / `readDescriptor` / `writeDescriptor` / `notifyCharacteristic` / `notifyCharacteristicTo` now route by `int characteristicHandle` (and `int descriptorHandle` where applicable). UUIDs are retained on DTOs for display and navigation only; the wire is handle-only.
- **Singular accessors throw on ambiguity.** `Connection.service(uuid)`, `RemoteService.characteristic(uuid)`, and `RemoteCharacteristic.descriptor(uuid)` now throw `AmbiguousAttributeException(uuid, matchCount)` when more than one attribute matches the UUID. Use the new plural accessors `RemoteService.characteristics({UUID? uuid})` and `RemoteCharacteristic.descriptors({UUID? uuid})` to disambiguate.
- **Service Changed surfaces as a typed exception.** Stale-handle ops post-Service-Changed fail with `AttributeHandleInvalidatedException`. Cached service trees are invalidated; re-call `services()` to obtain fresh handles.
- **`Connection` interface trimmed (I089/I066).** Bond / PHY / connection-parameters / connection-priority / refreshGattCache moved to `connection.android?` (a typed null on iOS). `Connection.mtu` is now `Mtu` (was `int`); `Connection.requestMtu(Mtu)` takes the value object.
- **Peer composition (I300).** `Bluey.connect()` returns a raw `Connection` — no implicit peer upgrade. New `Bluey.connectAsPeer(device): Future<PeerConnection>` (throws `NotABlueyPeerException` on miss) and `Bluey.tryUpgrade(connection): Future<PeerConnection?>` for the rare post-connect upgrade path.
- **Value objects (I301).** `Mtu`, `ConnectionInterval(double ms)`, `PeripheralLatency(int events)`, `SupervisionTimeout(int ms)`, `ConnectionParameters` (with cross-field invariant), `AttributeHandle`. Validation at construction.
- **`RemoteCharacteristic.handle` and `RemoteDescriptor.handle` getters** expose the platform-assigned `AttributeHandle` for direct addressing on duplicate-UUID peripherals.

See `docs/superpowers/specs/2026-04-28-pigeon-gatt-handle-rewrite-design.md` for the full design.
