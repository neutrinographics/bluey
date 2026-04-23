# Android Implementation Comparison

## Overview

This document compares the Android implementations of `bluey_android` (new library) against `bluetooth_low_energy_android` (reference library) to identify feature parity, improvements, regressions, and bugs.

### Architecture Comparison

| Aspect | bluetooth_low_energy_android | bluey_android |
|--------|------------------------------|---------------|
| **Code Generation** | Pigeon (manual API files) | Pigeon (auto-generated) |
| **Async Pattern** | Kotlin Coroutines | Callback-based with Handler |
| **Component Structure** | Monolithic managers | Domain-separated components |
| **GATT Object Tracking** | Hash code based (instanceId) | UUID string based |
| **Listener Pattern** | Add/Remove listener methods | Direct Flutter API calls |
| **State Management** | Lazy-initialized impl with listeners | Direct manager references |

---

## Feature Parity (18 features)

These features exist in both libraries with equivalent functionality:

| Feature | Status | Notes |
|---------|--------|-------|
| Bluetooth state monitoring | Parity | Both use BroadcastReceiver for ACTION_STATE_CHANGED |
| Permission request (Android 12+) | Parity | Both request BLUETOOTH_SCAN, BLUETOOTH_CONNECT, BLUETOOTH_ADVERTISE |
| Permission request (pre-Android 12) | Parity | Both request ACCESS_FINE_LOCATION |
| Start/Stop scanning | Parity | Both use ScanCallback with ScanFilter support |
| Service UUID filtering | Parity | Both support filtering scans by service UUIDs |
| Connect to peripheral | Parity | Both use connectGatt with TRANSPORT_LE |
| Disconnect from peripheral | Parity | Both call gatt.disconnect() |
| Discover services | Parity | Both use discoverServices() with callback |
| Read characteristic | Parity | Both support characteristic reads |
| Write characteristic (with/without response) | Parity | Both support WRITE_TYPE_DEFAULT and WRITE_TYPE_NO_RESPONSE |
| Enable/disable notifications | Parity | Both write to CCCD (UUID 2902) |
| Read/Write descriptors | Parity | Both support descriptor operations |
| Request MTU | Parity | Both use requestMtu() with callback |
| Read RSSI | Parity | Both use readRemoteRssi() with callback |
| GATT Server creation | Parity | Both use openGattServer() |
| Add/Remove services | Parity | Both support dynamic service management |
| Start/Stop advertising | Parity | Both use BluetoothLeAdvertiser |
| Send notifications/indications | Parity | Both use notifyCharacteristicChanged() |

---

## Improvements in bluey_android (6 features)

### 1. Clean Architecture / Domain Separation
**Reference**: Single `MyCentralManager` class handles everything
**Bluey**: Separate `Scanner`, `ConnectionManager`, `GattServer`, `Advertiser` classes

**Benefit**: Better maintainability, testability, and adherence to Single Responsibility Principle.

### 2. Automatic CCCD Management for Server
**Reference**: Manually tracks CCCD writes and maps them to characteristic IDs
**Bluey**: Automatically adds CCCD to characteristics with notify/indicate properties

```kotlin
// bluey GattServer.kt:412-418
if (dto.properties.canNotify || dto.properties.canIndicate) {
    val cccd = BluetoothGattDescriptor(
        CCCD_UUID,
        BluetoothGattDescriptor.PERMISSION_READ or BluetoothGattDescriptor.PERMISSION_WRITE
    )
    characteristic.addDescriptor(cccd)
}
```

**Benefit**: Reduces boilerplate and prevents missing CCCD descriptors.

### 3. Subscription Tracking for Server Notifications
**Reference**: Must track subscriptions on Dart side
**Bluey**: Native tracking of which centrals are subscribed to which characteristics

```kotlin
// bluey GattServer.kt:35
private val subscriptions = mutableMapOf<String, MutableSet<String>>()
```

**Benefit**: Server can efficiently notify only subscribed centrals.

