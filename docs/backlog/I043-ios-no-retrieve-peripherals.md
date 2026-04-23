---
id: I043
title: "iOS does not expose `retrievePeripherals(withIdentifiers:)` / `retrieveConnectedPeripherals(withServices:)`"
category: unimplemented
severity: medium
platform: ios
status: open
last_verified: 2026-04-23
---

## Symptom

iOS apps that want to reconnect to a previously-known peripheral after relaunch — without rediscovering it via a fresh scan — have no way to do so through Bluey. CoreBluetooth supports this via `CBCentralManager.retrievePeripherals(withIdentifiers:)` (given a stored UUID) and `retrieveConnectedPeripherals(withServices:)` (for peers already connected by the system). Bluey exposes neither.

Consequence: apps must always scan to reconnect, which is slow (scan discovery time) and power-hungry compared to direct retrieve-then-connect.

## Location

`bluey_ios/ios/Classes/CentralManagerImpl.swift` — no `retrievePeripherals` or `retrieveConnectedPeripherals` call anywhere. The `peripherals` cache is populated only from `didDiscover` (scan results).

## Root cause

Feature was not in the initial cut. Most Flutter BLE libraries don't expose this; it's a specifically iOS-flavored reconnection pattern.

## Notes

Fix sketch:

- Pigeon addition: `retrievePeripheralsByIdentifiers(deviceIds: List<String>) → List<DeviceDto>` and `retrieveConnectedPeripheralsByServices(serviceUuids: List<String>) → List<DeviceDto>`.
- iOS side: straight delegation to CoreBluetooth. Register the returned `CBPeripheral`s in the `peripherals` cache.
- Android side: emit `UnsupportedOperationException` or expose a compatible shape (Android's `BluetoothAdapter.getBondedDevices()` is analogous but not identical — retrieves *bonded* not *previously-known*).
- Domain API decision: whether this is an iOS-only escape hatch (with capability gating via I053) or abstracted as `Bluey.knownDevices({required Set<UUID> requiredServices})` with different semantics per platform.

This is a real feature gap for any iOS app that maintains long-lived connections. Android apps with the same need typically use MAC addresses directly with `bluetoothAdapter.getRemoteDevice(mac)` — a different shape but similar ergonomics.
