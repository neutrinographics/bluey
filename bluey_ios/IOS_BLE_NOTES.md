# iOS BLE Implementation Notes

This document captures iOS BLE quirks, limitations, and corner cases discovered during development. It serves as operational knowledge for anyone maintaining or extending the iOS implementation.

## Peripheral Manager (Server Role)

### No Client Disconnection Callback

`CBPeripheralManagerDelegate` does **not** provide a callback when a connected client disconnects. This is a known gap in CoreBluetooth that has existed since iOS 6 and has not been addressed through iOS 18.

The delegate provides these client-related callbacks:
- `peripheralManager(_:central:didSubscribeTo:)` — client subscribes to notifications
- `peripheralManager(_:central:didUnsubscribeFrom:)` — client unsubscribes from notifications
- `peripheralManager(_:didReceiveRead:)` — client reads a characteristic
- `peripheralManager(_:didReceiveWrite:)` — client writes to a characteristic

None of these directly indicate a BLE connection or disconnection.

**Our approach:** We infer client connections from any interaction (subscribe, read, or write). The first time we see a `CBCentral` from any of these callbacks, we fire `onCentralConnected`. See `trackCentralIfNeeded()` in `PeripheralManagerImpl.swift`.

### Unsubscribe vs Disconnect Ambiguity

When a client disconnects (gracefully or by going out of range), CoreBluetooth automatically cleans up its subscriptions and fires `didUnsubscribeFromCharacteristic:` for each subscribed characteristic. This is the **same callback** that fires when a client explicitly unsubscribes but stays connected.

There is no way to distinguish between:
1. Client explicitly unsubscribed but is still connected (can still read/write)
2. Client disconnected and CoreBluetooth is cleaning up subscriptions

**Current behavior:** We treat the last unsubscription as a disconnection (`onCentralDisconnected`). This means:
- If a client unsubscribes from all characteristics but stays connected, we incorrectly report it as disconnected
- The client reappears when it performs its next read or write (via `trackCentralIfNeeded`)

**Industry standard:** Every major BLE peripheral library (`ble_peripheral`, `flutter_ble_peripheral`, `RxBluetoothKit`) uses the same workaround. There is no better solution within the CoreBluetooth API.

**Alternative approaches considered:**
- **L2CAP channels (iOS 11+):** Publishing an L2CAP channel and monitoring the `NSStream` for `endEncountered` provides a definitive disconnect signal. However, this requires the client to explicitly open the channel and adds protocol-level complexity on both sides.
- **Application-level heartbeat:** Having the client periodically write to a characteristic and treating timeout as disconnection. Requires client cooperation and adds BLE traffic.
- **Polling `subscribedCentrals`:** Periodically checking `CBMutableCharacteristic.subscribedCentrals`. Not event-driven and unreliable.

### Client Tracking Without Subscriptions

If a client only reads and writes without subscribing to any characteristic, we will never receive a disconnection signal. The client will remain in our tracked list indefinitely until:
- The server is disposed
- The client is explicitly disconnected via `disconnectCentral()`
- The lifecycle heartbeat timeout fires (see below)

### Solution: Lifecycle Control Service

Bluey solves the disconnect detection problem with an internal control service that is invisible to library consumers. When `Bluey.server()` is called with a non-null `lifecycleInterval` (the default is 10 seconds), the server automatically adds a hidden GATT service with a heartbeat characteristic.

**How it works:**