### 4. Connection Timeout Support
**Reference**: No built-in connection timeout
**Bluey**: Configurable connection timeout with automatic cleanup

```kotlin
// bluey ConnectionManager.kt:93-108
config.timeoutMs?.let { timeout ->
    handler.postDelayed({
        val pendingCallback = pendingConnections.remove(deviceId)
        if (pendingCallback != null) {
            // Cleanup and fail with timeout error
        }
    }, timeout)
}
```

**Benefit**: Prevents indefinite connection attempts on unresponsive devices.

### 5. Activity Lifecycle Cleanup
**Reference**: Manual cleanup required
**Bluey**: Automatic BLE resource cleanup when activity is destroyed

```kotlin
// bluey BlueyPlugin.kt:100-115
activityLifecycleCallbacks = object : Application.ActivityLifecycleCallbacks {
    override fun onActivityDestroyed(activity: Activity) {
        if (cleanupOnActivityDestroy) {
            advertiser?.cleanup()
            gattServer?.cleanup()
        }
    }
}
```

**Benefit**: Prevents zombie BLE connections when app is closed.

### 6. Short UUID Normalization
**Reference**: Expects full 128-bit UUIDs
**Bluey**: Automatically expands 4-character short UUIDs

```kotlin
// bluey ConnectionManager.kt:589-595
private fun normalizeUuid(uuid: String): String {
    return if (uuid.length == 4) {
        "0000$uuid-0000-1000-8000-00805f9b34fb"
    } else {
        uuid
    }
}
```

**Benefit**: More convenient API for standard Bluetooth SIG UUIDs.

---

## Regressions in bluey_android (4 features)

### 1. Missing Coroutine-based Async Pattern
**Reference**: Uses Kotlin Coroutines for clean async/await semantics
**Bluey**: Uses callback-based pattern

**Impact**: Less idiomatic Kotlin code, harder to compose operations.

### 2. Missing Listener Add/Remove Pattern
**Reference**: Explicit add/remove listener methods allow fine-grained control
**Bluey**: Always sends events to Flutter

**Impact**: Cannot optimize by disabling unused event streams.

### 3. Missing Connection Priority Request
**Reference**: Supports `requestConnectionPriority()` for connection interval tuning
**Bluey**: Not implemented

```kotlin
// Reference CentralManagerImpl.kt:170-173
override fun requestConnectionPriority(address: String, priority: ConnectionPriorityApi) {
    val peripheralImpl = retrievePeripheralImpl(address)
    impl.requestConnectionPriority(peripheralImpl, priority.impl)
}
```

**Impact**: Cannot optimize power consumption vs throughput.

### 4. Missing Maximum Write Length Query
**Reference**: Can query `getMaximumWriteLength()` for optimal chunk sizes
**Bluey**: Not implemented

**Impact**: Must guess or hardcode write chunk sizes.

---

## Bugs Identified (9 total)

### Critical (2)

#### BUG-A1: UUID-Based GATT Object Lookup Causes Collision
**Location**: `ConnectionManager.kt:559-570`
**Severity**: Critical

**Problem**: Characteristics and descriptors are looked up by UUID string alone, ignoring the service context. If multiple services have characteristics with the same UUID, only the first one found will be returned.

```kotlin
private fun findCharacteristic(gatt: BluetoothGatt, uuid: String): BluetoothGattCharacteristic? {
    val normalizedUuid = normalizeUuid(uuid)
    for (service in gatt.services ?: emptyList()) {
        for (characteristic in service.characteristics ?: emptyList()) {
            if (characteristic.uuid.toString().equals(normalizedUuid, ignoreCase = true)) {
                return characteristic  // Returns first match only!
            }
        }
    }
    return null
}
```

**Reference Approach**: Uses `instanceId` (hash code) which is unique per GATT object instance:
```kotlin
// Reference uses characteristic.hashCode.args as unique identifier
val hashCodeArgs = characteristic.hashCode.args
```

