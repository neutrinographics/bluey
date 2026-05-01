---
id: I056
title: PeerDiscovery probe-connect uses platform default timeout (Android 30s, iOS infinite)
category: bug
severity: medium
platform: domain
status: fixed
last_verified: 2026-05-01
fixed_in: 4abcba9
related: [I055]
---

## Symptom

During peer discovery, if any candidate device is unresponsive (BLE devices in deep-sleep state often are on first connect attempt), the probe's connect call waits for the platform's default timeout — ~30 seconds on Android (or ~10 seconds on Samsung), indefinitely on iOS. A single unresponsive candidate blocks all subsequent probes for the duration of its timeout.

For a discovery session with `scanTimeout: 5 seconds` and 10 candidates, one stuck candidate can stretch total discovery time to 35+ seconds — 7× the user-visible expected duration.

## Location

`bluey/lib/src/peer/peer_discovery.dart:115-120`.

```dart
Future<ServerId> _readServerIdRaw(String address) async {
  final config = const platform.PlatformConnectConfig(
    timeoutMs: null,        // <- relies on platform default
    mtu: null,
  );
  await _platform.connect(address, config);
  ...
}
```

## Root cause

The `timeoutMs: null` path defers to the platform's default. The default differs per platform and is unsuitable for throw-away probes.

## Notes

Fixed in `4abcba9`. `PeerDiscovery._readServerIdRaw` now passes
`PlatformConnectConfig.timeoutMs: probeTimeout.inMilliseconds`. The
default lives on `PeerDiscovery.defaultProbeTimeout` (3 s); exposed as
`probeTimeout` on `Bluey.discoverPeers`, `BlueyPeer.connect`, and the
internal `PeerDiscovery.discover` / `connectTo` for power users who
want to tune it. Probe-loop catch-and-skip behavior unchanged.

Sub-fix: `BlueyPeer.connect`'s `timeout` parameter was a no-op (passed
to `connectTo` which ignored it). Renamed to `probeTimeout` and now
threaded through to the platform connect — exactly what its dartdoc
already claimed it did. Breaking rename, but the parameter was dead
code, so no functional caller behavior changes.
