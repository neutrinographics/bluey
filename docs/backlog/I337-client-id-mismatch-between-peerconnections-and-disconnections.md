---
id: I337
title: `Client.id` is not the same identifier `Server.disconnections` emits, breaking cross-stream bookkeeping
category: bug
severity: high
platform: both
status: resolved
last_verified: 2026-05-29
related: []
---

## Resolution (2026-05-29)

Fixed on branch `i337-transport-address-value-objects` by replacing the lossy
`String → UUID` synthesis behind `Device.id` / `Client.id` with per-context
value objects — `DeviceAddress` (Discovery/Connection) and `ClientAddress`
(GATT-Server) — that hold the raw platform string natively. `Client.id : UUID`
is gone; `Client.address : ClientAddress` and `Server.disconnections :
Stream<ClientAddress>` now emit the **same** value by construction, so the
cross-stream bridge is correct and type-checked. All three lossy coercion sites
(two algorithms) are deleted. Regression test:
`bluey/test/gatt_server/i337_stream_bridge_test.dart` (Android MAC, iOS UUID,
and the `peerConnections` path).

**Platform-scope correction:** the mismatch reproduced **Android-only**. The
native side already lowercases the iOS identifier for both `PlatformDevice.id`
and `PlatformCentral.id`, so on iOS the old `Client.id` re-normalized an
already-normalized string to the same value. The original report's
"platform: both" claim did not hold for the iOS half. The fix is still
cross-platform (it removes the synthesis and unifies the types everywhere).

See `docs/superpowers/specs/2026-05-29-transport-address-value-objects-design.md`
and `docs/superpowers/plans/2026-05-29-transport-address-value-objects.md`.

## Symptom

A consumer that wants to track which BLE peer is currently connected must reconcile two streams from `Server`:

- `peerConnections` — emits `PeerClient`. The consumer keys its bookkeeping by `peerClient.client.id.toString()`.
- `disconnections` — emits a raw `String` clientId.

These two values are not the same string. The consumer's map lookups fail, the disconnect handler silently bails, and the stale entry persists in the consumer's registry until something else evicts it.

Reproduced 2026-05-29 in the `gossip_chat` dogfood app between a Pixel 6a (Android) and an iPhone (iOS). After iOS's Dart main isolate hung for ~15 seconds while opening the QR-scan keyboard, Android's bluey lifecycle-heartbeat timeout fired:

```
[BLUEY-LIB] [WARN] bluey.server.lifecycle: client gone clientId=46:F9:31:94:D7:F6
[BLUEY-EV] [Lifecycle] Client 46:F9:31... timed out (heartbeat silence)
[BLUEY-LIB] [INFO] bluey.server: central disconnected clientId=46:F9:31:94:D7:F6
[BLUEY-EV] [Server] Client disconnected: 46:F9:31...
```

The gossip_chat application-level `Peer disconnected` event never followed. When iOS recovered and reconnected ~5 s later:

```
[BLUEY-EV] [Server] Client connected: 46:F9:31...
[BLUEY-LIB] [INFO] bluey.server: central identified as Bluey peer
                                    clientId=46:F9:31:94:D7:F6
                                    senderId=dcee33dc-985a-48f5-87a9-670804c2c0de
[BLUEY] duplicate connection for NodeId(dcee33dc...) arrived as
        ConnectionRole.peripheral; dropping
[BLUEY] Peer disconnected: dcee33dc
```

The legitimate reconnect was rejected as a duplicate because the registry still held the stale entry from the never-cleaned-up disconnect. The duplicate-drop then tore down the new connection, leaving both devices with no peer.

Same shape of failure on iOS — the rotation of the platform identifier through `UUID()` normalization (lowercase, hyphens stripped) means iOS reconnects also fail to clean up under the same conditions.

## Root cause

`BlueyClient.id` (`bluey/lib/src/gatt_server/bluey_server.dart:1037–1053`) transforms the raw platform `clientId` (MAC on Android, `CBPeer.identifier` UUID string on iOS) before exposing it as `Client.id`:

```dart
@override
UUID get id {
  // iOS branch: normalize hyphens + case
  if (_platformId.length == 36 && _platformId.contains('-')) {
    return UUID(_platformId);
  }
  // Android branch: ASCII-encode the raw clientId as bytes, pad/truncate to
  // 16 bytes, hex-encode, wrap in a UUID.
  final bytes = _platformId.codeUnits;
  final padded = List<int>.filled(16, 0);
  for (var i = 0; i < bytes.length && i < 16; i++) {
    padded[i] = bytes[i];
  }
  final hex = padded.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return UUID(hex);
}
```