**Proposed Solution**: Include service UUID in the lookup key, or use instance IDs:
```kotlin
private fun findCharacteristic(gatt: BluetoothGatt, serviceUuid: String, charUuid: String): BluetoothGattCharacteristic?
```

---

#### BUG-A2: Descriptor UUID Collision (Same as Characteristics)
**Location**: `ConnectionManager.kt:572-583`
**Severity**: Critical

**Problem**: Same issue as BUG-A1 but for descriptors. The CCCD descriptor (UUID 2902) exists on every notifiable characteristic, but only the first one is ever returned.

```kotlin
private fun findDescriptor(gatt: BluetoothGatt, uuid: String): BluetoothGattDescriptor? {
    val normalizedUuid = normalizeUuid(uuid)
    for (service in gatt.services ?: emptyList()) {
        for (characteristic in service.characteristics ?: emptyList()) {
            for (descriptor in characteristic.descriptors ?: emptyList()) {
                if (descriptor.uuid.toString().equals(normalizedUuid, ignoreCase = true)) {
                    return descriptor  // Returns first match only!
                }
            }
        }
    }
    return null
}
```

**Impact**: Reading/writing descriptors on the second+ characteristic with the same descriptor UUID will silently operate on the wrong descriptor.

**Proposed Solution**: Require characteristic context for descriptor operations:
```kotlin
fun readDescriptor(deviceId: String, characteristicUuid: String, descriptorUuid: String, callback: ...)
```

---

### High (3)

#### BUG-A3: Pending Callbacks Not Cleaned on Disconnect
**Location**: `ConnectionManager.kt:388-417`
**Severity**: High

**Problem**: When `onConnectionStateChange` reports `STATE_DISCONNECTED`, pending operation callbacks (reads, writes, descriptor ops) are not failed. They will leak or timeout.

```kotlin
BluetoothProfile.STATE_DISCONNECTED -> {
    notifyConnectionState(deviceId, ConnectionStateDto.DISCONNECTED)
    // Only handles pendingConnections callback
    val pendingCallback = pendingConnections.remove(deviceId)
    // ...
    // Missing: pendingReads, pendingWrites, pendingDescriptorReads, 
    //          pendingDescriptorWrites, pendingServiceDiscovery, etc.
}
```

**Reference Approach**: Properly fails all pending callbacks on disconnect:
```kotlin
// Reference MyCentralManager.kt:267-301
if (newState == BluetoothProfile.STATE_DISCONNECTED) {
    // ... clean up all pending callbacks with error
    val readCharacteristicCallbacks = mReadCharacteristicCallbacks.remove(addressArgs)
    if (readCharacteristicCallbacks != null) {
        for (callback in readCharacteristicCallbacks.values) {
            callback(Result.failure(error))
        }
    }
    // Same for writes, descriptors, etc.
}
```

**Proposed Solution**: Add comprehensive callback cleanup:
```kotlin
BluetoothProfile.STATE_DISCONNECTED -> {
    // Fail all pending operations
    val error = IllegalStateException("Device disconnected")
    pendingServiceDiscovery.remove(deviceId)?.invoke(Result.failure(error))
    pendingReads.keys.filter { it.startsWith("$deviceId:") }.forEach { 
        pendingReads.remove(it)?.invoke(Result.failure(error))
    }
    // ... repeat for all pending maps
}
```

---

#### BUG-A4: Server Read/Write Response Methods Are No-Op
**Location**: `GattServer.kt:116-132`
**Severity**: High

**Problem**: `respondToReadRequest` and `respondToWriteRequest` don't actually send responses to the central. The methods just return success without doing anything.

```kotlin
fun respondToReadRequest(
    requestId: Long,
    status: GattStatusDto,
    value: ByteArray?,
    callback: (Result<Unit>) -> Unit
) {
    val server = gattServer
    if (server == null) {
        callback(Result.failure(IllegalStateException("GATT server not running")))
        return
    }
    // NOTE: This does nothing! No sendResponse call.
    callback(Result.success(Unit))
}
```

