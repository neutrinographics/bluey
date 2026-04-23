# iOS Implementation Comparison: bluey_ios vs bluetooth_low_energy_darwin

This document provides a comprehensive comparison between the new `bluey_ios` implementation and the reference `bluetooth_low_energy_darwin` library, identifying areas of parity, improvements, regressions, and bugs.

**Analysis Date:** January 2026  
**Reference Library Version:** 7.0.0-dev.4  
**Bluey iOS Version:** Branch `7.0.0-da1nerd`

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Architecture Comparison](#architecture-comparison)
3. [Feature Parity Analysis](#feature-parity-analysis)
4. [Improvements in bluey_ios](#improvements-in-bluey_ios)
5. [Regressions in bluey_ios](#regressions-in-bluey_ios)
6. [Bugs Identified](#bugs-identified)
7. [Detailed Implementation Comparison](#detailed-implementation-comparison)
8. [Recommendations](#recommendations)

---

## Executive Summary

| Category | Count |
|----------|-------|
| Features at Parity | 18 |
| Improvements | 7 |
| Regressions | 5 |
| Bugs (Critical) | 2 |
| Bugs (High) | 3 |
| Bugs (Medium) | 4 |

**Overall Assessment:** The `bluey_ios` implementation is a cleaner, more modern rewrite that simplifies several aspects of the reference library. However, there are notable regressions in GATT object identification and service discovery that could cause issues in production. The bugs identified should be addressed before release.

---

## Architecture Comparison

### Directory Structure

| Aspect | bluetooth_low_energy_darwin | bluey_ios |
|--------|---------------------------|-----------|
| Shared Darwin Code | `darwin/Classes/` (iOS + macOS) | `ios/Classes/` (iOS only) |
| Pigeon Version | v20.0.2 | v22.7.4 |
| Code Organization | Single manager files | Separate manager + delegate files |
| macOS Support | Yes | No |

### Key Architectural Differences

| Aspect | Reference | Bluey | Impact |
|--------|-----------|-------|--------|
| **GATT Object Identification** | Swift object hash codes (`Int64`) | UUID strings | Regression (see bugs) |
| **Service Discovery** | Step-by-step (Dart controls flow) | Automatic cascade (Swift drives) | Improvement |
| **State Initialization** | Explicit `initialize()` method | Lazy initialization | Simplification |
| **Delegate Pattern** | Lazy inline instantiation | Separate delegate classes | Better separation |
| **Error Types** | 3 error cases | 4 error cases | Slightly more granular |

---

## Feature Parity Analysis

### Central Manager Features

| Feature | Reference | Bluey | Status |
|---------|-----------|-------|--------|
| Get Bluetooth state | `getState()` | `getState()` | Parity |
| State change events | `onStateChanged` | `onStateChanged` | Parity |
| Open Settings | `showAppSettings()` | `openSettings()` | Parity |
| Start scanning | `startDiscovery()` | `startScan()` | Parity |
| Stop scanning | `stopDiscovery()` | `stopScan()` | Parity |
| Device discovery events | `onDiscovered` | `onDeviceDiscovered` | Parity |
| Connect to device | `connect()` | `connect()` | Parity |
| Disconnect from device | `disconnect()` | `disconnect()` | Parity |
| Connection state events | `onConnectionStateChanged` | `onConnectionStateChanged` | Parity |
| Discover services | `discoverServices()` | `discoverServices()` | Different (see below) |
| Read characteristic | `readCharacteristic()` | `readCharacteristic()` | Different (see below) |
| Write characteristic | `writeCharacteristic()` | `writeCharacteristic()` | Different (see below) |
| Enable notifications | `setCharacteristicNotifyState()` | `setNotification()` | Parity |
| Notification events | `onCharacteristicNotified` | `onNotification` | Parity |
| Read descriptor | `readDescriptor()` | `readDescriptor()` | Different (see below) |
| Write descriptor | `writeDescriptor()` | `writeDescriptor()` | Different (see below) |
| Read RSSI | `readRSSI()` | `readRssi()` | Parity |
| Get max write length | `getMaximumWriteLength()` | `getMaximumWriteLength()` | Parity |
| Retrieve connected peripherals | `retrieveConnectedPeripherals()` | Not implemented | Regression |

### Peripheral Manager Features

| Feature | Reference | Bluey | Status |
|---------|-----------|-------|--------|
| Get state | `getState()` | implicit via central | Parity |
| Add service | `addService()` | `addService()` | Parity |
| Remove service | `removeService()` | `removeService()` | Parity |
| Remove all services | `removeAllServices()` | `closeServer()` | Parity |
| Start advertising | `startAdvertising()` | `startAdvertising()` | Parity |
| Stop advertising | `stopAdvertising()` | `stopAdvertising()` | Parity |
| Update characteristic value | `updateValue()` | `notifyCharacteristic()` | Parity |
| Respond to read request | `respond()` | `respondToReadRequest()` | Improvement |
| Respond to write request | `respond()` | `respondToWriteRequest()` | Improvement |
| Get max notify length | `getMaximumNotifyLength()` | Not implemented | Minor regression |
| Read request events | `didReceiveRead` | `onReadRequest` | Parity |
| Write request events | `didReceiveWrite` | `onWriteRequest` | Parity |
| Subscription events | `onCharacteristicNotifyStateChanged` | `onCharacteristicSubscribed/Unsubscribed` | Improvement |
| Central connection tracking | Limited | Full tracking | Improvement |
| isReady callback | `isReady()` | `isReadyToUpdateSubscribers()` | Parity (empty impl) |

---

## Improvements in bluey_ios

### 1. Automatic Cascading Service Discovery

**Reference Library Approach:**
```dart
// Dart must call each step explicitly
services = await api.discoverServices(uuid);
for (service in services) {
  chars = await api.discoverCharacteristics(uuid, service.hashCode);
  for (char in chars) {
    descs = await api.discoverDescriptors(uuid, char.hashCode);
  }
}
```

**Bluey Approach:**
```swift
// Swift automatically discovers entire GATT tree
func discoverServices(deviceId: String, completion: ...) {
    peripheral.discoverServices(nil)
    // Automatically triggers:
    // - discoverCharacteristics for each service
    // - discoverDescriptors for each characteristic
    // - Completion fires only when entire tree is discovered
}
```

**Benefit:** Reduces round-trips between Dart and native code, simpler API, fewer potential failure points.

---

### 2. Separate Read/Write Response Methods

**Reference Library:**
```dart
await api.respond(hashCode, value, errorCode);  // Same for read and write
```

**Bluey:**
```dart
await api.respondToReadRequest(requestId, status, value);
await api.respondToWriteRequest(requestId, status);
```

**Benefit:** Type-safe API, clearer intent, prevents accidentally sending value with write response.

---

### 3. Split Subscription Events

**Reference Library:**
```dart
// Single event with boolean state
onCharacteristicNotifyStateChanged(hashCode, centralArgs, stateArgs: bool)
```

**Bluey:**
```dart
// Separate events for subscribe and unsubscribe
onCharacteristicSubscribed(centralId, characteristicUuid)
onCharacteristicUnsubscribed(centralId, characteristicUuid)
```

**Benefit:** Clearer semantics, easier to handle in reactive streams.

---

### 4. Central Connection/Disconnection Tracking

**Reference Library:**
- Centrals tracked only by subscription state
- No explicit connect/disconnect events for centrals

**Bluey:**
```swift
// Explicit central tracking
var centrals: [String: CBCentral] = [:]
var subscribedCentrals: [String: Set<String>] = [:]

// Explicit events
flutterApi.onCentralConnected(central: centralDto)
flutterApi.onCentralDisconnected(centralId: centralId)
```

**Benefit:** Full visibility into which centrals are connected, easier to implement connection limits and targeted notifications.

---

### 5. UUID Normalization in Dart Layer

**Reference Library:**
- UUIDs passed through as-is
- Short UUIDs may not match full UUIDs in comparisons

**Bluey:**
```dart
String _expandUuid(String uuid) {
  // "180F" -> "0000180f-0000-1000-8000-00805f9b34fb"
  // Handles 4-char, 8-char, and 32-char formats
}
```

**Benefit:** Consistent UUID format across the entire domain layer, reliable comparisons.

---

### 6. Cleaner Error Type Hierarchy

**Reference Library:**
```swift
enum BluetoothLowEnergyError: Error {
    case unknown
    case unsupported
    case illegalArgument
}
```

**Bluey:**
```swift
enum BlueyError: Error {
    case unknown
    case illegalArgument
    case unsupported
    case notConnected  // NEW
    case notFound      // NEW
}
```

**Benefit:** More specific error types allow better error handling in the domain layer.

---

### 7. Simpler Completion Handler Storage

**Reference Library:**
```swift
// Nested dictionaries with Int64 hash codes
var mReadCharacteristicCompletions: [String: [Int64: Completion]] = [:]
```

**Bluey:**
```swift
// Nested dictionaries with String UUIDs
var readCharacteristicCompletions: [String: [String: Completion]] = [:]
```

**Benefit:** String keys are more debuggable, no need for hash code lookups.

---

## Regressions in bluey_ios

### 1. Missing `retrieveConnectedPeripherals()` Method

**Reference Library:**
```swift
func retrieveConnectedPeripherals() throws -> [PeripheralArgs] {
    let peripherals = mCentralManager.retrieveConnectedPeripherals(withServices: [])
    // Returns already-connected peripherals without scanning
}
```

**Bluey:** Not implemented.

**Impact:** Cannot reconnect to previously connected devices without scanning. This is particularly important for:
- Background reconnection scenarios
- Restoring connections after app restart
- Reducing battery usage by avoiding scans

**Severity:** Medium

---

### 2. UUID-Based GATT Object Identification (Critical Design Difference)

**Reference Library:**
```swift
// Uses Swift object hash codes - unique per object instance
let hashCodeArgs = characteristic.hash.toInt64()
mCharacteristics[uuidArgs, default: [:]][hashCodeArgs] = characteristic
```

**Bluey:**
```swift
// Uses UUID strings - not unique if same UUID appears multiple times
let charUuid = characteristic.uuid.uuidString.lowercased()
characteristics[deviceId, default: [:]][charUuid] = characteristic
```

**Impact:** If a device has multiple characteristics with the same UUID (which is allowed by BLE spec, though rare), operations will target the wrong characteristic.

**Example Failure Scenario:**
```
Service A:
  Characteristic X (UUID: 2A19) - Battery Level
Service B:
  Characteristic Y (UUID: 2A19) - Battery Level (different battery)

// Bluey will only see one of these, losing the other
```

**Severity:** High

---

### 3. Descriptor UUID Collision (Same Issue)

**Reference Library:**
```swift
let hashCodeArgs = descriptor.hash.toInt64()
mDescriptors[uuidArgs, default: [:]][hashCodeArgs] = descriptor
```

**Bluey:**
```swift
let descUuid = descriptor.uuid.uuidString.lowercased()
descriptors[deviceId, default: [:]][descUuid] = descriptor
```

**Impact:** CCCD (Client Characteristic Configuration Descriptor) has UUID `0x2902` on every notifiable characteristic. Only one will be accessible.

**Severity:** High (affects all notification-capable devices with multiple notifiable characteristics)

---

### 4. No Included Services Discovery Completion

**Reference Library:**
```swift
// Separate API for included services
func discoverIncludedServices(uuidArgs: String, hashCodeArgs: Int64, completion: ...)
```

**Bluey:**
```swift
// Included services discovered but stored without notification
func didDiscoverIncludedServices(peripheral: CBPeripheral, service: CBService, error: Error?) {
    // Store in cache but no completion handler
    // Discovery completion fires when all regular discovery is done
}
```

**Impact:** Caller cannot determine when included services are fully discovered vs. just the primary services.

**Severity:** Low (included services are rarely used)

---

### 5. No Maximum Notify Length API

**Reference Library:**
```swift
func getMaximumNotifyLength(uuidArgs: String) throws -> Int64 {
    let central = mCentrals[uuidArgs]
    return central.maximumUpdateValueLength.toInt64()
}
```

**Bluey:** Not implemented in the host API.

**Impact:** Server implementations cannot determine the maximum payload size for notifications to a specific central.

**Severity:** Low (most implementations use a conservative fixed size)

---

## Bugs Identified

### Critical Bugs

#### BUG-iOS-1: Descriptor UUID Collision Causes Wrong Descriptor Access

**Location:** `bluey_ios/ios/Classes/CentralManagerImpl.swift:244-270`

**Code:**
```swift
private func findDescriptor(deviceId: String, uuid: String) -> CBDescriptor? {
    guard let deviceDescs = descriptors[deviceId] else { return nil }

    // Try exact match first
    if let desc = deviceDescs[uuid] {
        return desc
    }

    // Try matching by CBUUID (handles short UUID matching)
    let targetCBUUID = uuid.toCBUUID()
    for (_, desc) in deviceDescs {
        if desc.uuid == targetCBUUID {
            return desc
        }
    }

    return nil
}
```

**Problem:** Descriptors are stored by UUID string, but the CCCD descriptor (UUID 2902) exists on every notifiable/indicatable characteristic. Only the last one discovered is retained.

**Justification:** When a device has multiple notifiable characteristics:
1. Characteristic A has CCCD with UUID 2902
2. Characteristic B has CCCD with UUID 2902
3. `descriptors[deviceId]["2902"]` will only contain one of them
4. Writing to the CCCD will enable/disable notifications on the wrong characteristic

**Impact:** Notification enable/disable operations may target wrong characteristics.

**Proposed Solution:**

Change the caching strategy to include the characteristic UUID as part of the key:

```swift
// Change from:
private var descriptors: [String: [String: CBDescriptor]] = [:] // [deviceId: [descUuid: desc]]

// To:
private var descriptors: [String: [String: CBDescriptor]] = [:] // [deviceId: [charUuid+descUuid: desc]]

// When caching:
let key = "\(characteristicUuid):\(descriptorUuid)"
descriptors[deviceId, default: [:]][key] = descriptor

// When finding:
func findDescriptor(deviceId: String, characteristicUuid: String, descriptorUuid: String) -> CBDescriptor?
```

This requires updating the Pigeon API to pass both characteristic UUID and descriptor UUID for descriptor operations.

---

#### BUG-iOS-2: Characteristic UUID Collision Causes Wrong Characteristic Access

**Location:** `bluey_ios/ios/Classes/CentralManagerImpl.swift:206-223`

**Code:**
```swift
private func findCharacteristic(deviceId: String, uuid: String) -> CBCharacteristic? {
    guard let deviceChars = characteristics[deviceId] else { return nil }

    // Try exact match first
    if let char = deviceChars[uuid] {
        return char
    }
    // ...
}
```

**Problem:** Same issue as BUG-iOS-1 but for characteristics. Though less common, the BLE spec allows multiple characteristics with the same UUID in different services.

**Impact:** Read/write/notify operations may target wrong characteristic.

**Proposed Solution:**

Use service UUID + characteristic UUID as the cache key:

```swift
// Key format: serviceUuid:characteristicUuid
let key = "\(serviceUuid):\(characteristicUuid)"
characteristics[deviceId, default: [:]][key] = characteristic
```

Update the Pigeon API to include service UUID in characteristic operations.

---

### High Severity Bugs

#### BUG-iOS-3: Notification Queue Full Returns Failure Instead of Retry

**Location:** `bluey_ios/ios/Classes/PeripheralManagerImpl.swift:83-93`

**Code:**
```swift
func notifyCharacteristic(characteristicUuid: String, value: FlutterStandardTypedData, completion: @escaping (Result<Void, Error>) -> Void) {
    // ...
    let success = peripheralManager.updateValue(value.data, for: characteristic, onSubscribedCentrals: nil)
    if success {
        completion(.success(()))
    } else {
        // Queue is full, will retry when isReadyToUpdateSubscribers is called
        // For simplicity, we report failure here  <-- PROBLEM
        completion(.failure(BlueyError.unknown))
    }
}
```

**Problem:** When the CoreBluetooth notification queue is full, `updateValue` returns `false`. The reference library implements a retry mechanism (Dart-side loop waiting for `isReady`), but bluey_ios just fails.

**Reference Library Approach:**
```dart
// In peripheral_manager_impl.dart
Future<void> notifyCharacteristic(...) async {
  while (true) {
    final updated = await _api.updateValue(...);
    if (updated) break;
    await _isReady.first;  // Wait for isReady callback
  }
}
```

**Impact:** High-throughput notification scenarios will fail unpredictably instead of throttling gracefully.

**Proposed Solution:**

Option A - Swift-side retry with callback:
```swift
private var pendingNotifications: [(characteristic: CBMutableCharacteristic, value: Data, completion: (Result<Void, Error>) -> Void)] = []

func notifyCharacteristic(...) {
    let success = peripheralManager.updateValue(...)
    if success {
        completion(.success(()))
    } else {
        // Queue for retry
        pendingNotifications.append((characteristic, value, completion))
    }
}

func isReadyToUpdateSubscribers(peripheral: CBPeripheralManager) {
    // Retry pending notifications
    while !pendingNotifications.isEmpty {
        let pending = pendingNotifications.removeFirst()
        let success = peripheralManager.updateValue(pending.value, for: pending.characteristic, onSubscribedCentrals: nil)
        if success {
            pending.completion(.success(()))
        } else {
            pendingNotifications.insert(pending, at: 0)
            break
        }
    }
}
```

Option B - Return boolean for Dart-side retry:
```swift
func notifyCharacteristic(..., completion: @escaping (Result<Bool, Error>) -> Void) {
    let success = peripheralManager.updateValue(...)
    completion(.success(success))  // Let Dart decide to retry
}
```

---

#### BUG-iOS-4: discoverServicesCompletions Not Protected Against Re-discovery

**Location:** `bluey_ios/ios/Classes/CentralManagerImpl.swift:321-332`

**Code:**
```swift
func didDiscoverServices(peripheral: CBPeripheral, error: Error?) {
    let deviceId = peripheral.identifier.uuidString.lowercased()

    // Check if we have a pending completion - if not, this might be a re-discovery
    guard discoverServicesCompletions[deviceId] != nil else {
        return  // Early return, but caches are NOT cleared
    }
    // ...
}
```

**Problem:** If service discovery is triggered twice (e.g., by the system or explicit re-call), the second discovery will populate caches without clearing the old data, potentially leaving stale references.

**Reference Library:** The reference library has the same pattern but uses `removeValue` consistently.

**Impact:** Stale characteristic/descriptor references after service changes (e.g., DFU mode switch).

**Proposed Solution:**

Clear caches at the start of discovery:
```swift
func discoverServices(deviceId: String, completion: ...) {
    guard let peripheral = peripherals[deviceId] else { ... }
    
    // Clear existing GATT cache for this device
    services.removeValue(forKey: deviceId)
    characteristics.removeValue(forKey: deviceId)
    descriptors.removeValue(forKey: deviceId)
    pendingServiceDiscovery.removeValue(forKey: deviceId)
    pendingCharacteristicDiscovery.removeValue(forKey: deviceId)
    
    discoverServicesCompletions[deviceId] = completion
    peripheral.discoverServices(nil)
}
```

---

#### BUG-iOS-5: Missing Connection State Check in GATT Operations

**Location:** `bluey_ios/ios/Classes/CentralManagerImpl.swift:143-155`

**Code:**
```swift
func readCharacteristic(deviceId: String, characteristicUuid: String, completion: ...) {
    let charUuid = normalizeUuid(characteristicUuid)
    guard let characteristic = findCharacteristic(deviceId: deviceId, uuid: charUuid) else {
        completion(.failure(BlueyError.notFound))
        return
    }

    guard let peripheral = peripherals[deviceId], peripheral.state == .connected else {
        completion(.failure(BlueyError.notConnected))
        return
    }
    // ...
}
```

**Problem:** The connection state check happens AFTER finding the characteristic. If the characteristic is found but the peripheral disconnected between `findCharacteristic` and the state check, the error message is confusing (notConnected when characteristic was found).

**Impact:** Misleading error messages during race conditions.

**Proposed Solution:**

Check connection state first:
```swift
func readCharacteristic(deviceId: String, characteristicUuid: String, completion: ...) {
    guard let peripheral = peripherals[deviceId], peripheral.state == .connected else {
        completion(.failure(BlueyError.notConnected))
        return
    }
    
    let charUuid = normalizeUuid(characteristicUuid)
    guard let characteristic = findCharacteristic(deviceId: deviceId, uuid: charUuid) else {
        completion(.failure(BlueyError.notFound))
        return
    }
    // ...
}
```

---

### Medium Severity Bugs

#### BUG-iOS-6: Write Request Only Stores First Request in Batch

**Location:** `bluey_ios/ios/Classes/PeripheralManagerImpl.swift:212-226`

**Code:**
```swift
func didReceiveWrite(peripheral: CBPeripheralManager, requests: [CBATTRequest]) {
    guard let firstRequest = requests.first else { return }
    // ...
    
    let requestId = nextRequestId
    nextRequestId += 1
    pendingWriteRequests[requestId] = requests  // Stores all requests
    
    // Notify Flutter for each request
    for request in requests {
        let requestDto = WriteRequestDto(
            requestId: Int64(requestId),  // SAME ID for all requests!
            // ...
        )
        flutterApi.onWriteRequest(request: requestDto) { _ in }
    }
}
```

**Problem:** All write requests in a batch get the same `requestId`. When `respondToWriteRequest` is called, it will respond to the first request but the subsequent requests in the batch won't get responses.

**Reference Library:** Has the same pattern - stores `requests.first` for response. This appears to be intentional since CoreBluetooth requires responding only once per batch.

**Impact:** In multi-request batches, Dart sees multiple requests with the same ID which may cause confusion.

**Proposed Solution:**

Either:
1. Document that write request batches should be responded to once, or
2. Only send one `onWriteRequest` event per batch with combined value

---

#### BUG-iOS-7: Scan Complete Not Signaled on Error

**Location:** `bluey_ios/ios/Classes/Scanner` (implied from Dart side)

**Problem:** In the Dart layer, `onScanCompleteCallback` is set up but never triggers error handling:

```dart
_flutterApi.onScanCompleteCallback = () {
  // Scan completed
};
```

If scanning fails (e.g., Bluetooth turns off mid-scan), there's no error propagation.

**Reference Library:** Similar issue - scan errors not propagated distinctly.

**Impact:** Scan failures are silent.

**Proposed Solution:**

Add error callback:
```dart
_flutterApi.onScanErrorCallback = (error) {
  _scanController.addError(error);
};
```

---

#### BUG-iOS-8: Lazy Delegate Initialization Creates Retain Cycle Risk

**Location:** `bluey_ios/ios/Classes/CentralManagerImpl.swift:14-23`

**Code:**
```swift
private lazy var centralManagerDelegate: CentralManagerDelegate = {
    let delegate = CentralManagerDelegate()
    delegate.manager = self  // Strong reference to self
    return delegate
}()

private lazy var peripheralDelegate: PeripheralDelegate = {
    let delegate = PeripheralDelegate()
    delegate.manager = self  // Strong reference to self
    return delegate
}()
```

**Problem:** While the delegate uses `weak var manager`, the lazy initialization captures `self` in a closure. This is generally safe in Swift but can cause issues if the CentralManagerImpl is deallocated before the lazy property is accessed.

**Reference Library:** Same pattern, same potential issue.

**Impact:** Potential memory issues, though unlikely in practice since these are long-lived objects.

**Proposed Solution:**

Use explicit initialization instead:
```swift
private var centralManagerDelegate: CentralManagerDelegate!

init(messenger: FlutterBinaryMessenger) {
    // ...
    centralManagerDelegate = CentralManagerDelegate()
    centralManagerDelegate.manager = self
}
```

---

#### BUG-iOS-9: Missing isReady Implementation for Notification Retry

**Location:** `bluey_ios/ios/Classes/PeripheralManagerImpl.swift:228-230`

**Code:**
```swift
func isReadyToUpdateSubscribers(peripheral: CBPeripheralManager) {
    // The queue has space again for notifications
    // We could retry any failed notifications here
}
```

**Problem:** The callback is received but does nothing. Combined with BUG-iOS-3, this means failed notifications are never retried.

**Impact:** Notification reliability issues under high throughput.

**Proposed Solution:** Implement retry queue as described in BUG-iOS-3.

---

## Detailed Implementation Comparison

### Service Discovery Flow

```
Reference Library (bluetooth_low_energy_darwin):
┌──────────┐    ┌──────────────────────────────────────────┐
│   Dart   │    │                  Swift                   │
├──────────┤    ├──────────────────────────────────────────┤
│          │    │                                          │
│ discover │───>│ discoverServices()                       │
│ Services │    │   └── peripheral.discoverServices(nil)   │
│          │<───│       └── completion([services])         │
│          │    │                                          │
│ discover │───>│ discoverCharacteristics()                │
│ Chars    │    │   └── peripheral.discoverCharacteristics │
│          │<───│       └── completion([characteristics])  │
│          │    │                                          │
│ discover │───>│ discoverDescriptors()                    │
│ Descs    │    │   └── peripheral.discoverDescriptors     │
│          │<───│       └── completion([descriptors])      │
│          │    │                                          │
└──────────┘    └──────────────────────────────────────────┘

Bluey (bluey_ios):
┌──────────┐    ┌──────────────────────────────────────────┐
│   Dart   │    │                  Swift                   │
├──────────┤    ├──────────────────────────────────────────┤
│          │    │                                          │
│ discover │───>│ discoverServices()                       │
│ Services │    │   └── peripheral.discoverServices(nil)   │
│          │    │       └── didDiscoverServices()          │
│          │    │           └── discoverCharacteristics()  │
│          │    │               └── didDiscoverChars()     │
│          │    │                   └── discoverDescs()    │
│          │    │                       └── didDiscoverD() │
│          │<───│                           └── completion │
│          │    │                              ([services  │
│          │    │                               with all   │
│          │    │                               children]) │
└──────────┘    └──────────────────────────────────────────┘
```

**Analysis:** Bluey's approach reduces Dart↔Native round trips from 1+N+M to just 1, where N is the number of services and M is the number of characteristics.

### Completion Handler Maps

```swift
// Reference Library - Uses hash codes
mReadCharacteristicCompletions: [String: [Int64: Completion]]
//                               │        │
//                               │        └── Swift object hash
//                               └── Peripheral UUID

// Bluey - Uses UUID strings
readCharacteristicCompletions: [String: [String: Completion]]
//                              │        │
//                              │        └── Characteristic UUID
//                              └── Device ID (peripheral UUID)
```

**Trade-offs:**

| Aspect | Hash Codes (Reference) | UUID Strings (Bluey) |
|--------|----------------------|----------------------|
| Uniqueness | Guaranteed unique per object | Not unique if same UUID in different services |
| Debuggability | Opaque numbers | Human-readable |
| Stability | Stable for object lifetime | Stable across sessions |
| Memory | Slightly more efficient | Slightly more memory |
| Collision risk | None | Yes (see BUG-iOS-2) |

### Error Handling Comparison

```swift
// Reference Library
enum BluetoothLowEnergyError: Error {
    case unknown
    case unsupported
    case illegalArgument
}

// Bluey
enum BlueyError: Error, LocalizedError {
    case unknown
    case illegalArgument
    case unsupported
    case notConnected
    case notFound
    
    var errorDescription: String? {
        switch self {
        case .unknown: return "An unknown error occurred"
        case .illegalArgument: return "Invalid argument provided"
        case .unsupported: return "Operation not supported on this platform"
        case .notConnected: return "Device is not connected"
        case .notFound: return "Resource not found"
        }
    }
}
```

**Analysis:** Bluey's error types are more granular and include `LocalizedError` conformance for better error messages.

---

## Recommendations

### Priority 1 (Before Release)

1. **Fix UUID collision bugs (BUG-iOS-1, BUG-iOS-2)**
   - Change cache keys to include parent object UUID
   - Update Pigeon API to pass service UUID for characteristic operations
   - Update Pigeon API to pass characteristic UUID for descriptor operations

2. **Implement notification retry (BUG-iOS-3, BUG-iOS-9)**
   - Add pending notification queue
   - Implement retry in `isReadyToUpdateSubscribers`

### Priority 2 (Should Have)

3. **Add `retrieveConnectedPeripherals()` API**
   - Required for background reconnection scenarios
   - Matches reference library feature set

4. **Clear GATT cache on re-discovery (BUG-iOS-4)**
   - Prevent stale references after service changes

5. **Fix connection state check order (BUG-iOS-5)**
   - Check connection before finding characteristic

### Priority 3 (Nice to Have)

6. **Add `getMaximumNotifyLength()` API**
   - Useful for optimizing notification payload sizes

7. **Consider scan error propagation (BUG-iOS-7)**
   - Add `onScanError` callback

8. **Document write request batch behavior (BUG-iOS-6)**
   - Clarify that batch writes share a request ID

### Not Recommended

- Switching back to hash-code-based identification
  - While it prevents UUID collisions, the debugging experience is worse
  - Better to fix the collision issue with composite keys

---

## Conclusion

The `bluey_ios` implementation represents a thoughtful simplification of the reference library with several genuine improvements:
- Automatic cascading service discovery
- Better error types
- Cleaner API separation (separate read/write response methods)
- Full central connection tracking

However, the fundamental design decision to use UUID strings instead of hash codes for GATT object identification introduces collision risks that must be addressed before production use. The notification queue handling also needs work to match the reliability of the reference implementation.

With the recommended fixes applied, `bluey_ios` would be a solid improvement over the reference library for most use cases.
