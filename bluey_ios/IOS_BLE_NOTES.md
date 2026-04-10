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

**Our approach:** When `disconnectCentral` is called, we remove the client from our internal tracking and subscription lists, but the underlying BLE connection may persist until the client disconnects or the link times out.

## Permissions

### Bluetooth Usage Descriptions

iOS requires usage description strings in `Info.plist`:
- `NSBluetoothAlwaysUsageDescription` — required for all Bluetooth usage (iOS 13+)
- `NSBluetoothPeripheralUsageDescription` — required for peripheral role (iOS 6-12, deprecated but still needed for backwards compatibility)

### No Runtime Permission Request for Bluetooth

Unlike Android, iOS does not have a runtime permission prompt specifically for Bluetooth scanning or connecting. The system prompts the user for Bluetooth access the first time `CBCentralManager` or `CBPeripheralManager` is initialized. If denied, the manager reports state `.unauthorized`.

## Central Role (Scanner/Client)

### cancelPeripheralConnection May Not Terminate the BLE Link

Calling `CBCentralManager.cancelPeripheralConnection()` cleans up CoreBluetooth's local state and fires `didDisconnectPeripheral` immediately, but it does **not** reliably send a BLE link termination (LL_TERMINATE_IND) to the remote device.

**Observed behavior:** When an iOS app disconnects from an Android peripheral:
- iOS reports the disconnect immediately (local cleanup succeeds)
- Android's GATT server never receives `onConnectionStateChange` with `STATE_DISCONNECTED`
- The Android side shows the client as still connected indefinitely
- Only toggling Bluetooth off on iOS (which forces the radio down) causes Android to detect the link loss via supervision timeout

**Implication:** The remote device may hold a stale connection entry until its supervision timeout fires (10-30 seconds), or indefinitely if the timeout doesn't trigger. There is no workaround on the iOS side — `cancelPeripheralConnection` is the only API available.

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
8. **cancelPeripheralConnection unreliable** — Local cleanup succeeds but the remote device may never receive the disconnect.
9. **BLE address rotation** — iOS uses random addresses per connection, causing stale client entries on remote servers.
