# Changelog

## 0.4.0

**Breaking changes:**

- `BlueyIos.disconnectCentral` removed (Pigeon API + native impl).

## 0.3.0

**Structured logging pipeline (I307):**

- New `BlueyLog` Swift singleton with native-side level filter + Pigeon bridge to Dart. Native log events flow into the unified `bluey.logEvents` stream as the single source of truth.
- New native logs at meaningful points (CB delegate callbacks, op-slot events, addService/advertising, request handling, state transitions). Closes the iOS observability gap (the iOS library previously had zero `NSLog`/`print` calls).
- `setLogLevel` HostApi method honors the Dart-set level — no Pigeon traffic for filtered events.

## 0.2.0

**Breaking changes (I088, I089, I066, I300, I301)** — bundled major-version rewrite. iOS-implementation changes; consult `bluey/CHANGELOG.md` for the full domain-side surface.

- **Pigeon GATT methods routed by handle (I088, I011).** `readCharacteristic` / `writeCharacteristic` / `setNotification` / `readDescriptor` / `writeDescriptor` / `notifyCharacteristic` / `notifyCharacteristicTo` route entirely by `int characteristicHandle` (and `int descriptorHandle` where applicable). The Swift side resolves `CBCharacteristic` / `CBDescriptor` via a per-peripheral handle table.
- **Handles minted client-side.** CoreBluetooth has no native equivalent of `getInstanceId()`. Handles are minted via a per-device monotonic counter at `peripheral(_:didDiscoverCharacteristicsFor:)` and `peripheral(_:didDiscoverDescriptorsFor:)`. Characteristics and descriptors share the counter pool.
- **Handle table cleared on `centralManager(_:didDisconnectPeripheral:error:)`** and on **`peripheral(_:didModifyServices:)`** (the iOS Service Changed equivalent).
- **Server-side handles** minted in `PeripheralManagerImpl.addService` via a separate module-wide counter (only one local server per process). Cleared on `removeService`. A full clear on `peripheralManagerDidUpdateState(.poweredOff)` is tracked separately as I083.
- **Stale-handle ops return Pigeon error `gatt-handle-invalidated`,** which the Dart side translates to `AttributeHandleInvalidatedException`.
- **iOS connection extension surface deferred (I089/I066).** No iOS-specific `Connection` extension methods are exposed; `connection.ios` is reserved as a typed `IosConnectionExtensions?` on the Dart side, currently empty.

See `docs/superpowers/specs/2026-04-28-pigeon-gatt-handle-rewrite-design.md` for the full design.
See `IOS_BLE_NOTES.md` "Handle minting" section for operational details.
