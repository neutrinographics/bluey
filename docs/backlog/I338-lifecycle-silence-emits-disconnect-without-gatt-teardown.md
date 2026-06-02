---
id: I338
title: Lifecycle-silence timeout fires `Server.disconnections` without tearing down the GATT link, corrupting downstream stream framing
category: bug
severity: high
platform: both
status: open
last_verified: 2026-06-02
related: [I017, I201, I202, I207, I337, I340]
---

> **Status note (2026-06-02).** Android half (Stage 1) is fixed in HEAD
> via PR #35 (`2a90fd1`). The iOS half took a different path than the
> original Stage 2 eviction plan: Pattern B (presence-subscription
> disconnect detection) is implemented on the
> `i338-disconnect-via-presence` branch. Real-device dogfood is **PASSED**
> across the role matrix: iOS-server detects disconnects via
> `didUnsubscribeFrom(presence)` on all four loss modes (BT-off,
> command-line kill, on-device close, out-of-range via the supervision
> timeout) with clean reconnect (no Codex-P1 loop); Android-server detects
> via its native `onConnectionStateChange` (pre-existing path, unchanged).
> The eviction machinery (Stage 2) is retained **dormant** behind
> `reportsCentralDisconnects == false` as a re-enable-able fallback — its
> eventual removal is tracked in [I340](I340-remove-dormant-silence-eviction-machinery.md).
> Tracked as `open` until the branch merges.

## Resolution

### Android (Stage 1 — shipped in PR #35 / `2a90fd1`)

Added `Capabilities.reportsCentralDisconnects` (Android `true`, iOS
`false` at the time). `BlueyServer` dis-conflates the two events that
previously shared `_handleClientDisconnected`: a new
`_handleLifecycleSilence` branches on the capability. On Android
(authoritative — a native `onConnectionStateChange` disconnect callback
exists), heartbeat silence is **advisory only**: it emits
`ClientLifecycleTimeoutEvent` and does **not** touch `disconnections`,
clear identification, or evict. The native callback remains the sole
source of `disconnections`. A paused peer resumes seamlessly; the decoder
is never torn down. This closes the Android half: a heartbeat lull no
longer produces a phantom disconnect.

### iOS (Pattern B — branch `i338-disconnect-via-presence`; pending merge)

The eviction handshake originally sketched as Option A/Stage 2 (silence →
evict session → force-reconnect via `0x80` ATT status) gave iOS a
real-ish disconnect signal at the cost of a reconnect blip on every long
pause. Pattern B replaces that with a **genuine native disconnect signal**
using a dedicated presence notify characteristic
(`b1e70005-0000-1000-8000-00805f9b34fb`) on the lifecycle control service.

**Mechanism.** A Bluey client subscribes to the presence characteristic
on connect and never voluntarily unsubscribes while connected.
`peripheralManager(_:central:didUnsubscribeFrom:)` on that specific
characteristic is treated as the authoritative client-disconnect signal —
it fires promptly on graceful disconnect and after the BLE
link-supervision timeout on ungraceful loss. The server removes the
central and fires `onCentralDisconnected`, which propagates to
`Server.disconnections`. This flips `Capabilities.iOS.reportsCentralDisconnects`
to `true`, so the `_handleLifecycleSilence` branch now treats silence as
**advisory on iOS too**: no session eviction, no `disconnections` emission.

**Why a dedicated characteristic?** A client can toggle notifications on
data characteristics while staying connected. Using a data-characteristic
`didUnsubscribe` callback would produce false-positive disconnects. The
dedicated presence characteristic — never voluntarily unsubscribed from
while live — is unambiguous.

**Codex-P1 reconnect loop resolved.** The eviction path (Stages 2–3)
cleared the central on a *silence* event while the link was still live.
When the peer reconnected, the server saw a "new" central and re-announced
it — triggering a reconnect loop in clients that relied on a stable
`ServerId` across the pause. Pattern B clears the central only on the real
disconnect signal, so a reconnect on the same link is impossible; the
central is only cleared when the link is actually gone.

**Eviction code is NOT deleted — it is dormant.** The `_handleLifecycleSilence`
eviction branch (heartbeat silence → evict → `0x80` ATT status → force
reconnect) remains in `LifecycleServer` but is gated behind
`Capabilities.reportsCentralDisconnects == false`. With Pattern B live,
iOS reports `true`, so the branch never runs. If the presence mechanism
proves unreliable in the field (a real loss fails to fire
`didUnsubscribeFrom(presence)` before the supervision timeout), flipping
the capability flag re-enables the eviction handshake without any code
changes.