1. The Bluey server adds the control service before advertising starts
2. When a Bluey client connects and discovers services, it recognizes the control service by its UUID and starts sending periodic heartbeat writes (at half the server's interval)
3. The server maintains a per-client timer. Each heartbeat resets the timer. If no heartbeat arrives within `lifecycleInterval`, the server fires a disconnect event
4. Before disconnecting, the client writes a special disconnect command for immediate cleanup — no timer wait
5. The control service is filtered from the public `services()`, `readRequests`, and `writeRequests` APIs. Consumers never see it

**What this solves:**
- Reliable disconnect detection on iOS without native API support
- Clean disconnect notification even when `cancelPeripheralConnection` doesn't terminate the physical link
- Force-kill detection via heartbeat timeout
- Consistent behavior across iOS and Android

**Configuration:**
```dart
final server = bluey.server();                                    // lifecycle enabled, 10s default
final server = bluey.server(lifecycleInterval: Duration(seconds: 5)); // custom interval
final server = bluey.server(lifecycleInterval: null);             // disabled, raw BLE behavior
```

**Limitation:** Non-Bluey clients connecting to a Bluey server won't send heartbeats. They will be timed out after `lifecycleInterval` unless lifecycle management is disabled.

## Advertising

### Advertised Name (CBAdvertisementDataLocalNameKey)

When set via `startAdvertising`, the custom name is placed in the BLE advertisement packet.

**Foreground only:** iOS includes the custom name in advertisements only while the app is in the foreground. In background mode, the name is stripped from the advertisement and service UUIDs are moved to a special "overflow area."

**28-byte limit:** The total advertisement payload for name and service UUIDs combined is limited to 28 bytes. If the name is too long, iOS may truncate it (sending it as a "Shortened Local Name").

**GAP Device Name is separate:** After a client connects, it reads the Generic Access Profile (GAP) Device Name characteristic (0x2A00), which is managed by iOS and set to the device name from Settings > General > About > Name. This may differ from the advertised name. The app cannot control the GAP name.

### Advertising in Background

When the app moves to the background:
- The advertised name (`CBAdvertisementDataLocalNameKey`) is removed
- Service UUIDs move to a special overflow area, only visible to iOS devices scanning for those specific UUIDs
- Android devices will not discover the peripheral via service UUID filter while the iOS app is backgrounded

### Manufacturer Data Not Supported

`CBPeripheralManager.startAdvertising()` ignores manufacturer-specific data. Only `CBAdvertisementDataLocalNameKey` and `CBAdvertisementDataServiceUUIIDsKey` are supported in the advertising dictionary.

## Disconnect Central Limitations

iOS does not provide a direct way to disconnect a connected client from the peripheral side. `CBPeripheralManager` has no `cancelConnection` or equivalent method.

**Our approach (post-I045):** `disconnectCentral` throws `BlueyPlatformException` (translated from `gatt-status-failed` with REQUEST_NOT_SUPPORTED) instead of silently untracking and returning success. Lying to the caller masks the platform limitation and leads to "ghost peer" bugs where the central keeps reading/writing/subscribing after the server believes it gone.

Bluey peers (clients that speak the lifecycle protocol) can write `0x00` to the heartbeat characteristic as a cooperative disconnect signal — that path lives on the *client* side via `PeerConnection.disconnect()` and is fully effective. There is no server-initiated equivalent on iOS. Pre-I045 callers that depended on the silent untrack should either: (a) catch the throw and use `removeService` / `stopAdvertising` for global teardown, or (b) negotiate a client-driven disconnect via the lifecycle protocol.

## Permissions

### Bluetooth Usage Descriptions

iOS requires usage description strings in `Info.plist`:
- `NSBluetoothAlwaysUsageDescription` — required for all Bluetooth usage (iOS 13+)
- `NSBluetoothPeripheralUsageDescription` — required for peripheral role (iOS 6-12, deprecated but still needed for backwards compatibility)

### No Runtime Permission Request for Bluetooth

Unlike Android, iOS does not have a runtime permission prompt specifically for Bluetooth scanning or connecting. The system prompts the user for Bluetooth access the first time `CBCentralManager` or `CBPeripheralManager` is initialized. If denied, the manager reports state `.unauthorized`.

## Central Role (Scanner/Client)

### cancelPeripheralConnection Does Not Reliably Terminate the BLE Link

`cancelPeripheralConnection()` does **not** directly terminate the physical BLE connection. It decrements an internal reference count. iOS treats BLE connections as **shared resources multiplexed across all apps and system services**. The actual link termination (`LL_TERMINATE_IND`) is only sent when every consumer — including system services — releases the connection.

This is an intentional Apple design decision, not a bug.

**Why it happens:**

- iOS system services (notably ANCS — Apple Notification Center Service) may hold their own reference to the same BLE connection. When your app calls `cancelPeripheralConnection`, iOS releases your app's reference but keeps the link alive for ANCS or other services.
- A TI engineer confirmed with a BLE sniffer that when ANCS is active, the disconnect packet is literally never sent.
- Even without system services, iOS may delay physical disconnection by ~30 seconds to avoid rapid reconnect/disconnect cycles.
- `didDisconnectPeripheral` fires locally (the app thinks it disconnected), but the physical link stays up.

**Observed behavior:** When an iOS app disconnects from an Android peripheral:
- iOS reports the disconnect immediately via `didDisconnectPeripheral` (local cleanup succeeds)
- Android's GATT server never receives `onConnectionStateChange` with `STATE_DISCONNECTED`
- The Android side shows the client as still connected indefinitely
- Only toggling Bluetooth off on iOS (which forces the radio down) causes Android to detect the link loss via supervision timeout

**Industry status:** Every major Flutter BLE library (flutter_blue_plus, flutter_reactive_ble) has the same problem with no solution. This is a fundamental CoreBluetooth limitation.

**Recommended workaround:** For applications that need reliable cross-platform disconnect, use an application-level disconnect protocol — have the client write a "disconnect command" to a custom characteristic, and let the server initiate the disconnection from its side. The server's `LL_TERMINATE_IND` is always sent because the server owns the connection.

### BLE Address Rotation

iOS uses random resolvable BLE addresses for privacy. Each time an iOS device connects to a peripheral, it may use a different random MAC address. This means:
- The same iPhone may appear as multiple connected clients on the Android server
- Stale entries from previous connections (with old rotated addresses) will never receive a disconnect event
- There is no API to correlate two different addresses to the same physical device

**Implication:** The connected clients list on an Android server may accumulate stale entries from an iOS device reconnecting with rotated addresses. These entries will persist until the GATT server is restarted.

## Device Name (UIDevice.current.name)

Starting with iOS 16, `UIDevice.current.name` returns only the generic model name ("iPhone", "iPad") instead of the user-assigned device name (e.g., "Joel's iPhone"). The full device name requires the `com.apple.developer.device-information.user-assigned-device-name` entitlement, which requires approval from Apple.

## Known Limitations

1. **No client disconnection callback** — `CBPeripheralManager` does not report when clients disconnect. We infer connections from interactions and use subscription cleanup as a proxy for disconnection.
2. **Cannot force-disconnect clients** — No API to disconnect a client from the peripheral side.
3. **Unsubscribe/disconnect ambiguity** — Cannot distinguish between explicit unsubscribe and link loss.
4. **Background advertising limitations** — Name dropped, service UUIDs moved to overflow area, not visible to Android scanners.
5. **No manufacturer data in advertising** — CoreBluetooth ignores manufacturer data in the advertising dictionary.
6. **GAP name not controllable** — The name shown after connection is the system device name, not the advertised name.
7. **Device name restricted (iOS 16+)** — `UIDevice.current.name` returns generic model name without special entitlement.
8. **cancelPeripheralConnection unreliable** — iOS treats connections as shared resources; `cancelPeripheralConnection` only releases the app's reference. The physical link stays up if system services (ANCS, etc.) maintain their own reference. The remote device may never receive a disconnect.
9. **BLE address rotation** — iOS uses random addresses per connection, causing stale client entries on remote servers.

## Handle minting (2026-04-28, I088)

GATT attribute identity on the wire is a per-connection opaque `int handle` (`AttributeHandle` on the Dart side). UUIDs are kept on DTOs for navigation/display only.

- CoreBluetooth has no native equivalent of `BluetoothGattCharacteristic.getInstanceId()`; we mint our own. `CBCharacteristic` and `CBDescriptor` only expose UUIDs, which is insufficient for duplicate-UUID peripherals.
- Per-device monotonic counter; characteristics and descriptors share the pool. The counter starts at 1 and increments on every minted handle. Handles are minted at `peripheral(_:didDiscoverCharacteristicsFor:)` (one per characteristic) and `peripheral(_:didDiscoverDescriptorsFor:)` (one per descriptor).
- The handle table is cleared on `centralManager(_:didDisconnectPeripheral:error:)` and `peripheral(_:didModifyServices:)` (the iOS Service Changed equivalent — fired before the system invalidates the affected services).
- **Server side**: `PeripheralManagerImpl.swift` mints handles in `addService` via a separate module-wide counter (only one local server per process). Cleared on `removeService`. A full clear on `peripheralManagerDidUpdateState(.poweredOff)` is its own backlog item — see I083.
- Stale-handle lookup (handle non-null in the call but absent from the table) returns Pigeon error `gatt-handle-invalidated`, which the Dart side translates to `AttributeHandleInvalidatedException`. Callers must re-discover services to obtain fresh handles.
