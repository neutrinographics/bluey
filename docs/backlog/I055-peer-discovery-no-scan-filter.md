---
id: I055
title: PeerDiscovery scans without service filter; probes every nearby device
category: limitation
severity: medium
platform: domain
status: fixed
last_verified: 2026-05-01
fixed_in: 4abcba9
related: [I056, I057, I313]
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

Fixed in `4abcba9`.

**Client side:** `PeerDiscovery._collectCandidates` now uses
`serviceUuids: [lifecycle.controlServiceUuid]` instead of `const []`.
Probe time is O(matches) instead of O(nearby devices).

**Server side:** `Server.startAdvertising` gained a `bool peerDiscoverable
= false` parameter. When `true`, `BlueyServer` prepends the control UUID
to the advertised `serviceUuids` (with dedup against any user-supplied
listing). The original sketch in this entry suggested defaulting to
"on" — that turned out wrong-sized for Android: a 128-bit UUID consumes
~18 bytes from the 31-byte legacy advertising budget, and slipping the
control UUID into apps already at the limit would silently break them
with `ADVERTISE_FAILED_DATA_TOO_LARGE`. Default `false` makes the cost
explicit at the API.

**Follow-up filed as I313**: route the control UUID through Android's
scan-response slot (a separate 31-byte budget). Once that lands, the
default can flip to `true` safely without competing with the user's
primary AD content. Until then, callers opt in deliberately.

iOS handles the budget pressure gracefully via the overflow area —
foreground scans on other iOS devices that explicitly filter on the
control UUID still match — so the cost is mostly an Android concern.

**Privacy tradeoff acknowledged.** Opt-in `peerDiscoverable: true` does
expose a stable Bluey-using-app fingerprint to passive BLE scanners.
Privacy-sensitive deployments leave it `false` and either ship an OOB
ServerId discovery channel or use `Bluey.peer(knownId).connect()` with
out-of-band peer pairing.

External references:
- BLE Core Specification 5.4, Vol 3, Part C, §11: GAP modes and advertising data formats.
- Apple, [Advertising and Discoverability](https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetoothLE/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html) — overflow area discussion.