**Empirical residual (real-device dogfood, pending).** The presence
mechanism relies on CoreBluetooth cleaning up subscriptions on link
teardown for every genuine loss. This has been consistent across iOS
11–18. What is not yet confirmed on hardware for this specific
characteristic: that `didUnsubscribeFrom(presenceChar)` fires reliably on
ungraceful loss within the supervision-timeout window (expected: ~30 s).
The gossip_chat dogfood run confirming both graceful and ungraceful
disconnect paths is the load-bearing real-world check and is still
outstanding.

**Net effect.** Both platforms are now non-corrupting with **no reconnect
blip**: a paused peer resumes seamlessly on both Android and iOS — no
`disconnections` event, no decoder teardown. The consumer-facing behavior
is documented in `bluey/docs/cross-platform-quirks.md` ("Heartbeat silence
is advisory on both platforms"). Spec:
`docs/superpowers/specs/2026-05-30-lifecycle-silence-transport-reconciliation-design.md`.

## Original report (pre-fix)

## Symptom

When the `LifecycleServer`'s heartbeat-silence timer fires for a connected
client, bluey emits the client's address on `Server.disconnections` and
removes its internal bookkeeping — **but does not actually disconnect the
underlying GATT link**. The platform connection stays alive; the remote
peer's central stack continues to deliver `WriteRequest`s to the server,
which now believes the client is gone.

For consumers that maintain per-peer stream state on top of the GATT link
(framing decoders, JSON reassemblers, application-level keepalives), the
phantom-disconnect is destructive in two ways simultaneously:

1. **Stream-state teardown without a stream boundary.** The consumer tears
   down its decoder on the `disconnections` event, expecting that the byte
   stream has ended. It hasn't. Whatever bytes the remote was mid-sending
   when the timer fired never reach the consumer (they hit `writeRequests`,
   look up the now-deleted address-to-NodeId mapping, and are silently
   dropped — see consumer pattern below).
2. **Resync against a misaligned stream.** When bluey eventually re-emits
   `peerConnections` for the same client (the next heartbeat arrives over
   the still-open GATT link), the consumer creates a fresh decoder. That
   decoder is fed bytes from the *middle* of a frame, interprets four
   random bytes as a 4-byte length prefix, and proceeds to parse garbage
   as a message. Recovery requires skipping forward until a valid-looking
   length lands on an actual frame boundary — typically hundreds of bytes
   of throughput discarded, and the cycle recurs on the next mid-frame
   re-alignment.

Reproduced 2026-05-30 in the `gossip_chat` dogfood app between a Pixel 6a
(Android peripheral) and an iPhone (iOS central). After a brief stall on
the iOS main isolate that paused heartbeat writes for >30 s, Android's
lifecycle layer timed the iOS client out:

```
[BLUEY-LIB] [WARN ] bluey.server.lifecycle: client gone clientId=50:A2:C1:9D:DE:B3
[BLUEY-EV]          [Lifecycle] Client 50:A2:C1 timed out (heartbeat silence)
[BLUEY-LIB] [INFO ] bluey.server: central disconnected clientId=50:A2:C1:9D:DE:B3
[BLUEY-EV]          [Server] Client disconnected: 50:A2:C1
```

Two seconds later iOS's heartbeat resumed and re-identified — the
underlying GATT link was untouched throughout. iOS's log over the entire
window contains **zero** disconnect events; CoreBluetooth never noticed
anything happened:

```
[BLUEY-EV] [Server] Client connected: 50:A2:C1            ← no mtu=, no platform reconnect
[BLUEY-LIB] [INFO ] bluey.server: central identified as Bluey peer
                                    clientId=50:A2:C1:9D:DE:B3
                                    senderId=88c71a8a-...
```

Four seconds later the consumer's frame decoder began choking on bytes it
had no boundary for:

```
[ERROR] Peer sync error: type=messageCorrupted
        msg=Malformed gossip message ... FormatException: Unexpected character (at character 760)
        ...,48,53,45,51,48,84,48,48,58,48,51,58,50,54,46,57,50,51,56,57,52,34,125]}]}GS
                                                                                    ^
[BLUEY][WARNING] frame decoder recovered from corruption; discarded 405 bytes
```

The `...}]}GS` tail is the closing brackets of a valid JSON message body
followed by two bytes of a *next* message that the decoder ate because
its length prefix had been read from misaligned bytes. After recovery
the decoder kept re-desynchronizing on subsequent chunked bursts, with
recoveries firing every few seconds for the next ~22 s (405, 68, 446,
438, 2645, 446, 438 bytes discarded). Throughout, SWIM continued to
exchange pings successfully — gossip never agreed the peer was gone,
only bluey did.

## Root cause

`LifecycleServer._resetTimer()` arms a per-client `Timer` that, on expiry,
calls the injected `onClientGone(clientAddress)` callback
(`bluey/lib/src/gatt_server/lifecycle_server.dart:356–371`):

```dart
state.timer = Timer(interval, () {
  _logger.log(BlueyLogLevel.warn, 'bluey.server.lifecycle', 'client gone',
              data: {'clientId': clientAddress.toString()});
  _clients.remove(clientAddress);
  _events?.emit(ClientLifecycleTimeoutEvent(clientAddress: clientAddress,
                                            source: 'LifecycleServer'));
  onClientGone(clientAddress);
});
```

`BlueyServer` wires `onClientGone` to `_handleClientDisconnected`
(`bluey/lib/src/gatt_server/bluey_server.dart:115`), which adds to
`_disconnectionsController` (`bluey_server.dart:919`):

```dart
// Always emit on the disconnections stream -- even for untracked clients
// (e.g., stale connections from before a server restart).
_disconnectionsController.add(clientAddress);
```

Nowhere in this chain does anything call into the platform layer to close
the GATT link. The same `_handleClientDisconnected` runs for real
platform-level disconnects (BluetoothGattServerCallback /
peripheralManager:central:didUnsubscribeFromCharacteristic-equivalents),
which is correct — but for the lifecycle-silence path it produces an
event the consumer cannot distinguish from a real disconnect while the
link silently remains up.

## Why this is a bluey bug

The `Server` API documents `disconnections` as:

> Emits the [ClientAddress] of a client when it disconnects from this
> peripheral.

— and `peerConnections` correspondingly as the entry edge. Consumers
that hold any per-connection state (mailboxes, encryption nonces, frame
decoders, MTU caches) require these two streams to be a faithful
projection of GATT-level connection lifetime. They aren't, today: the
lifecycle silence path injects a fake "disconnect → connect" pair into
the streams while the actual link state never changed. Any consumer that
relies on stream boundaries to bracket reassembly state will corrupt
under this scenario.

The lifecycle layer's job is to detect dead peers. A dead peer should not
still hold a live ATT link. Today bluey detects-but-doesn't-act: it
informs the consumer but leaves the platform connection in place,
allowing the remote (which doesn't know its heartbeats stopped arriving)
to continue burning bandwidth on a server that has just told its
consumer the client is gone.

There is no API surface that lets a consumer tell apart "lifecycle
silence disconnect" from "GATT disconnect." A workaround inside the
consumer (suppress decoder teardown on `disconnections` and trust some
other signal) is not possible against the current contract.

## Proposed fix

### A. Force a real GATT disconnect when lifecycle silence times out (preferred)

When the silence Timer fires, tear down the platform connection before
emitting on `disconnections`:

```dart
state.timer = Timer(interval, () {
  _logger.log(...);
  _clients.remove(clientAddress);
  _events?.emit(ClientLifecycleTimeoutEvent(...));
  // Close the underlying GATT link so the remote sees a real disconnect
  // and both sides re-establish with aligned stream framing on reconnect.
  onClientGone(clientAddress);
});
```

— where `BlueyServer` wires `onClientGone` to a handler that does the
platform-level cancel (Android: `BluetoothGattServer.cancelConnection`;
iOS: `CBPeripheralManager` has no per-central cancel, but stopping
advertising / dropping the subscription is the closest available
mechanism — see "Out of scope" below) **before** emitting on
`_disconnectionsController`.

This makes `disconnections` a faithful projection of GATT-level
disconnects again: every emission corresponds to a link that is actually
gone, whether the cause was the platform reporting a disconnect or the
lifecycle layer deciding the peer was silent and pulling the plug. The
consumer never sees a phantom disconnect with bytes still arriving.

iOS half: `CBPeripheralManager` exposes no `cancelPeripheralConnection`
analogue. The pragmatic fallback there is for the lifecycle silence path
to stop responding to writes from that central (return an error status
on its next ATT operation) and let CoreBluetooth tear the link down on
the remote side. Either way, the contract on the Dart side is the same:
`disconnections` does not fire until the link is actually being shut
down.

### B. Add a separate `lifecycleSilences` stream; do not emit on `disconnections`

Leave `disconnections` strictly for platform-level disconnect callbacks.
Add:

```dart
abstract class Server {
  /// Emits when [LifecycleServer] decides a connected client has gone
  /// silent (heartbeat silence beyond [peerSilenceTimeout]) but the
  /// underlying GATT link is still up. Consumers that care about
  /// peer-protocol liveness can subscribe here; consumers that
  /// bracket stream state on [disconnections] are unaffected.
  Stream<ClientAddress> get lifecycleSilences;
  ...
}
```

This is non-breaking and correctly separates the two signals. The
downside is the zombie GATT connection persists — the remote keeps
writing, the server keeps accepting bytes for a client its consumer
believes is gone, and bandwidth is wasted until the platform notices
the link is dead (which on iOS can take many seconds to minutes).

A is preferable because the zombie-connection cost is real and silently
borne by every consumer. B is a useful adjunct (a consumer that wants
heartbeat-presence as a separate signal from transport-presence can opt
in), but B alone doesn't fix the framing-corruption case.

### Out of scope

- Defining what platform-level "force disconnect" means on iOS. The
  pragmatic approach (stop responding / let CoreBluetooth time the link
  out from the remote side) may be acceptable here, but the right
  design needs its own decision — possibly via a `CBPeripheralManager`
  state probe that has not been audited for this purpose. This issue is
  flagging the contract break; the iOS implementation work can be a
  sub-task.
- Whether `peerConnections` should also be reset on the silence event,
  or only on the next heartbeat. The current "re-identification" path
  (which re-emits on `peerConnections` when a heartbeat arrives from a
  client whose lifecycle was timed out) already exists and is fine for
  Option A — the consumer will see a clean connect-then-disconnect-
  then-reconnect sequence with a real platform gap between them.

## Why severity is high

- Affects both platforms (Android primary, iOS via the same Dart-side
  emission path). The issue is in the platform-agnostic `LifecycleServer`
  /`BlueyServer` wiring.
- Triggers on any heartbeat-silence event, not on an exceptional code
  path. Heartbeat silence happens routinely whenever a peer's app pauses
  the Dart main isolate longer than `peerSilenceTimeout` (default 30 s):
  GC pauses, plugin-channel stalls, keyboard XPC reconnects, user
  switching apps briefly. These are common, not edge cases.
- Cannot be worked around in consumer code without depending on
  implementation details that the public API does not expose. The
  consumer has no way to ask "did the GATT link actually close, or did
  bluey's lifecycle layer just decide it should have?"
- Silently corrupts the byte stream of every consumer that does frame
  reassembly on the data path — a near-universal pattern for any
  protocol that sends messages larger than a single ATT MTU.

## Notes

- The consumer pattern that surfaces this most quickly is the
  `peerConnections` ⇄ `disconnections` bracket as used by
  `gossip_bluey`: a `FrameDecoder` is allocated on the former and
  removed on the latter. The decoder's recovery loop (scan-forward
  until a length prefix yields valid JSON) does work — it just
  discards hundreds of bytes of throughput per event and recurs
  whenever the stream re-misaligns. The consumer can be made more
  resilient (e.g., persist the decoder across nominal disconnects)
  but only by trusting an out-of-band signal the API does not provide.
- Read alongside I017 (peer-silence timeout defaults) and I337
  (cross-stream identifier mismatch) — three issues, same root surface:
  the lifecycle layer's interaction with `Server`'s connection-edge
  streams is under-specified.
- This bug was masked by I337 until 2026-05-29. Pre-I337 the
  `_clientAddressToNodeId` lookup in the gossip_bluey consumer
  silently missed even for real disconnects (because `Client.id` and
  the `disconnections` clientId were different strings), so the
  decoder was never torn down at all and the framing happened to ride
  through silently — at the cost of a leaking peer registry. After
  I337 the bookkeeping is correct, the decoder gets torn down
  faithfully on every `disconnections` event, and this issue surfaces.
