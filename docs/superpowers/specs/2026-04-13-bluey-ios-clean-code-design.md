# bluey_ios Clean Code Refactor — Design Spec

## Goal

Split the monolithic `BlueyIos` class (812 lines) into focused delegate classes mirroring the Android architecture, add Dart-side unit tests, and add Swift-side timeout handling for stalled CoreBluetooth operations.

## Approach

Three workstreams:
1. **Dart structural split** — Extract `IosScanner`, `IosConnectionManager`, `IosServer` from `BlueyIos`, mirroring the Android pattern
2. **Dart tests** — Test each delegate with mocked `BlueyHostApi` using `mocktail`
3. **Swift timeouts** — Add `DispatchQueue.main.asyncAfter` timeouts to `CentralManagerImpl.swift` for operations that could hang indefinitely

---

## Step 1: Extract `IosScanner`

### Changes

**Create `bluey_ios/lib/src/ios_scanner.dart`:**

- Receives `BlueyHostApi` in constructor
- Owns `StreamController<PlatformDevice>` for scan results
- `scan()`, `stopScan()`
- `onDeviceDiscovered(DeviceDto)` — callback handler, maps DTO with UUID expansion
- Private `_mapDevice()` — maps DeviceDto to PlatformDevice, expands short UUIDs in serviceUuids

**Move `_expandUuid` to `bluey_ios/lib/src/uuid_utils.dart`** — currently a top-level private function in `bluey_ios.dart`. Move it to its own file as a public top-level function `expandUuid()` so all three delegates can import it. Move the `_bluetoothBaseUuidSuffix` constant with it.

**Create `bluey_ios/test/ios_scanner_test.dart`:**

- scan() calls hostApi.startScan with correct config
- onDeviceDiscovered emits to scan stream with correct mapping
- Device mapping expands short UUIDs (16-bit "180F" → full 128-bit)
- Device mapping expands 32-bit UUIDs
- Full 128-bit UUIDs pass through unchanged
- stopScan calls hostApi.stopScan

**Update `BlueyIos`** — delegate scanning, remove `_scanController` and `_mapDevice`.

---

## Step 2: Extract `IosConnectionManager`

### Changes

**Create `bluey_ios/lib/src/ios_connection_manager.dart`:**

- Receives `BlueyHostApi` in constructor
- Owns per-device `_connectionStateControllers` and `_notificationControllers` maps
- Connection: `connect()`, `disconnect()`, `connectionStateStream()`, `notificationStream()`
- GATT client: `discoverServices()`, `readCharacteristic()`, `writeCharacteristic()`, `setNotification()`, `readDescriptor()`, `writeDescriptor()`, `readRssi()`
- iOS-specific: `requestMtu()` throws `UnsupportedError`
- Bonding: `getBondState()` → none, `bondStateStream()` → empty, `bond()` → no-op, `removeBond()` → throws UnsupportedError, `getBondedDevices()` → empty list
- PHY: `getPhy()` → throws, `phyStream()` → empty, `requestPhy()` → throws
- Connection params: `getConnectionParameters()` → throws, `requestConnectionParameters()` → throws
- Callback handlers: `onConnectionStateChanged()`, `onNotification()` (with UUID expansion), `onMtuChanged()`
- DTO mapping with `expandUuid()` on all UUID fields: `_mapService()`, `_mapCharacteristic()`, `_mapDescriptor()`
- Cleans up per-device streams on disconnect

**Create `bluey_ios/test/ios_connection_manager_test.dart`:**

- connect/disconnect lifecycle with stream cleanup
- Connection state routing to correct device stream
- Notification routing with UUID expansion
- Service discovery maps DTOs with UUID expansion
- readCharacteristic/writeCharacteristic delegation
- Unsupported operations throw: requestMtu, removeBond, getPhy, requestPhy, getConnectionParameters, requestConnectionParameters
- Bonding stubs return expected defaults

**Update `BlueyIos`** — delegate all connection/GATT/bonding/PHY/params methods.

---

## Step 3: Extract `IosServer`

### Changes

**Create `bluey_ios/lib/src/ios_server.dart`:**

- Receives `BlueyHostApi` in constructor
- Owns 4 server stream controllers
- Service management, advertising, notifications/indications, request/response handling
- Callback handlers with UUID expansion on request characteristicUuid fields
- DTO mapping for local services, permissions, GATT status
- Note: iOS `AdvertiseConfigDto` does not include `mode` (Android-only)

**Create `bluey_ios/test/ios_server_test.dart`:**

- addService maps PlatformLocalService to DTO correctly
- startAdvertising maps config (no mode parameter for iOS)
- Callback handlers emit to correct streams with UUID expansion
- respondToReadRequest/respondToWriteRequest map GATT status correctly

**Update `BlueyIos`** — delegate all server methods.

---

## Step 4: Swift Timeout Handling

### Changes

**Modify `bluey_ios/ios/Classes/BlueyError.swift`:**

Add `case timeout` to the `BlueyError` enum with description "Operation timed out".

**Modify `bluey_ios/ios/Classes/CentralManagerImpl.swift`:**

Add timeouts to these operations using `DispatchQueue.main.asyncAfter`:

| Operation | Default Timeout | Notes |
|-----------|----------------|-------|
| `connect()` | `config.timeoutMs` or 30s | Honor existing param, cancel `CBCentralManager.connect()` on timeout |
| `discoverServices()` | 15s | Cancel and fail completion |
| `readCharacteristic()` | 10s | Fail pending completion |
| `writeCharacteristic()` | 10s | With-response only |
| `readDescriptor()` | 10s | Fail pending completion |
| `writeDescriptor()` | 10s | Fail pending completion |
| `readRssi()` | 5s | Fail pending completion |

**Pattern:** Each operation schedules a delayed block that checks if the completion handler is still in the pending map. If so, it removes it and calls it with `BlueyError.timeout`. When the real CoreBluetooth callback fires, it removes the completion from the map first — so the timeout block finds nothing and does nothing.

**Connect timeout cleanup:** On connect timeout, call `centralManager.cancelPeripheralConnection(peripheral)` to cancel the CoreBluetooth connection attempt.

**No timeouts for:** `setNotification()` (reliable), `disconnect()` (reliable), scan (no completion pattern).

---

## Testing Strategy

**Dart tests (~30 new):**
- `ios_scanner_test.dart` — ~6 tests including UUID expansion
- `ios_connection_manager_test.dart` — ~14 tests including unsupported operations
- `ios_server_test.dart` — ~10 tests including UUID expansion on requests

**No Swift timeout tests** — the timeout pattern is simple (asyncAfter guarded by completion removal). Best verified through integration testing.

---

## Out of Scope

- Kotlin/Android changes
- Pigeon definition changes
- New BLE features
- PeripheralManagerImpl.swift changes (server-side Swift)
- Resource pruning of stale per-device streams