Meanwhile, auto-responses are sent in the callbacks:
```kotlin
// GattServer.kt:268-277 - Auto-responds in callback
try {
    gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, 
        characteristic.value ?: ByteArray(0))
} catch (e: SecurityException) {}
```

**Impact**: The Dart-side response mechanism is completely broken. Developers cannot customize responses.

**Reference Approach**: Properly tracks pending requests and maps device to request:
```kotlin
// Reference PeripheralManagerImpl.kt:264-269
override fun respondReadRequestWithValue(id: Long, value: ByteArray) {
    val requestId = id.toInt()
    for ((_, device) in devices) {
        gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, value)
        break
    }
}
```

**Proposed Solution**: Track pending requests with device reference:
```kotlin
private data class PendingRequest(val device: BluetoothDevice, val requestId: Int, val offset: Int)
private val pendingReadRequests = mutableMapOf<Long, PendingRequest>()

fun respondToReadRequest(requestId: Long, status: GattStatusDto, value: ByteArray?, callback: ...) {
    val pending = pendingReadRequests.remove(requestId)
    if (pending != null) {
        gattServer?.sendResponse(pending.device, pending.requestId, status.toGattStatus(), 
            pending.offset, value)
    }
    callback(Result.success(Unit))
}
```

---

#### BUG-A5: Notification Callback Collision
**Location**: `GattServer.kt:93-112`
**Severity**: High

**Problem**: When notifying multiple centrals, only one callback is tracked. If notifications are sent to multiple devices rapidly, only the last one gets the completion callback.

```kotlin
fun notifyCharacteristic(characteristicUuid: String, value: ByteArray, callback: (Result<Unit>) -> Unit) {
    // ...
    for (centralId in subscribedCentralIds) {
        val device = connectedCentrals[centralId] ?: continue
        sendNotification(server, device, characteristic, value)
    }
    callback(Result.success(Unit))  // Called immediately, not waiting for onNotificationSent
}
```

The individual notification send has no callback tracking:
```kotlin
private fun sendNotification(...) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        server.notifyCharacteristicChanged(device, characteristic, false, value)
    } else {
        // ...
    }
    // No tracking of which device/notification this was
}
```

**Impact**: Cannot reliably confirm notification delivery to all centrals.

**Proposed Solution**: Track per-device notification callbacks:
```kotlin
private val pendingNotifications = mutableMapOf<String, (Result<Unit>) -> Unit>()

// In onNotificationSent callback
override fun onNotificationSent(device: BluetoothDevice, status: Int) {
    val callback = pendingNotifications.remove(device.address)
    callback?.invoke(if (status == GATT_SUCCESS) Result.success(Unit) else Result.failure(...))
}
```

---

### Medium (3)

#### BUG-A6: Connection Timeout Not Cancelled on Success
**Location**: `ConnectionManager.kt:93-108`
**Severity**: Medium

**Problem**: When a connection succeeds before the timeout, the timeout handler is not cancelled. It will still fire and try to clean up an already-connected device.

```kotlin
config.timeoutMs?.let { timeout ->
    handler.postDelayed({
        val pendingCallback = pendingConnections.remove(deviceId)
        if (pendingCallback != null) {
            // Tries to disconnect and close even if already connected
            val currentGatt = connections.remove(deviceId)
            // ...
        }
    }, timeout)
}
```

The successful connection callback in `onConnectionStateChange` doesn't cancel this:
```kotlin
BluetoothProfile.STATE_CONNECTED -> {
    val pendingCallback = pendingConnections.remove(deviceId)
    // Timeout handler still scheduled!
}
```

**Proposed Solution**: Track and cancel timeout runnables:
```kotlin
private val connectionTimeouts = mutableMapOf<String, Runnable>()

// In connect():
val timeoutRunnable = Runnable { /* timeout logic */ }
connectionTimeouts[deviceId] = timeoutRunnable
handler.postDelayed(timeoutRunnable, timeout)

// In onConnectionStateChange STATE_CONNECTED:
connectionTimeouts.remove(deviceId)?.let { handler.removeCallbacks(it) }
```

