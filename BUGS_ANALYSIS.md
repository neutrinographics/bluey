# Bluey Implementation: Logical Bugs Analysis

This document provides a comprehensive analysis of logical bugs identified in the Bluey BLE library implementation, comparing it against the reference `bluetooth_low_energy` library and BLE best practices.

**Analysis Date:** January 2026  
**Analyzed Version:** Branch `7.0.0-da1nerd`

---

## Table of Contents

1. [Critical Bugs](#critical-bugs)
2. [High Severity Bugs](#high-severity-bugs)
3. [Medium Severity Bugs](#medium-severity-bugs)
4. [Low Severity Issues](#low-severity-issues)
5. [Summary](#summary)

---

## Critical Bugs

### 1. Race Condition in Connection State Initialization

**Location:** `bluey/lib/src/bluey_connection.dart:20-24`

**Code:**
```dart
ConnectionState _state = ConnectionState.connected; // Start as connected since we're created after successful connection
```

**Justification:**

The `BlueyConnection` constructor initializes `_state` as `connected` immediately, based on the assumption that the connection is already established when the object is created. However, several issues arise:

1. The platform state subscription is set up asynchronously in the constructor
2. The platform may emit state changes before the subscription is active
3. There's no synchronization between the assumed initial state and actual platform state
4. If the connection drops immediately after creation (common in BLE), the state may remain incorrectly as `connected`

The reference library (`bluetooth_low_energy`) queries the actual connection state from the platform rather than assuming it.

**Impact:**
- Callers may attempt GATT operations on a connection that isn't actually connected
- State listeners may miss the initial connected event or receive inconsistent state
- Potential for `IllegalStateException` on the native side when operations are attempted on a disconnected GATT

**Proposed Solution:**

```dart
class BlueyConnection implements Connection {
  // Start as unknown/connecting, not connected
  ConnectionState _state = ConnectionState.connecting;
  
  // Add a completer to track when initialization is complete
  final Completer<void> _initialized = Completer<void>();
  
  BlueyConnection({
    required platform.BlueyPlatform platformInstance,
    required String connectionId,
    required this.deviceId,
  }) : _platform = platformInstance,
       _deviceAddress = connectionId {
    _initialize();
  }
  
  Future<void> _initialize() async {
    // Subscribe to state changes FIRST
    _platformStateSubscription = _platform
        .connectionStateStream(_deviceAddress)
        .listen((platformState) {
          _state = _mapConnectionState(platformState);
          _stateController.add(_state);
        });
    
    // Then query the actual current state from platform
    try {
      final currentState = await _platform.getConnectionState(_deviceAddress);
      _state = _mapConnectionState(currentState);
      _stateController.add(_state);
    } catch (e) {
      // If we can't get state, assume disconnected
      _state = ConnectionState.disconnected;
      _stateController.add(_state);
    }
    
    _initialized.complete();
  }
  
  /// Wait for initialization before performing operations
  Future<void> ensureInitialized() => _initialized.future;
}
```

Additionally, update `Bluey.connect()` to await initialization:

```dart
Future<Connection> connect(Device device, {Duration? timeout}) async {
  // ... existing connection code ...
  
  final connection = BlueyConnection(
    platformInstance: _platform,
    connectionId: connectionId,
    deviceId: device.id,
  );
  
  await connection.ensureInitialized();
  
  // Verify we're actually connected
  if (connection.state != ConnectionState.connected) {
    throw ConnectionException(device.id, ConnectionFailureReason.unknown);
  }
  
  return connection;
}
```

---

### 2. Notification Subscription Race Condition

**Location:** `bluey/lib/src/bluey_connection.dart:321-345`

**Code:**
```dart
void _onFirstListen() {
  // Enable notifications on the platform
  _platform.setNotification(_deviceAddress, uuid.toString(), true);  // NOT AWAITED

  // Subscribe to platform notifications
  _notificationSubscription = _platform
      .notificationStream(_deviceAddress)
      .where((n) => n.characteristicUuid.toLowerCase() == uuid.toString().toLowerCase())
      .listen(
        (notification) {
          _notificationController?.add(notification.value);
        },
        onError: (error) {
          _notificationController?.addError(error);
        },
      );
}
```

**Justification:**

The `_onFirstListen` callback is triggered synchronously when the first listener subscribes to the `notifications` stream. However:

1. `_platform.setNotification()` is an async operation that writes to the CCCD (Client Characteristic Configuration Descriptor) on the remote device
2. The call is fire-and-forget (not awaited)
3. The subscription to `notificationStream` starts immediately, before notifications are actually enabled
4. If the BLE device has cached data or sends a notification very quickly after CCCD write, it could be missed

The BLE specification states that notifications are only sent after the CCCD write is acknowledged by the GATT server. In practice, some devices start sending immediately after receiving the write, before the acknowledgment reaches the client.

**Impact:**
- First notification(s) may be lost
- No error handling if enabling notifications fails
- Users experience intermittent data loss that's difficult to debug

**Proposed Solution:**

Change the notification stream to use a lazy-start pattern:

```dart
class BlueyRemoteCharacteristic implements RemoteCharacteristic {
  final platform.BlueyPlatform _platform;
  final String _deviceAddress;
  
  StreamSubscription? _notificationSubscription;
  StreamController<Uint8List>? _notificationController;
  bool _notificationsEnabled = false;
  final _enablingLock = Lock();  // Use a mutex to prevent concurrent enable/disable

  @override
  Stream<Uint8List> get notifications {
    if (!properties.canSubscribe) {
      throw const OperationNotSupportedException('notify');
    }

    _notificationController ??= StreamController<Uint8List>.broadcast(
      onListen: _onFirstListen,
      onCancel: _onLastCancel,
    );

    return _notificationController!.stream;
  }

  void _onFirstListen() {
    // Start the async enable process
    _enableNotifications();
  }
  
  Future<void> _enableNotifications() async {
    await _enablingLock.synchronized(() async {
      if (_notificationsEnabled) return;
      
      // Subscribe to stream FIRST to avoid missing notifications
      _notificationSubscription = _platform
          .notificationStream(_deviceAddress)
          .where((n) => n.characteristicUuid.toLowerCase() == uuid.toString().toLowerCase())
          .listen(
            (notification) {
              _notificationController?.add(notification.value);
            },
            onError: (error) {
              _notificationController?.addError(error);
            },
          );
      
      // THEN enable notifications on the platform
      try {
        await _platform.setNotification(_deviceAddress, uuid.toString(), true);
        _notificationsEnabled = true;
      } catch (e) {
        // Clean up subscription on failure
        await _notificationSubscription?.cancel();
        _notificationSubscription = null;
        _notificationController?.addError(e);
      }
    });
  }

  void _onLastCancel() {
    _disableNotifications();
  }
  
  Future<void> _disableNotifications() async {
    await _enablingLock.synchronized(() async {
      if (!_notificationsEnabled) return;
      
      try {
        await _platform.setNotification(_deviceAddress, uuid.toString(), false);
      } catch (e) {
        // Log but don't throw - we're cleaning up
      }
      
      await _notificationSubscription?.cancel();
      _notificationSubscription = null;
      _notificationsEnabled = false;
    });
  }
}
```

---

### 3. Disconnect State Machine Double-Emission

**Location:** `bluey/lib/src/bluey_connection.dart:136-152`

**Code:**
```dart
Future<void> disconnect() async {
  // Idempotent: if already disconnected or disconnecting, do nothing
  if (_state == ConnectionState.disconnected ||
      _state == ConnectionState.disconnecting) {
    return;
  }

  _state = ConnectionState.disconnecting;
  _stateController.add(_state);

  await _platform.disconnect(_deviceAddress);

  _state = ConnectionState.disconnected;
  _stateController.add(_state);  // EMITS disconnected

  await _cleanup();
}
```

Combined with the constructor subscription:

```dart
_platformStateSubscription = _platform
    .connectionStateStream(_deviceAddress)
    .listen(
      (platformState) {
        _state = _mapConnectionState(platformState);
        _stateController.add(_state);  // ALSO EMITS disconnected
      },
      ...
    );
```

**Justification:**

When `disconnect()` is called:

1. The method manually sets `_state = ConnectionState.disconnected` and emits it
2. The platform disconnect triggers a callback that also emits `disconnected`
3. This results in the `stateChanges` stream receiving `disconnected` twice

This is a violation of the state machine pattern where each state transition should emit exactly once. The reference library uses either:
- Platform-driven state only (wait for callback), or
- Manual state with callback cancellation

**Impact:**
- Listeners receive duplicate `disconnected` events
- UI code may trigger cleanup/navigation twice
- State transition logic may fail if it expects idempotent transitions

**Proposed Solution:**

Use the platform as the source of truth and don't manually emit states:

```dart
Future<void> disconnect() async {
  // Idempotent: if already disconnected or disconnecting, do nothing
  if (_state == ConnectionState.disconnected ||
      _state == ConnectionState.disconnecting) {
    return;
  }

  // Update local state but DON'T emit - let the platform callback do it
  _state = ConnectionState.disconnecting;
  
  // The platform will emit the state change via the subscription
  await _platform.disconnect(_deviceAddress);
  
  // Wait for the disconnected state from the platform
  await stateChanges.firstWhere((s) => s == ConnectionState.disconnected)
      .timeout(const Duration(seconds: 5), onTimeout: () {
        // Force disconnected if platform doesn't respond
        _state = ConnectionState.disconnected;
        _stateController.add(_state);
        return ConnectionState.disconnected;
      });

  await _cleanup();
}
```

Or alternatively, cancel the subscription before manual emission:

```dart
Future<void> disconnect() async {
  if (_state == ConnectionState.disconnected ||
      _state == ConnectionState.disconnecting) {
    return;
  }

  // Cancel subscription to prevent duplicate emissions
  await _platformStateSubscription?.cancel();
  _platformStateSubscription = null;

  _state = ConnectionState.disconnecting;
  _stateController.add(_state);

  await _platform.disconnect(_deviceAddress);

  _state = ConnectionState.disconnected;
  _stateController.add(_state);

  await _cleanup();
}
```

---

### 4. GATT Operations Not Gated by Connection State

**Location:** `bluey/lib/src/bluey_connection.dart:109-118`

**Code:**
```dart
@override
Future<List<RemoteService>> get services async {
  if (_cachedServices != null) {
    return _cachedServices!;
  }

  final platformServices = await _platform.discoverServices(_deviceAddress);
  _cachedServices = platformServices.map((ps) => _mapService(ps)).toList();
  return _cachedServices!;
}
```

Also in `BlueyRemoteCharacteristic.read()`:

```dart
@override
Future<Uint8List> read() async {
  if (!properties.canRead) {
    throw const OperationNotSupportedException('read');
  }
  return await _platform.readCharacteristic(_deviceAddress, uuid.toString());
}
```

**Justification:**

None of the GATT operations check whether the connection is still active before making platform calls. This leads to:

1. Platform exceptions being thrown instead of domain-specific `DisconnectedException`
2. Inconsistent error handling for callers
3. Potential crashes if the platform layer doesn't handle disconnected operations gracefully

The reference library checks connection state before every GATT operation and throws appropriate domain exceptions.

**Impact:**
- Users receive `IllegalStateException` or `PlatformException` instead of `DisconnectedException`
- Error handling becomes inconsistent across the API
- Difficult to write robust reconnection logic

**Proposed Solution:**

Add a connection check helper and use it in all operations:

```dart
class BlueyConnection implements Connection {
  // ... existing code ...
  
  /// Throws [DisconnectedException] if not connected.
  void _ensureConnected() {
    if (_state != ConnectionState.connected) {
      throw DisconnectedException(deviceId, DisconnectReason.unknown);
    }
  }
  
  @override
  Future<List<RemoteService>> get services async {
    _ensureConnected();
    
    if (_cachedServices != null) {
      return _cachedServices!;
    }

    try {
      final platformServices = await _platform.discoverServices(_deviceAddress);
      _cachedServices = platformServices.map((ps) => _mapService(ps)).toList();
      return _cachedServices!;
    } catch (e) {
      // Check if we disconnected during the operation
      if (_state != ConnectionState.connected) {
        throw DisconnectedException(deviceId, DisconnectReason.linkLoss);
      }
      rethrow;
    }
  }
  
  @override
  Future<int> requestMtu(int mtu) async {
    _ensureConnected();
    // ... rest of implementation
  }
  
  @override
  Future<int> readRssi() async {
    _ensureConnected();
    // ... rest of implementation
  }
}
```

Pass the connection reference to characteristics for state checking:

```dart
class BlueyRemoteCharacteristic implements RemoteCharacteristic {
  final BlueyConnection _connection;  // Add connection reference
  
  @override
  Future<Uint8List> read() async {
    _connection._ensureConnected();
    
    if (!properties.canRead) {
      throw const OperationNotSupportedException('read');
    }
    
    try {
      return await _platform.readCharacteristic(_deviceAddress, uuid.toString());
    } catch (e) {
      _connection._ensureConnected();  // Check again after failure
      rethrow;
    }
  }
}
```

---

## High Severity Bugs

### 5. Memory Leak in Notification Controllers

**Location:** `bluey/lib/src/bluey_connection.dart:302-347`

**Code:**
```dart
class BlueyRemoteCharacteristic implements RemoteCharacteristic {
  StreamSubscription? _notificationSubscription;
  StreamController<Uint8List>? _notificationController;
  
  // ... _notificationController is created but never closed
}
```

In `BlueyConnection._cleanup()`:

```dart
Future<void> _cleanup() async {
  await _platformStateSubscription?.cancel();
  await _platformBondStateSubscription?.cancel();
  await _platformPhySubscription?.cancel();
  await _stateController.close();
  await _bondStateController.close();
  await _phyController.close();
  _cachedServices = null;
  // NOTE: No cleanup of characteristic notification controllers!
}
```

**Justification:**

When a `BlueyConnection` is disposed:
1. The cached services (including characteristics) are set to `null`
2. But the `StreamController` instances inside each `BlueyRemoteCharacteristic` are never closed
3. Any active subscriptions to notifications are not cancelled
4. The garbage collector cannot collect these objects because the stream controllers hold references

This is a classic stream controller memory leak pattern in Dart.

**Impact:**
- Memory usage grows with each connection/disconnection cycle
- Active notification subscriptions may continue running in the background
- On long-running apps, this leads to OOM crashes

**Proposed Solution:**

Add cleanup methods to characteristics and call them from connection cleanup:

```dart
class BlueyRemoteCharacteristic implements RemoteCharacteristic {
  // ... existing code ...
  
  /// Clean up resources. Called when the connection is disposed.
  Future<void> dispose() async {
    await _notificationSubscription?.cancel();
    _notificationSubscription = null;
    
    await _notificationController?.close();
    _notificationController = null;
  }
}

class BlueyRemoteService implements RemoteService {
  final List<BlueyRemoteCharacteristic> _characteristics;
  
  Future<void> dispose() async {
    for (final char in _characteristics) {
      await char.dispose();
    }
  }
}

class BlueyConnection implements Connection {
  Future<void> _cleanup() async {
    // Clean up characteristics first
    if (_cachedServices != null) {
      for (final service in _cachedServices!) {
        await (service as BlueyRemoteService).dispose();
      }
    }
    
    await _platformStateSubscription?.cancel();
    await _platformBondStateSubscription?.cancel();
    await _platformPhySubscription?.cancel();
    await _stateController.close();
    await _bondStateController.close();
    await _phyController.close();
    _cachedServices = null;
  }
}
```

---

### 6. Android Pending Callback Collision

**Location:** `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/ConnectionManager.kt:171-182`

**Code:**
```kotlin
fun readCharacteristic(
    deviceId: String,
    characteristicUuid: String,
    callback: (Result<ByteArray>) -> Unit
) {
    // ...
    
    // Store callback for async response
    val key = "$deviceId:$characteristicUuid"
    pendingReads[key] = callback  // OVERWRITES any existing callback!

    try {
        if (!gatt.readCharacteristic(characteristic)) {
            pendingReads.remove(key)
            callback(Result.failure(IllegalStateException("Failed to read characteristic")))
        }
    } catch (e: SecurityException) {
        pendingReads.remove(key)
        callback(Result.failure(e))
    }
}
```

**Justification:**

The callback storage uses a simple map keyed by `deviceId:characteristicUuid`. If two reads are initiated before the first completes:

1. First read stores callback A at key "device:char"
2. Second read stores callback B at key "device:char", overwriting A
3. GATT callback fires for first read, invokes callback B
4. Callback A is never invoked - caller hangs forever

This is a fundamental issue in BLE libraries because Android's `BluetoothGatt` only supports one pending operation per characteristic at a time, but the library doesn't enforce this.

**Impact:**
- Callers can hang indefinitely waiting for a future that never completes
- Race conditions in multi-threaded apps
- Difficult to debug intermittent hangs

**Proposed Solution:**

Option A - Queue operations:

```kotlin
class ConnectionManager(...) {
    // Queue of pending operations per characteristic
    private val operationQueues = mutableMapOf<String, ArrayDeque<PendingOperation>>()
    private val operationLock = ReentrantLock()
    
    sealed class PendingOperation {
        data class Read(val callback: (Result<ByteArray>) -> Unit) : PendingOperation()
        data class Write(val value: ByteArray, val withResponse: Boolean, 
                        val callback: (Result<Unit>) -> Unit) : PendingOperation()
    }
    
    fun readCharacteristic(
        deviceId: String,
        characteristicUuid: String,
        callback: (Result<ByteArray>) -> Unit
    ) {
        val key = "$deviceId:$characteristicUuid"
        
        operationLock.withLock {
            val queue = operationQueues.getOrPut(key) { ArrayDeque() }
            val operation = PendingOperation.Read(callback)
            queue.addLast(operation)
            
            // If this is the only operation, execute it
            if (queue.size == 1) {
                executeNextOperation(deviceId, characteristicUuid, queue)
            }
            // Otherwise it will be executed when the current operation completes
        }
    }
    
    private fun executeNextOperation(deviceId: String, characteristicUuid: String, 
                                     queue: ArrayDeque<PendingOperation>) {
        val operation = queue.peekFirst() ?: return
        
        when (operation) {
            is PendingOperation.Read -> {
                // Execute read...
            }
            is PendingOperation.Write -> {
                // Execute write...
            }
        }
    }
    
    // In onCharacteristicRead callback:
    private fun onReadComplete(deviceId: String, characteristicUuid: String, 
                               result: Result<ByteArray>) {
        val key = "$deviceId:$characteristicUuid"
        
        operationLock.withLock {
            val queue = operationQueues[key] ?: return
            val operation = queue.pollFirst() as? PendingOperation.Read ?: return
            
            handler.post { operation.callback(result) }
            
            // Execute next queued operation
            if (queue.isNotEmpty()) {
                executeNextOperation(deviceId, characteristicUuid, queue)
            }
        }
    }
}
```

Option B - Reject concurrent operations:

```kotlin
fun readCharacteristic(
    deviceId: String,
    characteristicUuid: String,
    callback: (Result<ByteArray>) -> Unit
) {
    val key = "$deviceId:$characteristicUuid"
    
    // Check for pending operation
    if (pendingReads.containsKey(key)) {
        callback(Result.failure(IllegalStateException(
            "Read already in progress for $characteristicUuid"
        )))
        return
    }
    
    pendingReads[key] = callback
    // ... rest of implementation
}
```

---

### 7. Server Read/Write Response Not Implemented

**Location:** `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/GattServer.kt:183-200`

**Code:**
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

    // requestId encodes both the device hashcode and offset
    // For simplicity, we store pending requests with device reference
    // This is a simplified implementation - a production version would
    // track pending requests with their associated device
    callback(Result.success(Unit))  // DOES NOTHING!
}
```

Meanwhile, the auto-response is in the callback:

```kotlin
override fun onCharacteristicReadRequest(
    device: BluetoothDevice,
    requestId: Int,
    offset: Int,
    characteristic: BluetoothGattCharacteristic
) {
    // ... emit to Flutter ...
    
    // Auto-respond with success for now (simplified implementation)
    try {
        gattServer?.sendResponse(
            device,
            requestId,
            BluetoothGatt.GATT_SUCCESS,
            offset,
            characteristic.value ?: ByteArray(0)
        )
    } catch (e: SecurityException) {
        // Permission revoked
    }
}
```

**Justification:**

The Server API in Dart exposes `respondToRead` and `respondToWrite` methods that suggest users can provide custom responses to GATT requests. However:

1. The Kotlin implementation ignores the provided status and value
2. It immediately returns success without sending any response
3. The actual response is auto-sent in the callback handler with whatever value was previously in the characteristic
4. Users cannot implement custom read handlers or dynamic values

This makes the entire Server request/response API non-functional.

**Impact:**
- Custom GATT server implementations are impossible
- Dynamic characteristic values don't work
- Read authentication/authorization cannot be implemented
- Users waste time debugging why their responses aren't working

**Proposed Solution:**

Track pending requests and respond with user-provided values:

```kotlin
class GattServer(...) {
    // Track pending requests by ID
    data class PendingRequest(
        val device: BluetoothDevice,
        val requestId: Int,
        val offset: Int
    )
    
    private val pendingReadRequests = mutableMapOf<Long, PendingRequest>()
    private val pendingWriteRequests = mutableMapOf<Long, PendingRequest>()
    private var nextRequestId = 0L
    
    override fun onCharacteristicReadRequest(
        device: BluetoothDevice,
        requestId: Int,
        offset: Int,
        characteristic: BluetoothGattCharacteristic
    ) {
        // Generate a unique ID for this request
        val uniqueId = nextRequestId++
        pendingReadRequests[uniqueId] = PendingRequest(device, requestId, offset)
        
        val request = ReadRequestDto(
            requestId = uniqueId,  // Use our unique ID
            centralId = device.address,
            characteristicUuid = characteristic.uuid.toString(),
            offset = offset.toLong()
        )
        
        handler.post {
            flutterApi.onReadRequest(request) {}
        }
        
        // DON'T auto-respond - wait for respondToReadRequest
    }
    
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
        
        val pending = pendingReadRequests.remove(requestId)
        if (pending == null) {
            callback(Result.failure(IllegalStateException("Unknown request ID: $requestId")))
            return
        }
        
        try {
            val gattStatus = when (status) {
                GattStatusDto.SUCCESS -> BluetoothGatt.GATT_SUCCESS
                GattStatusDto.READ_NOT_PERMITTED -> BluetoothGatt.GATT_READ_NOT_PERMITTED
                GattStatusDto.WRITE_NOT_PERMITTED -> BluetoothGatt.GATT_WRITE_NOT_PERMITTED
                // ... map other statuses
                else -> BluetoothGatt.GATT_FAILURE
            }
            
            server.sendResponse(
                pending.device,
                pending.requestId,
                gattStatus,
                pending.offset,
                value ?: ByteArray(0)
            )
            callback(Result.success(Unit))
        } catch (e: SecurityException) {
            callback(Result.failure(e))
        }
    }
}
```

Also add a timeout to auto-respond if the Flutter side doesn't respond:

```kotlin
override fun onCharacteristicReadRequest(...) {
    val uniqueId = nextRequestId++
    pendingReadRequests[uniqueId] = PendingRequest(device, requestId, offset)
    
    // ... emit to Flutter ...
    
    // Auto-respond after timeout if Flutter doesn't respond
    handler.postDelayed({
        val pending = pendingReadRequests.remove(uniqueId)
        if (pending != null) {
            Log.w("GattServer", "Read request $uniqueId timed out, auto-responding")
            try {
                gattServer?.sendResponse(
                    pending.device,
                    pending.requestId,
                    BluetoothGatt.GATT_FAILURE,
                    pending.offset,
                    ByteArray(0)
                )
            } catch (e: Exception) {
                Log.e("GattServer", "Failed to auto-respond", e)
            }
        }
    }, 5000)  // 5 second timeout
}
```

---

### 8. Scan Stream Controller Not Reset Between Scans

**Location:** `bluey_android/lib/src/bluey_android.dart:88-90`

**Code:**
```dart
_flutterApi.onScanCompleteCallback = () {
  // Scan completed - close and recreate the controller for next scan
  // NOTE: This comment describes what SHOULD happen, but the body is empty!
};
```

**Justification:**

The comment indicates the intent to reset the scan controller when a scan completes, but the implementation is empty. This causes:

1. The `_scanController` (a broadcast `StreamController`) persists across multiple scans
2. Old listeners may still be attached from previous scans
3. If a scan fails or is stopped, the stream state may be inconsistent
4. Memory usage grows if listeners aren't properly removed

**Impact:**
- Duplicate device discovery events if old listeners remain
- Memory leak from accumulated listeners
- Potential for receiving stale scan results

**Proposed Solution:**

```dart
class BlueyAndroid extends BlueyPlatform {
  StreamController<PlatformDevice>? _scanController;
  
  @override
  Stream<PlatformDevice> scan(PlatformScanConfig config) {
    _ensureInitialized();
    
    // Close any existing scan controller
    _scanController?.close();
    
    // Create fresh controller for this scan
    _scanController = StreamController<PlatformDevice>.broadcast(
      onCancel: () {
        // When all listeners cancel, stop the scan
        _hostApi.stopScan();
      },
    );
    
    final dto = ScanConfigDto(
      serviceUuids: config.serviceUuids,
      timeoutMs: config.timeoutMs,
    );

    _hostApi.startScan(dto);

    return _scanController!.stream;
  }
  
  void _ensureInitialized() {
    if (_isInitialized) return;
    _isInitialized = true;

    BlueyFlutterApi.setUp(_flutterApi);

    _flutterApi.onDeviceDiscoveredCallback = (device) {
      // Only emit if we have an active scan
      if (_scanController != null && !_scanController!.isClosed) {
        _scanController!.add(_mapDevice(device));
      }
    };

    _flutterApi.onScanCompleteCallback = () {
      // Close the controller to signal scan completion
      _scanController?.close();
      _scanController = null;
    };
    
    // ... rest of initialization
  }
  
  @override
  Future<void> stopScan() async {
    _ensureInitialized();
    await _hostApi.stopScan();
    
    // Also close the controller
    _scanController?.close();
    _scanController = null;
  }
}
```

---

## Medium Severity Bugs

### 9. MTU Not Synchronized with Platform Callbacks

**Location:** `bluey/lib/src/bluey_connection.dart:127-131` and `bluey_android/lib/src/bluey_android.dart`

**Code in BlueyConnection:**
```dart
@override
Future<int> requestMtu(int mtu) async {
  final negotiatedMtu = await _platform.requestMtu(_deviceAddress, mtu);
  _mtu = negotiatedMtu;
  return _mtu;
}
```

**Code in BlueyAndroid:**
```dart
_flutterApi.onMtuChangedCallback = (event) {
  // MTU change is also reflected through the callback
  // Currently we don't expose this as a separate stream
};
```

**Justification:**

The MTU can change in two scenarios:
1. Local request via `requestMtu()` - handled by updating `_mtu`
2. Remote device initiates MTU change - callback fires but `_mtu` is not updated

The current implementation only handles case 1. The platform callback does nothing with the MTU change event.

**Impact:**
- After a remote-initiated MTU change, `connection.mtu` returns stale value
- Write operations may fail if the user relies on stale MTU for chunking
- Difficult to debug issues with large characteristic writes

**Proposed Solution:**

Expose MTU changes as a stream and keep the local value synchronized:

```dart
// In BlueyConnection
final StreamController<int> _mtuController = StreamController<int>.broadcast();
StreamSubscription? _platformMtuSubscription;

BlueyConnection(...) {
  // ... existing subscriptions ...
  
  _platformMtuSubscription = _platform
      .mtuStream(_deviceAddress)
      .listen((mtu) {
        _mtu = mtu;
        _mtuController.add(mtu);
      });
}

@override
int get mtu => _mtu;

/// Stream of MTU changes.
Stream<int> get mtuChanges => _mtuController.stream;

Future<void> _cleanup() async {
  // ... existing cleanup ...
  await _platformMtuSubscription?.cancel();
  await _mtuController.close();
}
```

And in BlueyAndroid:

```dart
final Map<String, StreamController<int>> _mtuControllers = {};

Stream<int> mtuStream(String deviceId) {
  return _mtuControllers.putIfAbsent(
    deviceId, 
    () => StreamController<int>.broadcast()
  ).stream;
}

// In _ensureInitialized:
_flutterApi.onMtuChangedCallback = (event) {
  final controller = _mtuControllers[event.deviceId];
  controller?.add(event.mtu);
};
```

---

### 10. Connection Timeout Handler Not Cancelled

**Location:** `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/ConnectionManager.kt:78-100`

**Code:**
```kotlin
// Set timeout if specified
config.timeoutMs?.let { timeout ->
    handler.postDelayed({
        // If still connecting after timeout, fail the connection
        val pendingCallback = pendingConnections.remove(deviceId)
        if (pendingCallback != null) {
            // Cleanup...
        }
    }, timeout)
}
```

In `onConnectionStateChange`:

```kotlin
BluetoothProfile.STATE_CONNECTED -> {
    notifyConnectionState(deviceId, ConnectionStateDto.CONNECTED)
    val pendingCallback = pendingConnections.remove(deviceId)
    if (pendingCallback != null) {
        handler.post {
            pendingCallback.invoke(Result.success(deviceId))
        }
    }
    // NOTE: Timeout handler is NOT cancelled!
}
```

**Justification:**

When a connection succeeds, the pending callback is removed but the timeout `Runnable` continues to exist in the handler queue. While it won't cause immediate issues (since `pendingConnections.remove()` returns null), it:

1. Wastes memory until the timeout fires
2. Could cause issues if the device is quickly reconnected with the same address
3. Indicates incomplete resource management

**Impact:**
- Memory waste from accumulated timeout handlers
- Potential for bugs if connection logic is modified
- Difficult to debug timing issues

**Proposed Solution:**

Track and cancel the timeout handler:

```kotlin
class ConnectionManager(...) {
    private val connectionTimeouts = mutableMapOf<String, Runnable>()
    
    fun connect(
        deviceId: String,
        config: ConnectConfigDto,
        callback: (Result<String>) -> Unit
    ) {
        // ... existing connection code ...
        
        config.timeoutMs?.let { timeout ->
            val timeoutRunnable = Runnable {
                connectionTimeouts.remove(deviceId)
                val pendingCallback = pendingConnections.remove(deviceId)
                if (pendingCallback != null) {
                    // Cleanup and fail...
                }
            }
            connectionTimeouts[deviceId] = timeoutRunnable
            handler.postDelayed(timeoutRunnable, timeout)
        }
    }
    
    // In onConnectionStateChange:
    override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
        val deviceId = gatt.device.address
        
        // Cancel any pending timeout
        connectionTimeouts.remove(deviceId)?.let { handler.removeCallbacks(it) }
        
        when (newState) {
            BluetoothProfile.STATE_CONNECTED -> {
                // ... existing code ...
            }
            BluetoothProfile.STATE_DISCONNECTED -> {
                // ... existing code ...
            }
        }
    }
    
    fun cleanup() {
        // Cancel all pending timeouts
        connectionTimeouts.forEach { (_, runnable) ->
            handler.removeCallbacks(runnable)
        }
        connectionTimeouts.clear()
        
        // ... rest of cleanup ...
    }
}
```

---

### 11. Descriptor UUID Collision in findDescriptor

**Location:** `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/ConnectionManager.kt:562-574`

**Code:**
```kotlin
private fun findDescriptor(gatt: BluetoothGatt, uuid: String): BluetoothGattDescriptor? {
    val normalizedUuid = normalizeUuid(uuid)
    for (service in gatt.services ?: emptyList()) {
        for (characteristic in service.characteristics ?: emptyList()) {
            for (descriptor in characteristic.descriptors ?: emptyList()) {
                if (descriptor.uuid.toString().equals(normalizedUuid, ignoreCase = true)) {
                    return descriptor  // Returns FIRST match only
                }
            }
        }
    }
    return null
}
```

**Justification:**

The CCCD (Client Characteristic Configuration Descriptor) has UUID `0x2902` and exists on every characteristic that supports notifications or indications. This function returns the first descriptor with a matching UUID across all services and characteristics.

If a device has multiple notifiable characteristics:
1. Characteristic A has CCCD with UUID 0x2902
2. Characteristic B has CCCD with UUID 0x2902
3. Calling `findDescriptor(gatt, "2902")` always returns Characteristic A's CCCD
4. Operations intended for Characteristic B's CCCD affect Characteristic A instead

**Impact:**
- Enabling notifications on one characteristic may actually enable them on another
- Descriptor reads return wrong values
- Extremely difficult to debug because UUIDs match

**Proposed Solution:**

Change the API to require both characteristic UUID and descriptor UUID:

```kotlin
private fun findDescriptor(
    gatt: BluetoothGatt, 
    characteristicUuid: String,
    descriptorUuid: String
): BluetoothGattDescriptor? {
    val normalizedCharUuid = normalizeUuid(characteristicUuid)
    val normalizedDescUuid = normalizeUuid(descriptorUuid)
    
    for (service in gatt.services ?: emptyList()) {
        for (characteristic in service.characteristics ?: emptyList()) {
            if (characteristic.uuid.toString().equals(normalizedCharUuid, ignoreCase = true)) {
                for (descriptor in characteristic.descriptors ?: emptyList()) {
                    if (descriptor.uuid.toString().equals(normalizedDescUuid, ignoreCase = true)) {
                        return descriptor
                    }
                }
            }
        }
    }
    return null
}

fun readDescriptor(
    deviceId: String,
    characteristicUuid: String,  // Add this parameter
    descriptorUuid: String,
    callback: (Result<ByteArray>) -> Unit
) {
    // ... validation ...
    
    val descriptor = findDescriptor(gatt, characteristicUuid, descriptorUuid)
    // ...
}
```

Update the Pigeon API and Dart layer to pass the characteristic UUID along with descriptor operations.

---

### 12. BlueyCentral ID Conversion Truncates MAC Address

**Location:** `bluey/lib/src/bluey_server.dart:182-196`

**Code:**
```dart
@override
UUID get id {
  // Convert the platform ID to a UUID
  // If it's already a UUID format, use it directly
  if (platformId.length == 36 && platformId.contains('-')) {
    return UUID(platformId);
  }
  // Otherwise, create a UUID from the string by padding
  final bytes = platformId.codeUnits;
  final padded = List<int>.filled(16, 0);
  for (var i = 0; i < bytes.length && i < 16; i++) {
    padded[i] = bytes[i];  // Truncates at 16 bytes!
  }
  // Convert to hex string
  final hex = padded.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return UUID(hex);
}
```

**Justification:**

A MAC address like `AA:BB:CC:DD:EE:FF` is 17 characters. The code:

1. Takes the string's code units (ASCII values): `[65, 65, 58, 66, 66, 58, 67, 67, 58, 68, 68, 58, 69, 69, 58, 70, 70]` = 17 bytes
2. Truncates to 16 bytes, losing the final `F` (70)
3. Creates an inconsistent UUID that can't be reversed to the original MAC

This means two different MACs could theoretically map to the same UUID (collision).

**Impact:**
- Cannot reliably identify centrals by their UUID
- Debugging becomes difficult when MACs don't match
- Potential for sending data to wrong central if collision occurs

**Proposed Solution:**

Use a proper MAC-to-UUID conversion:

```dart
@override
UUID get id {
  // If it's already a UUID format, use it directly
  if (platformId.length == 36 && platformId.contains('-')) {
    return UUID(platformId);
  }
  
  // If it looks like a MAC address, convert it properly
  if (platformId.contains(':') && platformId.length == 17) {
    // MAC format: AA:BB:CC:DD:EE:FF
    // Convert to UUID by padding with zeros at the front
    // Result: 00000000-0000-0000-00AA-BBCCDDEEFF
    final cleanMac = platformId.replaceAll(':', '').toLowerCase();
    final padded = cleanMac.padLeft(32, '0');
    return UUID(padded);
  }
  
  // Fallback: hash the string to create a deterministic UUID
  final hash = sha256.convert(utf8.encode(platformId)).bytes;
  final hex = hash.sublist(0, 16)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  return UUID(hex);
}
```

Or simpler - keep the platformId accessible and use UUID only when needed:

```dart
class BlueyCentral implements Central {
  final String platformId;
  
  /// The MAC address or platform-specific identifier.
  String get address => platformId;
  
  @override
  UUID get id => _convertToUuid(platformId);
  
  // ...
}
```

---

### 13. Async Initialization Without Error Handling

**Location:** `bluey/lib/src/bluey_connection.dart:51-99`

**Code:**
```dart
BlueyConnection({...}) : ... {
  // Sync subscriptions
  _platformStateSubscription = _platform.connectionStateStream(...).listen(...);
  _platformBondStateSubscription = _platform.bondStateStream(...).listen(...);
  _platformPhySubscription = _platform.phyStream(...).listen(...);
  
  // Async initializations - fire and forget with no error handling!
  _platform.getBondState(_deviceAddress).then((platformBondState) {
    _bondState = _mapBondState(platformBondState);
  });
  
  _platform.getPhy(_deviceAddress).then((platformPhy) {
    _txPhy = _mapPhy(platformPhy.tx);
    _rxPhy = _mapPhy(platformPhy.rx);
  });
  
  _platform.getConnectionParameters(_deviceAddress).then((params) {
    _connectionParameters = _mapConnectionParameters(params);
  });
}
```

**Justification:**

The constructor initiates several async operations:
1. No error handling - if any fails, the error is swallowed
2. No completion tracking - callers don't know when initialization is done
3. Getters return stale default values if accessed before init completes
4. Violates the principle that constructors should be synchronous

**Impact:**
- Silent failures during initialization
- Race conditions accessing properties before they're populated
- Inconsistent state that's difficult to reproduce and debug

**Proposed Solution:**

Use a factory constructor with async initialization:

```dart
class BlueyConnection implements Connection {
  // Private constructor
  BlueyConnection._({
    required platform.BlueyPlatform platformInstance,
    required String connectionId,
    required this.deviceId,
    required BondState bondState,
    required Phy txPhy,
    required Phy rxPhy,
    required ConnectionParameters connectionParameters,
  }) : _platform = platformInstance,
       _deviceAddress = connectionId,
       _bondState = bondState,
       _txPhy = txPhy,
       _rxPhy = rxPhy,
       _connectionParameters = connectionParameters {
    _setupSubscriptions();
  }
  
  /// Creates a new connection with initialized state.
  static Future<BlueyConnection> create({
    required platform.BlueyPlatform platformInstance,
    required String connectionId,
    required UUID deviceId,
  }) async {
    // Fetch initial state in parallel
    final results = await Future.wait([
      platformInstance.getBondState(connectionId),
      platformInstance.getPhy(connectionId),
      platformInstance.getConnectionParameters(connectionId),
    ]);
    
    final bondState = _mapBondState(results[0] as platform.PlatformBondState);
    final phy = results[1] as ({platform.PlatformPhy tx, platform.PlatformPhy rx});
    final params = results[2] as platform.PlatformConnectionParameters;
    
    return BlueyConnection._(
      platformInstance: platformInstance,
      connectionId: connectionId,
      deviceId: deviceId,
      bondState: bondState,
      txPhy: _mapPhy(phy.tx),
      rxPhy: _mapPhy(phy.rx),
      connectionParameters: _mapConnectionParameters(params),
    );
  }
  
  void _setupSubscriptions() {
    _platformStateSubscription = _platform
        .connectionStateStream(_deviceAddress)
        .listen(...);
    // ... other subscriptions
  }
}
```

Update `Bluey.connect()` to use the factory:

```dart
Future<Connection> connect(Device device, {Duration? timeout}) async {
  // ... connect logic ...
  
  return await BlueyConnection.create(
    platformInstance: _platform,
    connectionId: connectionId,
    deviceId: device.id,
  );
}
```

---

## Low Severity Issues

### 14. Unclosed Stream Controllers in BlueyAndroid

**Location:** `bluey_android/lib/src/bluey_android.dart`

**Code:**
```dart
final StreamController<PlatformCentral> _centralConnectionsController =
    StreamController<PlatformCentral>.broadcast();
final StreamController<String> _centralDisconnectionsController =
    StreamController<String>.broadcast();
final StreamController<PlatformReadRequest> _readRequestsController =
    StreamController<PlatformReadRequest>.broadcast();
final StreamController<PlatformWriteRequest> _writeRequestsController =
    StreamController<PlatformWriteRequest>.broadcast();
```

**Justification:**

These controllers are created but never closed. While Dart's garbage collector can clean them up, best practice is to explicitly close stream controllers to:
1. Signal to listeners that no more events will come
2. Allow dependent resources to be freed immediately
3. Catch accidental adds after disposal

**Proposed Solution:**

Add a `dispose()` method:

```dart
Future<void> dispose() async {
  await _stateController.close();
  await _scanController?.close();
  
  for (final controller in _connectionStateControllers.values) {
    await controller.close();
  }
  _connectionStateControllers.clear();
  
  for (final controller in _notificationControllers.values) {
    await controller.close();
  }
  _notificationControllers.clear();
  
  await _centralConnectionsController.close();
  await _centralDisconnectionsController.close();
  await _readRequestsController.close();
  await _writeRequestsController.close();
}
```

---

### 15. Missing Error Propagation in Scanner

**Location:** `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/Scanner.kt:67-71`

**Code:**
```kotlin
override fun onScanFailed(errorCode: Int) {
    handler.post {
        flutterApi.onScanComplete {}  // Only signals completion, not error!
    }
}
```

**Justification:**

When scanning fails, the error code is discarded and only a completion event is sent. The caller has no way to know:
- That the scan failed vs completed normally
- What went wrong (permission denied, Bluetooth off, hardware error, etc.)

**Proposed Solution:**

Add an error callback to the Flutter API:

```kotlin
// In Scanner.kt
override fun onScanFailed(errorCode: Int) {
    val errorMessage = when (errorCode) {
        ScanCallback.SCAN_FAILED_ALREADY_STARTED -> "Scan already started"
        ScanCallback.SCAN_FAILED_APPLICATION_REGISTRATION_FAILED -> "App registration failed"
        ScanCallback.SCAN_FAILED_INTERNAL_ERROR -> "Internal error"
        ScanCallback.SCAN_FAILED_FEATURE_UNSUPPORTED -> "Feature unsupported"
        else -> "Unknown error: $errorCode"
    }
    
    handler.post {
        flutterApi.onScanError(ScanErrorDto(code = errorCode, message = errorMessage)) {}
    }
}
```

And in Dart:

```dart
_flutterApi.onScanErrorCallback = (error) {
  _scanController?.addError(ScanException(error.code, error.message));
  _scanController?.close();
  _scanController = null;
};
```

---

### 16. Bonding/PHY/Connection Parameters Return Stub Implementations

**Location:** `bluey_android/lib/src/bluey_android.dart:240-290`

**Code:**
```dart
@override
Future<PlatformBondState> getBondState(String deviceId) async {
  // TODO: Implement when Android Pigeon API supports bonding
  return PlatformBondState.none;
}

@override
Stream<PlatformBondState> bondStateStream(String deviceId) {
  // TODO: Implement when Android Pigeon API supports bonding
  return const Stream.empty();
}

// ... similar stubs for PHY and connection parameters
```

**Justification:**

The domain layer (`Connection`) exposes these APIs as if they work:
- `connection.bondState` - returns a value (always `none`)
- `connection.bond()` - appears to succeed but does nothing
- `connection.requestPhy()` - silently ignored

Users may integrate these features, ship to production, and discover they don't work.

**Proposed Solution:**

Option A - Throw `UnsupportedOperationException`:

```dart
@override
Future<PlatformBondState> getBondState(String deviceId) async {
  throw UnsupportedOperationException('getBondState', 'Android');
}
```

Option B - Expose capability flags (preferred):

```dart
class Capabilities {
  static const android = Capabilities(
    canScan: true,
    canConnect: true,
    canAdvertise: true,
    canBond: false,  // Not yet implemented
    canRequestPhy: false,  // Not yet implemented
    canRequestConnectionParameters: false,  // Not yet implemented
    // ...
  );
  
  final bool canBond;
  final bool canRequestPhy;
  // ...
}
```

Then in domain layer:

```dart
@override
Future<void> bond() async {
  if (!_platform.capabilities.canBond) {
    throw UnsupportedOperationException('bond', 'Android');
  }
  await _platform.bond(_deviceAddress);
}
```

---

## Summary

| Severity | Count | Categories |
|----------|-------|------------|
| 🔴 Critical | 4 | Connection state race, notification race, disconnect double-emit, no GATT state check |
| 🟠 High | 4 | Memory leak, callback collision, server response no-op, scan controller not reset |
| 🟡 Medium | 5 | MTU not synced, timeout not cancelled, descriptor collision, Central ID truncation, async init |
| 🟢 Low | 3 | Unclosed controllers, missing error propagation, stub implementations |

### Priority Order for Fixes

1. **Critical #1 & #3** - Connection state management (risk of operations on disconnected device)
2. **Critical #2** - Notification race condition (data loss)
3. **High #7** - Server response no-op (feature completely broken)
4. **High #5** - Memory leak (production stability)
5. **Critical #4** - GATT state check (user experience - proper error messages)
6. **High #6** - Callback collision (hanging futures)
7. **Medium issues** - Address based on feature usage
8. **Low issues** - Address during refactoring

### Comparison with Reference Library

The `bluetooth_low_energy` reference library handles several of these scenarios better:

| Issue | Bluey | Reference Library |
|-------|-------|-------------------|
| Connection state | Assumes connected | Queries actual state |
| Notification enable | Fire-and-forget | Awaits CCCD write |
| GATT operations | No state check | Validates connection |
| Callback management | Simple map (collisions) | Queue with mutex |
| Stream cleanup | Incomplete | Full lifecycle management |

The reference library's approach to state management is more robust, though it has its own issues (documented in AUDIT_REPORT.md).
