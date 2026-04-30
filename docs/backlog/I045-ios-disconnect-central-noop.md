---
id: I045
title: iOS `disconnectCentral` returns success without disconnecting the central
category: bug
severity: medium
platform: ios
status: fixed
last_verified: 2026-04-30
fixed_in: d015870
related: [I207]
---

## Symptom

`server.disconnectCentral(centralId)` on iOS resolves successfully and the central is removed from the server's local `centrals` and `subscribedCentrals` tracking. The actual BLE link remains connected at the OS level. The central can continue reading, writing, and receiving notifications — the server just no longer tracks it. From the central's perspective, nothing happened.

The consumer of the Server API gets a successful Future, treats the central as gone, and may free associated resources. Subsequent operations from that central appear as "ghost" interactions from an unknown peer.

## Location

`bluey_ios/ios/Classes/PeripheralManagerImpl.swift:176-189`.

## Root cause

CoreBluetooth's `CBPeripheralManager` provides no method to terminate an active central connection. Apple's design treats peripheral-side connection lifecycle as the central's responsibility; the only tools the peripheral has are `removeAllServices()` and `stopAdvertising()`, neither of which disconnects an existing link.

The current implementation hides this limitation behind a successful return value, masking platform behaviour.

## Notes

Three viable fix paths:

1. **Throw `UnsupportedOperationException('disconnectCentral', 'ios')`.** Honest. Caller catches and uses the lifecycle disconnect command instead (which is best-effort but at least signals intent).
2. **Add `Capabilities.canForceDisconnectRemoteCentral: false` for iOS** and have the cross-platform `Server.disconnectCentral` check the capability before delegating. The capability flag also belongs on Android (see I207) — neither platform genuinely supports it.
3. **Send the lifecycle disconnect command (0x00 to heartbeat char) via notify, then mark the client locally as gone.** Best-effort but at least communicates intent if the central is a Bluey client.

Recommended: combine (2) and (3) — capability flag plus a "soft disconnect" cooperative protocol via the existing lifecycle channel.

External references:
- Apple [`CBPeripheralManager`](https://developer.apple.com/documentation/corebluetooth/cbperipheralmanager) — no force-disconnect method exists.
- [Apple Developer Forums thread #93060](https://developer.apple.com/forums/thread/93060) confirming the platform limitation.
- I207 (Android equivalent, marked wontfix) — consider whether I045 should also be wontfix or if the cooperative fallback is worth implementing.

**Followup resolved 2026-04-30**: rather than adding a
`canForceDisconnectRemoteCentral` flag, `Client.disconnect()` and
`BlueyPlatform.disconnectCentral` were removed entirely. Neither
supported platform can reliably force-disconnect in the BLE topology
Bluey uses (centrals always initiate); a flag that is `false` on every
platform would gate a method whose only honest behavior is `throw`.
Server consumers needing force-disconnect must close the entire
server; cooperative disconnect via the lifecycle protocol remains
future work.
