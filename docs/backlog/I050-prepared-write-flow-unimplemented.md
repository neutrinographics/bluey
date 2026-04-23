---
id: I050
title: Prepared-write (long-write) flow unimplemented
category: unimplemented
severity: medium
platform: both
status: open
last_verified: 2026-04-23
---

## Symptom

ATT writes are limited to `MTU - 3` bytes per packet. For larger payloads, BLE specifies a multi-step prepared-write protocol: the client sends `PREPARE_WRITE` requests with offset chunks, the server buffers them, then the client sends `EXECUTE_WRITE` to commit (or cancel). Bluey neither exposes this to clients nor handles it on servers.

Client-side impact: writing a characteristic value larger than `MTU - 3` fails. Most modern stacks auto-negotiate MTU up to 247+ bytes so this rarely bites, but it's still a spec-compliance gap.

Server-side impact: the Android server receives `onCharacteristicWriteRequest(..., preparedWrite: true, ...)` and discards the flag, treating it as a normal write. If a conformant client tries a prepared write, the behavior is undefined.

## Location

- **Domain**: no API. `RemoteCharacteristic.write` / `writeLong` / `writeLargeValue` don't exist.
- **Android (client)**: `BluetoothGatt.beginReliableWrite()` / `executeReliableWrite()` / `abortReliableWrite()` not called anywhere.
- **Android (server)**: `GattServer.kt:441, 500` — `preparedWrite` parameter is received but not routed through Pigeon; `onExecuteWrite` callback is not implemented.
- **iOS (client)**: CoreBluetooth does this transparently — `writeValue(_:for:type:)` handles chunking up to the implementation-defined limit. No Bluey code needed on iOS client.
- **iOS (server)**: `didReceiveWrite` delivers a single reassembled request to `CBPeripheralManagerDelegate` for prepared-write groups. One of the requests in a prepared-write bundle; needs special handling if we care about atomicity.

## Root cause

Feature was never in scope for the initial library cut.

## Notes

The design needs to decide:

1. **Is there a user-facing Dart API** for the client to initiate a prepared write? (E.g., `characteristic.writeLong(bytes)` which either uses write-long protocol or fails if the payload exceeds `maxWriteLength`.)
2. **Is the server-side API** an atomic delivery (single `onWriteRequest` with reassembled data and an `atomic: true` flag)? Or a multi-event sequence that the server app manually commits?

Option (1) pushes complexity into the library; option (2) pushes it into the user. (1) is clearly better for users.

Fix sketch:

- Android client: add `writeLongCharacteristic(deviceId, charUuid, data)` that uses `beginReliableWrite` / chunked `writeCharacteristic` / `executeReliableWrite`. Enqueue through `GattOpQueue`.
- Android server: wire `preparedWrite` flag + `onExecuteWrite` to Pigeon. Add `pendingPreparedWrites: Map<centralId, List<chunk>>` — accumulate, deliver one `onWriteRequest` on execute, auto-respond to each PREPARE.
- iOS client: nothing needed; already transparent.
- iOS server: handle the CoreBluetooth behavior correctly (it delivers atomic reassembly) and mirror the server-side Pigeon shape.

Coupled with I020 (server write response) — the fix for I020 should consciously leave prepared-writes as pass-through-auto-respond for now, and a later entry replaces that with buffered delivery.

Why it's medium, not high: in practice modern Bluey interactions negotiate MTU ≥ 247, so characteristic values fit in a single ATT write. Only matters for legacy peers or unusually large values.
