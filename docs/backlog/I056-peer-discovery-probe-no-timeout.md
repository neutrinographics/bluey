---
id: I056
title: PeerDiscovery probe-connect uses platform default timeout (Android 30s, iOS infinite)
category: bug
severity: medium
platform: domain
status: open
last_verified: 2026-04-26
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

Pass an explicit short timeout (3 seconds is a reasonable default for a probe; the device either responds quickly or gets skipped).

```dart
final config = const platform.PlatformConnectConfig(
  timeoutMs: 3000,
  mtu: null,
);
```

If the connect throws `GattOperationTimeoutException` after 3 seconds, the probe loop already catches and skips. No further changes needed.

Consider exposing this as a parameter on `Bluey.discoverPeers` for power users who want to tune it.
