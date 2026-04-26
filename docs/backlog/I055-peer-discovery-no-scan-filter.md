---
id: I055
title: PeerDiscovery scans without service filter; probes every nearby device
category: limitation
severity: medium
platform: domain
status: open
last_verified: 2026-04-26
related: [I056, I057]
---

## Symptom

`bluey.discoverPeers()` and `BlueyPeer.connect()` both delegate to `PeerDiscovery._collectCandidates`, which scans with an empty `serviceUuids` list. Every BLE device in range becomes a candidate. Each candidate is then connect-probed sequentially in `_probeServerId` / `_readServerIdRaw` to read the serverId characteristic.

In a typical environment with 10-30 nearby BLE devices (offices, homes with smart-home gear, public spaces), peer discovery takes 20-60 seconds because the probe is O(n) sequential connect-disconnect cycles at ~1-2 seconds each.

## Location

`bluey/lib/src/peer/peer_discovery.dart:85-99`.

```dart
final scanConfig = platform.PlatformScanConfig(
  serviceUuids: const [],   // <- empty filter
  timeoutMs: timeout.inMilliseconds,
);
```

## Root cause

The Bluey server eagerly adds the control service (`b1e70001-0000-1000-8000-00805f9b34fb`) but does not advertise it. Even if it did advertise it, the discovery scan filter doesn't pass it through, so the OS-level scan doesn't filter on it.

## Notes

The control service UUID is the natural filter for peer discovery — it uniquely identifies a Bluey-protocol peer.

Two-part fix:

1. **Server side:** include the control service UUID in the advertising payload by default. This consumes 18 bytes (16 UUID + 2 header) from the 31-byte legacy advertising budget — non-trivial. On iOS, the OS automatically promotes 128-bit UUIDs to the overflow area when scanning is foreground, so it remains discoverable to other Bluey clients explicitly scanning for that UUID. On Android, it appears in the primary advertisement.
2. **Client side:** change `_collectCandidates` to filter by the control service UUID:

```dart
final scanConfig = platform.PlatformScanConfig(
  serviceUuids: [lifecycle.controlServiceUuid],
  timeoutMs: timeout.inMilliseconds,
);
```

Probe time becomes O(matches) rather than O(nearby devices).

**Privacy tradeoff.** Advertising the control service UUID exposes a stable Bluey-using-app fingerprint. For privacy-sensitive deployments (consumer apps where users don't want their app stack identifiable from a passive BLE scan), this is undesirable. Make the advertising of the control UUID a configurable option on `Server.startAdvertising`.

External references:
- BLE Core Specification 5.4, Vol 3, Part C, §11: GAP modes and advertising data formats.
- Apple, [Advertising and Discoverability](https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetoothLE/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html) — overflow area discussion.