Concretely, for the Android MAC `"46:F9:31:94:D7:F6"` (17 chars, no hyphens, hits the second branch), the loop truncates to the first 16 ASCII bytes and the hex encoding yields:

```
client.id.toString() == "34363a46393a33313a39343a44373a46"
```

Meanwhile `disconnections.add(clientId)` at `bluey_server.dart:914` emits the raw platform string `"46:F9:31:94:D7:F6"` directly. No normalization, no encoding. Consumers cannot use `Client.id.toString()` as a map key and look up by the raw `disconnections` clientId — the two strings are unrelated.

The same divergence occurs on iOS for any clientId whose hyphenation or casing differs from `UUID`'s normalization output (which is lowercase, hyphens-stripped, 32 hex chars).

## Why this is a bluey bug

bluey's `Server` API is a producer/consumer surface for two streams that *describe the same underlying connections* — `peerConnections` says "this peer is here", `disconnections` says "this peer is gone". The only sensible consumer pattern is to key bookkeeping by some stable identifier emitted by both. The API as it stands fails that contract: the identifier projected through `Client.id` is not the same as the identifier emitted on `disconnections`.

There is no documented stable identifier the consumer can use without internal knowledge of the `BlueyClient.id` transformation. The only field that could be used — `BlueyClient._platformId` — is private.

## Proposed fix

Either:

### A. Expose the raw platform clientId on `Client` (preferred)

Add a public getter:

```dart
abstract class Client {
  /// Stable transport-level identifier — the same string emitted on
  /// [Server.disconnections]. Use this as a map key when bridging the
  /// `peerConnections` and `disconnections` streams.
  ///
  /// On Android this is the central's MAC address; on iOS it is the
  /// CBPeer.identifier UUID string. Format is platform-specific and
  /// opaque to consumers — never parse it.
  String get platformId;

  UUID get id;          // unchanged; still a normalized derived form
  int get mtu;
}
```

`BlueyClient` already stores `_platformId`; just promote it to public.

This is non-breaking (purely additive). Consumers can switch their map keys from `client.id.toString()` to `client.platformId` and the bridge between the two streams becomes correct by construction.

### B. Normalize `disconnections` to emit the same value `Client.id.toString()` returns

Apply the `BlueyClient.id` transformation before adding to `_disconnectionsController`. This is also non-breaking and keeps the `Client.id` abstraction. Slightly less ergonomic for consumers that already think of "the client id" as the raw platform value.

A is preferable because it exposes a stable transport-level handle that's directly meaningful for platform-level operations (e.g. `notifyTo`, future per-client disconnect APIs), and because parsing-out the original platform id from `Client.id`'s ASCII-hex encoding is impossible after truncation.

### Out of scope

- Changing what `Client.id` returns. The current `Client.id : UUID` shape is a convenient consumer-facing wrapper; the bug is the lack of a *stable, cross-stream* identifier, not the existence of the UUID wrapper.

## Why severity is high (not medium)

- Affects both platforms.
- Manifests on every clean disconnect — the consumer's bookkeeping leaks forever unless something else (process restart, explicit `port.disconnect(nodeId)` call) evicts it.
- Cannot be worked around without depending on the implementation detail of `BlueyClient.id`'s transformation, which is private and undocumented.
- Causes legitimate reconnects to be rejected as duplicates at higher application layers, leading to total loss of peer connectivity.

## Notes

- `gossip_bluey` has not yet applied a workaround. The consumer-side fix would replicate `BlueyClient.id`'s transformation in the disconnect handler — gross, brittle, and a strong signal the API needs the upstream fix.
- The Android branch of `BlueyClient.id` ASCII-encodes the MAC bytes (not the hex-decoded MAC), then truncates at 16 bytes. For typical MAC strings like `"46:F9:31:94:D7:F6"` (17 chars) one byte is silently dropped. So `Client.id` is not even a lossless representation of the platform clientId — adding to the case for exposing the raw value.
- Read alongside I333 (live-instance invalidation) and I335 (scanner onCancel) — these together form a triplet of "Server-side bookkeeping that consumers can't get right with the current API."
