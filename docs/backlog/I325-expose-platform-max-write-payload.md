---
id: I325
title: Expose `Connection.maxWritePayload(withResponse: bool)`; relocate `mtu` / `requestMtu` to `AndroidConnectionExtensions`
category: enhancement
severity: medium
platform: both
status: open
last_verified: 2026-05-05
related: [I326]
---

## Expanded scope (2026-05-05)

Original ticket only proposed adding `maxWritePayload`. After design discussion, the scope expanded to also **relocate `Connection.mtu` and `Connection.requestMtu` to `AndroidConnectionExtensions`**, because:

- iOS's CoreBluetooth does not expose the GATT MTU as a number via any public API; only `maximumWriteValueLength(for:)` is surfaced.
- Today bluey's iOS `_mtu` is hardcoded to 23 — a Dart-side fiction.
- The "throw `UnsupportedCapabilityException` on iOS" pattern for `requestMtu` is strictly worse than "compile-time absent on iOS" via the platform-extension pattern that already houses `bond`, `setPhy`, `requestConnectionPriority`, etc.

Final API after this ticket:

```dart
abstract class Connection {
  // cross-platform
  Future<int> maxWritePayload({required bool withResponse});
  // ... no mtu, no requestMtu

  AndroidConnectionExtensions? get android;
  IosConnectionExtensions? get ios;
}

abstract class AndroidConnectionExtensions {
  Mtu get mtu;
  Future<Mtu> requestMtu(Mtu desired);
  // ... existing bond / setPhy / etc.
}
```

A separate ticket I326 covers wiring Android's `onMtuChanged` event into the cached `mtu` value so it stays current after spontaneous renegotiation.

## Symptom

Bluey's `Connection.mtu` getter returns the GATT MTU, which on Android is the right value to derive chunk sizes from (`mtu - 3` for ATT-write payload). On iOS it is **misleading**: `_mtu` is initialized to 23 and never updated, because iOS's CoreBluetooth does not surface the negotiated MTU to apps via any callback bluey listens for.

The platform plumbing already exposes the correct per-write payload limit through `peripheral.maximumWriteValueLength(for: type)` — this is the iOS-recommended way to size writes. `bluey_ios/ios/Classes/CentralManagerImpl.swift:382` implements `getMaximumWriteLength(deviceId:withResponse:)`, but the value is **not plumbed up** to `bluey_platform_interface` or to the Dart `Connection` abstraction.

Consumers (e.g. `gossip_bluey`) end up reading `connection.mtu.value`, getting 23, computing `chunkSize = 20` (default ATT write payload), and writing tiny chunks. On a real iOS connection that has auto-negotiated a 185-byte ATT MTU, this means **~10× as many writes** as the link could carry.

In a long-lived connection sending unacknowledged writes, the higher write count proportionally raises the probability that *some* write is silently dropped. A single dropped write corrupts the framing layer's byte stream — and even though framing-layer recovery is something the consumer should also build, exposing the right chunk size is the *upstream* half of the fix.

## Reproduction

In a `gossip_bluey`-style consumer on iOS, log the chunk size it derives from `connection.mtu`:

```dart
final caps = bluey.capabilities;
try {
  final desired = bluey.Mtu(caps.maxMtu, capabilities: caps);
  final negotiated = await peerConnection.connection.requestMtu(desired);
  print('iOS: requested ${desired.value}, negotiated ${negotiated.value}');
} on UnsupportedCapabilityException {
  print('iOS: cannot request MTU; mtu.value = ${peerConnection.connection.mtu.value}');
}
```

Output on iOS: `cannot request MTU; mtu.value = 23` — even though the actual link is running at MTU 185+ (visible in `peripheral.maximumWriteValueLength(for: .withoutResponse)` if accessed through a private channel).

## Proposed API

Add a getter on `Connection`:

```dart
abstract class Connection {
  // ...

  /// Largest single ATT write payload the platform will accept for this
  /// connection. Use this — not `mtu - 3` — when sizing chunked writes.
  ///
  /// On Android: derived from the negotiated GATT MTU (`mtu - 3`).
  /// On iOS: returned by `CBPeripheral.maximumWriteValueLength(for:)`,
  /// which is the only API CoreBluetooth exposes for this; `mtu`
  /// itself is not surfaced by iOS to apps.
  ///
  /// [withResponse] selects the type: writes-with-response have a
  /// slightly smaller maximum than writes-without-response on some
  /// platforms.
  int maxWritePayload({required bool withResponse});
}
```

Or as a method (signature shown). Implementation:

- **Android** (`bluey_android`): `mtu - 3`. Cached value updated in `requestMtu`.
- **iOS** (`bluey_ios`): forward to existing `getMaximumWriteLength(deviceId:, withResponse:)` in `CentralManagerImpl.swift`. The platform-pigeon plumbing for this method already exists; add the Dart-side surface.
- **Fakes / in-memory**: synthetic value (e.g. `withResponse ? 20 : 100`).

## Why this matters

- **Performance**: 5–10× throughput improvement on iOS for chunked writes (typical 200-byte gossip message goes from ~10 writes to ~2 writes).
- **Reliability**: proportionally fewer write opportunities → proportionally fewer chances for a silent drop on writes-without-response.
- **Cleaner consumer code**: today consumers either compute the wrong number from `mtu` and accept the perf hit, or hardcode a magic constant ("100 bytes is probably safe on iOS"). Both are bad.

## Notes

- This is the **upstream half** of a two-part fix; the consumer (e.g. `gossip_bluey`) should also build framing-level recovery so a single write-drop doesn't corrupt the stream forever. That's their problem, but exposing the right write size cuts the drop frequency by an order of magnitude.
- Consider deprecating the `Connection.mtu` getter on iOS or documenting its 23-always behavior — it's a footgun for any consumer that thinks they can derive a chunk size from it.
- The existing `Connection.requestMtu` API doesn't need to change; on iOS it'll continue to throw `UnsupportedCapabilityException`. Apps just stop relying on it.
