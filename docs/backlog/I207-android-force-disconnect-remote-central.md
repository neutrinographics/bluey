---
id: I207
title: Android cannot force-disconnect remote centrals
category: limitation
severity: low
platform: android
status: wontfix
last_verified: 2026-04-23
---

## Rationale

`BluetoothGattServer.cancelConnection(device)` only works for connections initiated by the GATT server itself. It does not reliably disconnect connections initiated by remote centrals (e.g., iOS connecting to an Android server).

When an iOS client connects to an Android server and the Android side wants to kick it:

- `cancelConnection(device)` may not trigger a disconnection.
- `onConnectionStateChange(STATE_DISCONNECTED)` may never fire.
- The only reliable option is to close the GATT server entirely, which will eventually cause the connection to time out on the client side.

## Current mitigation

For Bluey-to-Bluey communication, the server uses the lifecycle control service's disconnect command protocol, where the client writes "disconnect command" and the server initiates the termination from its side. Server-initiated disconnects are honored.

For non-Bluey clients, the server app must close the entire GATT server to force-disconnect any particular client.

## Decision

Wontfix at the OS level — this is an Android/Bluetooth-stack behavior.

## Notes

Compounded by iOS's `cancelPeripheralConnection` also being unreliable (I202). Combined effect: neither side can unilaterally force a hard disconnect; both depend on the remote peer honoring a soft-disconnect request.