---

#### BUG-A7: Scan Timeout Fires After Manual Stop
**Location**: `Scanner.kt:78-83`
**Severity**: Medium

**Problem**: If scan is stopped manually via `stopScan()` before the timeout, the timeout runnable still fires and calls `onScanComplete` again.

```kotlin
fun stopScan(callback: (Result<Unit>) -> Unit) {
    stopScanInternal()
    flutterApi.onScanComplete {}  // Called here
    callback(Result.success(Unit))
}

private fun stopScanInternal() {
    scanTimeoutRunnable?.let { handler.removeCallbacks(it) }
    // ...
}
```

Actually this is handled correctly with `removeCallbacks`, but the comment in stopScan shows potential double-emit:
```kotlin
// onScanFailed also calls flutterApi.onScanComplete
override fun onScanFailed(errorCode: Int) {
    handler.post {
        flutterApi.onScanComplete {}
    }
}
```

**Impact**: Minor - may result in duplicate `onScanComplete` events.

---

#### BUG-A8: GATT Server Not Closed on Engine Detach
**Location**: `BlueyPlugin.kt:73-84`
**Severity**: Medium

**Problem**: `onDetachedFromEngine` calls `gattServer?.cleanup()`, but if the Activity was already detached and `cleanupOnActivityDestroy` is false, the GATT server may remain open.

```kotlin
override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    // ...
    gattServer?.cleanup()  // May already be null if activity cleanup ran
}
```

**Impact**: Potential resource leak if cleanup order is unexpected.

---

### Low (1)

#### BUG-A9: Manufacturer Data Only Returns First Entry
**Location**: `Scanner.kt:117-124`
**Severity**: Low

**Problem**: If a scan result contains multiple manufacturer-specific data entries, only the first one is returned.

```kotlin
scanRecord?.manufacturerSpecificData?.let { sparseArray ->
    if (sparseArray.size() > 0) {
        val key = sparseArray.keyAt(0)  // Only first entry
        val data = sparseArray.get(key)
        manufacturerDataCompanyId = key.toLong()
        manufacturerData = data?.map { it.toLong() }
    }
}
```

**Reference Approach**: Also only handles single manufacturer data, but the API design allows for it.

**Proposed Solution**: Return all manufacturer data entries:
```kotlin
val allManufacturerData = mutableListOf<ManufacturerDataDto>()
for (i in 0 until sparseArray.size()) {
    val companyId = sparseArray.keyAt(i)
    val data = sparseArray.valueAt(i)
    allManufacturerData.add(ManufacturerDataDto(companyId, data))
}
```

---

## Summary

| Category | Count |
|----------|-------|
| Features at Parity | 18 |
| Improvements | 6 |
| Regressions | 4 |
| Critical Bugs | 2 |
| High Severity Bugs | 3 |
| Medium Severity Bugs | 3 |
| Low Severity Bugs | 1 |

### Critical Issues Requiring Immediate Attention

1. **BUG-A1 & BUG-A2**: UUID-based GATT object lookup will cause silent failures when multiple services have characteristics/descriptors with the same UUID. This is especially problematic for CCCD (2902) which exists on every notifiable characteristic.

2. **BUG-A4**: Server read/write response methods are completely non-functional, making custom GATT server responses impossible.

### Recommendations

1. **Adopt hash-code/instance-ID based GATT tracking** from the reference implementation to fix BUG-A1 and BUG-A2.

2. **Implement proper pending request tracking** for server responses to fix BUG-A4.

3. **Add comprehensive disconnect cleanup** to fail all pending callbacks (BUG-A3).

4. **Consider adding coroutine support** for more idiomatic Kotlin and better async composition.

5. **Implement connection priority** and **maximum write length** APIs for feature completeness.
