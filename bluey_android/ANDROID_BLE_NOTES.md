# Android BLE Implementation Notes

This document captures Android BLE quirks, limitations, and corner cases discovered during development. It serves as operational knowledge for anyone maintaining or extending the Android implementation.

## App Lifecycle and Cleanup

### Force-Kill Behavior

When an Android app is force-killed (swipe away from recents, `kill` command, or Ctrl+C on `flutter run`), **no lifecycle callbacks are invoked**. The process terminates immediately.

This means:
- `onActivityDestroyed` is NOT called
- `onDetachedFromActivity` is NOT called
- Any cleanup code in these callbacks will not run

**Implication:** There is no reliable way to clean up BLE resources when the app is force-killed. The BLE connections may persist at the OS/Bluetooth stack level until they timeout (typically 20-30 seconds) or the remote device disconnects.

**Our approach:** We clean up on normal app close via `ActivityLifecycleCallbacks.onActivityDestroyed` and `onDetachedFromActivity`. For force-kills, we accept that connections may briefly persist and rely on the remote device eventually timing out.

### Activity Lifecycle Callbacks

We register `Application.ActivityLifecycleCallbacks` for more reliable cleanup detection. This is called even in some cases where Flutter's `onDetachedFromActivity` might not be.

```kotlin
application.registerActivityLifecycleCallbacks(object : Application.ActivityLifecycleCallbacks {
    override fun onActivityDestroyed(activity: Activity) {
        // Clean up BLE resources here
    }
    // ... other callbacks
})
```

## GATT Server

### Opening the GATT Server

`BluetoothManager.openGattServer()` can sometimes return `null` on the first attempt, especially right after Bluetooth is enabled. A retry with a short delay often succeeds.

```kotlin
var server = bluetoothManager?.openGattServer(context, callback)
if (server == null) {
    Thread.sleep(100)
    server = bluetoothManager?.openGattServer(context, callback)
}
```

### cancelConnection Limitations

`BluetoothGattServer.cancelConnection(device)` only works for connections that the GATT server initiated. It does **not** reliably disconnect connections initiated by a remote central (e.g., iOS connecting to us).

When a remote device (iOS) connects to our GATT server:
- The connection is initiated by iOS, not Android
- `cancelConnection` may not trigger a disconnection
- The `onConnectionStateChange` callback with `STATE_DISCONNECTED` may never fire

**Implication:** We cannot forcibly disconnect iOS devices that connect to us. We can only close the GATT server, which will eventually cause the connection to timeout on the iOS side.

### Callback Threading

GATT server callbacks (`onConnectionStateChange`, `onCharacteristicReadRequest`, etc.) are called on a Binder thread, not the main thread. Flutter platform channels require main thread access.

Always dispatch to the main thread before calling Flutter APIs:

```kotlin
handler.post {
    flutterApi.onCentralConnected(central) {}
}
```

## iOS Interoperability

### iOS Connection Caching

iOS aggressively caches BLE connections. When an iOS device connects to an Android peripheral:

1. iOS remembers the connection
2. If the Android app closes and reopens, iOS may still think it's connected
3. When Android opens a new GATT server, iOS's cached connection immediately "reconnects"

This manifests as:
- `onConnectionStateChange` with `STATE_CONNECTED` fires immediately when opening the GATT server
- The connection appears before we even start advertising

**Our approach:** We report all connections to Flutter immediately, regardless of whether advertising has started. This allows the app to handle these "inherited" connections rather than leaving them in a broken state.

### Connection Persistence After Server Close

When Android calls `gattServer.close()`:
- The Android side cleans up its resources
- iOS may still think it's connected for 20-30 seconds
- iOS will eventually timeout and show as disconnected

There's no way to force iOS to disconnect immediately from the Android side.

## Permissions

### Android 12+ (API 31+)

Requires new Bluetooth permissions:
- `BLUETOOTH_SCAN` - for scanning
- `BLUETOOTH_CONNECT` - for connecting and GATT operations
- `BLUETOOTH_ADVERTISE` - for advertising as a peripheral

### Android 11 and below

Uses legacy permissions:
- `BLUETOOTH`
- `BLUETOOTH_ADMIN`
- `ACCESS_FINE_LOCATION` - required for scanning

## Service Addition

### Asynchronous Service Addition

`BluetoothGattServer.addService()` is asynchronous. The method returns `true` if the request was initiated, but the service isn't actually added until `onServiceAdded` callback fires.

```kotlin
pendingServiceCallback = callback
if (!server.addService(gattService)) {
    // Failed to initiate
    pendingServiceCallback = null
    callback(Result.failure(...))
}
// Wait for onServiceAdded callback
```

## Advertising

### Advertising Modes

Android supports different advertising modes with tradeoffs:
- `ADVERTISE_MODE_LOW_POWER` - 1000ms interval, best battery
- `ADVERTISE_MODE_BALANCED` - 250ms interval
- `ADVERTISE_MODE_LOW_LATENCY` - 100ms interval, fastest discovery but highest power

### Connectable Advertising

For a GATT server, advertising must be connectable:
```kotlin
AdvertiseSettings.Builder()
    .setConnectable(true)
    .build()
```

## Known Limitations

1. **No reliable force-kill cleanup** - BLE resources may leak briefly when app is force-killed
2. **Cannot force-disconnect remote centrals** - `cancelConnection` doesn't work for inbound connections
3. **iOS connection caching** - Connections may persist across app restarts
4. **GATT server open may fail** - Retry logic needed
5. **MTU negotiation** - iOS typically requests MTU of 517, but the actual MTU depends on both devices
