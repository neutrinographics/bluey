---
id: I202
title: iOS `cancelPeripheralConnection` unreliable
category: limitation
severity: medium
platform: ios
status: wontfix
last_verified: 2026-04-23
---

## Rationale

`CBCentralManager.cancelPeripheralConnection(_:)` is reference-counted across apps and system services (notably ANCS — Apple Notification Center Service). Calling it only decrements the app's reference; if any other consumer still holds the connection, the physical BLE link stays up. `didDisconnectPeripheral` fires locally, but the remote peer may never see `LL_TERMINATE_IND`.

Symptoms observed on Android peripherals connected to iOS: iOS reports disconnect, Android's `onConnectionStateChange(STATE_DISCONNECTED)` never fires, the central stays in the connected list indefinitely. Only toggling Bluetooth off on iOS forces link teardown via supervision timeout.

## Current mitigation

- Server-side: the lifecycle control service (see I201) lets Bluey servers time out "zombie" client entries via heartbeat loss.
- Client-initiated protocol-level disconnect: `BlueyPeer` supports a soft disconnect command the client writes to a server characteristic, and the server side initiates the disconnect. Server-initiated disconnects are honored because the server owns its GATT resources.

## Decision

Wontfix at the iOS level. This is a well-known Apple behavior, confirmed by BLE sniffer traces, documented in CoreBluetooth lore and multiple other libraries. No workaround exists within CoreBluetooth.

## Notes

When writing cross-platform BLE code with Bluey, the rule of thumb: **make the server initiate the disconnect**. The server always owns the link and can always terminate it. The client saying "please disconnect" is a polite request, not a termination.
