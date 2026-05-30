# Lifecycle-silence ⇄ transport reconciliation (server-side)

- **Date:** 2026-05-30
- **Status:** Approved (design)
- **Fixes:** I338 (lifecycle-silence timeout fires `Server.disconnections` without tearing down the GATT link, corrupting downstream stream framing)
- **Related:** I201 (iOS has no client-disconnect callback — wontfix), I207 (Android cannot force-disconnect remote centrals — wontfix), I202 (iOS `cancelPeripheralConnection` unreliable — wontfix), I017 (peer-silence timeout defaults), I337 (cross-stream identifier mismatch — fixed; unmasked this bug)

## Problem

When the `LifecycleServer` heartbeat-silence timer fires for a connected client,
bluey emits the client's address on `Server.disconnections` and clears its
internal bookkeeping — **without tearing down the underlying GATT link** (it
can't; see constraints). The link stays up, the peer keeps writing, and when its
heartbeats resume bluey re-emits `peerConnections` for the same client. A
consumer that brackets per-connection stream state (frame decoders, reassembly
buffers) on these two streams tears its decoder down on the phantom disconnect
and rebuilds it against bytes from the *middle* of a frame on the phantom
reconnect — corrupting the stream and discarding throughput on every recovery.

Confirmed mechanism (verified in code):
- `LifecycleServer._resetTimer` arms a `Timer` whose expiry calls
  `onClientGone(clientAddress)` after emitting `ClientLifecycleTimeoutEvent`.
- `BlueyServer` wires `onClientGone` to `_handleClientDisconnected` — **the same
  handler used for real platform disconnects** — which emits `disconnections`,
  clears `_identifiedPeerClientAddresses`, and touches **nothing** at the
  platform layer.
- So both stream edges fire from a peer-protocol event while the transport link
  is untouched. (Surfaced after I337 made the consumer's address bookkeeping
  faithful; pre-I337 the mismatch silently suppressed the teardown.)

The trigger is routine: any peer whose Dart isolate pauses longer than the
silence timeout (GC, plugin-channel stalls, app backgrounding) looks
"disconnected" even though its link is fine.

## Constraints (these shape the whole design)

1. **The heartbeat stays as-is, and its timeout is configurable.** Confirmed:
   `peerSilenceTimeout` (peer/client side) and `lifecycleInterval` (server side,
   default 10 s). Apps tune it. We do not change detection.
2. **A server cannot force a central off the link.** Android
   `BluetoothGattServer.cancelConnection` does not reliably disconnect a
   remote-initiated central (I207); iOS `CBPeripheralManager` has no per-central
   disconnect (I202). The only Android lever is closing the whole server. So
   "force a real GATT disconnect on silence" is not achievable — the doc's
   originally-preferred fix is rejected.
3. **iOS has no native client-disconnect callback (I201).** On iOS-server,
   heartbeat silence is the *only* disconnect signal. So we cannot simply stop
   treating silence as a disconnect — that would blind iOS to disconnects.
4. **A client *can* always disconnect its own outgoing link.** This asymmetry is
   the lever the design uses.

## Core model

**Principle:** `Server.disconnections` emits from the *most authoritative
transport signal available on the server's platform.* One capability decides
which:

- **New capability `Capabilities.reportsCentralDisconnects`** — `true` on
  Android, `false` on iOS. "Does this platform deliver a reliable native
  disconnect callback for a central, or must I infer it from heartbeat silence?"

**Dis-conflate the two events that today share `_handleClientDisconnected`** —
that conflation is the root surface of the bug:

- `_handleClientDisconnected(clientAddress)` — wired to the **platform** disconnect
  callback (`centralDisconnections`) only. Emits `disconnections`, clears
  identification, removes the session (`_connectedClients`). Behavior unchanged; trigger narrowed.
- `_handleLifecycleSilence(clientAddress)` — **new**, wired to the lifecycle
  timer's `onClientGone`. Branches on the capability:
  - **`reportsCentralDisconnects == true` (Android — "authoritative"):** advisory
    only. Emit `ClientLifecycleTimeoutEvent`; do **not** touch `disconnections`,
    do **not** clear identification, do **not** evict. The platform callback
    remains the sole source of `disconnections`. A paused peer resumes
    seamlessly; the decoder is never torn down.
  - **`reportsCentralDisconnects == false` (iOS — "inferring"):** silence *is* the
    disconnect signal. Emit `disconnections` + clear identification (as today)
    **and** remove its session, so any return is rejected (no established
    session) and forced through a clean reconnect instead of a corrupting
    mid-stream resume — see *Eviction & session coherence*.

**Platform-awareness lives in `BlueyServer`** (the domain↔platform seam that
already knows capabilities). `LifecycleServer` stays platform-agnostic — it runs
the heartbeat/timer and fires `onClientGone` + the timeout event exactly as now.

**Scope: server-side only.** The mirror direction (a *client* detecting the
server went silent) already tears down for real via
`LifecycleClient.onServerUnreachable → connection.disconnect()`, because a client
can drop its own link. Untouched.

## Data flow

**iOS-server (inferring) — peer pauses then resumes (the repro):**
1. Heartbeats stop → silence timer fires → `_handleLifecycleSilence`.
2. `reportsCentralDisconnects == false` → emit `ClientLifecycleTimeoutEvent` +
   `disconnections(clientAddress)`, clear identification, **remove the session**
   (`_connectedClients.remove`). Consumer tears down its decoder; no bytes are
   flowing (peer paused).
3. Peer resumes → first request (heartbeat or app write) hits `BlueyServer`'s
   chokepoint → no established session → answered with the reserved ATT status,
   not dispatched.
4. Client's bluey layer translates that status → clean `disconnect()`. App's
   existing reconnect logic runs.
5. Fresh connection → `centralConnections` (re-establishes the session) → next
   heartbeat re-identifies → `peerConnections`. Consumer builds a fresh decoder on a
   frame-aligned stream. No corruption.

**iOS-server — peer truly drops:** silence fires → as step 2. Peer never returns
→ no resumed request arrives, so the rejection never fires and no state lingers. `disconnections` was correct.

**Android-server (authoritative) — peer pauses then resumes:**
1. Heartbeats stop → silence timer fires → `_handleLifecycleSilence`.
2. `reportsCentralDisconnects == true` → emit `ClientLifecycleTimeoutEvent` only.
   No `disconnections`, identification intact, no eviction.
3. Peer resumes → heartbeats continue; decoder never torn down; stream aligned.

**Android-server — peer truly drops:** platform fires
`onConnectionStateChange(DISCONNECTED)` → `centralDisconnections` →
`_handleClientDisconnected` → `disconnections`. Unchanged. (Silence advisory may
fire first if silence beats the supervision timeout — a heads-up, not a
disconnect.)

**Platform-pair coverage.** The branch keys on the *server's*
`reportsCentralDisconnects`, not on the client's platform, and the client side
(send heartbeats; on the reserved status, self-disconnect) is uniform Dart logic.
So all four pairings reduce to the two paths above: **Android-server**
(Android↔Android and iOS→Android) takes the authoritative path; **iOS-server**
(iOS↔iOS and Android→iOS) takes the inferring path. Same-platform *bidirectional*
setups still face the orthogonal shared-link trap (Android: I208; iOS:
`cross-platform-quirks.md`) — out of scope here; neither fixed nor regressed.

Eviction is a special case of one rule, not its own bookkeeping:

> **The server services read/write requests only within an *established session*.
> A request from a client it has no session for is answered with the reserved ATT
> status and not dispatched — forcing a clean (re)connect.**

An "established session" = the client is present in `_connectedClients` via a
real connect/announce event (`centralConnections`). Eviction (the inferring-path
silence timeout) simply **removes the session** (`_connectedClients.remove`,
clear identification) — the resumed write then finds no session and is rejected.
So there is **no separate `_evicted` set** (it would need bounding/expiry, and
expiry could reopen the hole); the absence of a session *is* the eviction state,
and it also subsumes the "stale connection from before a server restart" case.

**Server chokepoint.** `BlueyServer`'s read and write listeners check for an
established session *before* dispatch. No session → respond with the reserved ATT
status and return (`_lifecycle.handleWriteRequest` not run, app not forwarded
to). Note this requires **removing the "establish from an unknown heartbeat"
behavior** in `_trackPeerClient` on the inferring path: a heartbeat from a client
with no session must reject, not silently re-create the client and re-emit
`peerConnections` (that re-creation is the corruption path this fix closes).

**Client translation.** bluey's error-translation layer (which already preserves
the raw ATT status byte post-I091) maps the reserved status to a
connection-fatal condition: `BlueyConnection` initiates its own `disconnect()`
and surfaces `DisconnectedException(reason: evictedByServer)`. Handled at the
connection layer, so it's uniform whether the status lands on a `LifecycleClient`
heartbeat write or an app data write. **The app sees a normal disconnect** and
reconnects via existing logic; it never learns "eviction" exists.

### Precise establishment ordering (no grace window)

For the rule above to be safe, a *legitimate* fresh client must already have a
session by the time its first request is serviced — deterministically, not via a
timing window. Both a benign "first contact" and a dangerous "stale mid-stream"
client present identically (a request from a client not in `_connectedClients`),
so the discriminator must be enforced at the source:

1. **Native invariant — "announce before forward."** The native layer never hands
   a request to Dart for a central it hasn't already announced via
   `onCentralConnected`. Because both are emitted from the same serial callback
   queue (CBPeripheralManager queue / Android GATT callback), announcing first
   and forwarding second means Dart receives them in that order — establishment
   is processed before the request by construction. (iOS already calls
   `trackCentralIfNeeded` inside `didReceiveWrite`; the invariant makes it run
   *before* the forward.)
2. **Reset "announced" state on server (re)init.** The stale-restart case breaks
   the invariant only because the native `centrals` map's "already announced"
   notion survives a Dart-server recreation, so it won't re-announce a central
   the *new* Dart server never heard of. On `BlueyServer` init, the native side
   clears its per-central announced-flags, so each surviving central is
   re-announced on its next interaction. No replay race.
3. **Dart reject** of a genuinely-unestablished request (reserved status) is the
   safety net — with (1)+(2) it should essentially never fire for a live central.

This is precise because the ordering is an enforced native invariant on a serial
queue, not a Dart-side window. **Fallback if a platform can't guarantee (1):** a
per-central session epoch stamped on `onCentralConnected` and every request, so
Dart matches the epoch rather than arrival order — adopted only if the invariant
can't be met.

**Gating verification items** (confirm before/while planning):
- CBPeripheralManager and the Android GATT callbacks run on a single serial
  queue, and the announce (`trackCentralIfNeeded` / Android equivalent) runs
  *before* the request is forwarded.
- Flutter delivers sequential same-queue channel messages to Dart in order
  (relied-upon property; state it).
- Whether a recreated `BlueyServer` reuses the native manager (→ reset-on-init
  required) or gets a fresh one (→ no stale central; invariant holds trivially).
- **Client-side reserved-status delivery (all four configs):** both client
  platforms must surface an application-range (`0x80–0x9F`) ATT *write-response*
  status faithfully to Dart so the eviction handshake's client leg fires. The
  carry path already exists — iOS preserves the numeric byte post-I091; Android
  routes it via `statusFailedError(op, status)` →
  `GattOperationStatusFailedException(status)` → `GattOperationFailedException(status)`.
  Residual to confirm: the OS actually delivers a `0x80–0x9F` code on a write
  response rather than masking/normalizing it (low risk; iOS handled, Android
  generally passes through). If a platform masks it, the eviction status moves to
  the heartbeat-write path only (the `LifecycleClient` can treat any heartbeat
  write failure on a session it believes live as an evict-and-reconnect trigger).

## Reserved protocol constants & collision-safety

- The reserved status is one code in the ATT application range `0x80–0x9F` (e.g.
  `0x80`), named (`kLifecycleEvictionStatus`) and documented next to the existing
  reserved lifecycle constants (control-service UUID, heartbeat-characteristic
  UUID, `version|marker|senderId` wire format).
- Guard: `GattResponseStatus` exposes only standard ATT errors (`0x01–0x0F`)
  today, so an app *cannot* emit an application-range code through bluey's API —
  no collision is possible. A comment on the enum records that if it is ever
  widened to allow application-range statuses, this reserved value is excluded.
  That invariant — not the prose docs — is the real guard.

## Public API surface

All additive or bug-fix; nothing renamed.

- `Capabilities.reportsCentralDisconnects` — new read-only field (Android `true`,
  iOS `false`). Informational; most consumers ignore it.
- `disconnections` becomes a faithful transport projection on both platforms —
  **the behavior change**: Android no longer fires it on a mere heartbeat lull.
  A fix, but a changelog line, since a consumer leaning on the old
  phantom-disconnect now sees fewer, truthful disconnects.
- `ClientLifecycleTimeoutEvent` stays the public advisory "peer went
  heartbeat-silent." Docs gain: advisory-only on platforms with a native
  disconnect signal (no longer co-emitted with `disconnections`); on inferring
  platforms it accompanies a real `disconnections` + eviction.
- `DisconnectReason.evictedByServer` — new additive enum value, so a consumer can
  distinguish an eviction-driven reconnect from a link-loss one.
- `cross-platform-quirks.md` gains the documented divergence: a transient pause
  crossing the timeout resumes seamlessly on Android but forces a clean reconnect
  on iOS — both non-corrupting; the only visible difference is the iOS reconnect
  blip. Tunable via `peerSilenceTimeout`/`lifecycleInterval`.

## Design assumptions (on the record)

1. **Android `onConnectionStateChange(DISCONNECTED)` reliably reports genuine
   central disconnects.** The lifecycle silence timer is advisory-only on Android
   and is *not* a disconnect backstop. (I207's "may never fire" caveat is specific
   to server-initiated `cancelConnection`, which this design never relies on; the
   repro logs show the callback firing on every genuine disconnect.)
2. **`ClientLifecycleTimeoutEvent` is emit-only.** Verified: no `is`/listener
   branch in `bluey/lib` or `bluey/example/lib` — only a diagnostic test asserts
   it. So changing *what else* happens when it fires cannot break consumer logic.

## Testing

TDD throughout; domain layer ≥90%. `FakeBlueyPlatform` gains a
`reportsCentralDisconnects` toggle and the ability to assert the status returned
on a request.

1. **iOS / inferring (`false`):** silence fires → `disconnections` + identification
   cleared + advisory event + **session removed** from `_connectedClients`;
   resumed **read and write** from a session-less client → reserved ATT status,
   not forwarded, lifecycle handler not run; fresh `centralConnections` →
   session re-established → re-identify → `peerConnections` re-emits.
2. **Android / authoritative (`true`):** silence fires → advisory event only, **no**
   `disconnections`, identification intact, session intact in
   `_connectedClients`; real platform disconnect → `disconnections` via
   `_handleClientDisconnected`; heartbeat resumes after a silence fire → timer
   re-arms, no disruption.
3. **Client-side translation:** GATT op failing with the reserved status →
   `BlueyConnection` self-disconnects + `DisconnectedException(evictedByServer)` —
   verified for a heartbeat write and an app data write.
4. **Session coherence:** a request from a client with no established session is
   rejected with the reserved status (not silently re-tracked via
   `_trackPeerClient`); and a fresh client's `centralConnections` is processed
   before its first request is serviced (establishment precedes dispatch — the
   "announce before forward" invariant).
5. **Headline regression (I338 contract):** on the inferring path, a
   silence-then-resume cannot continue mid-stream — the resumed request is
   rejected (forcing reconnect), not processed. Fails today.

**Existing tests to update:** `bluey_server_test.dart` and
`connection/lifecycle_events_test.dart` assert the old unconditional "silence →
`disconnections`"; split them by capability.

**Out of unit scope, gating before close:** real-device dogfood (gossip_chat)
confirming the iOS eviction→reconnect yields frame-aligned reassembly on
hardware — the design's load-bearing real-world claim.

## Out of scope

- Changing the heartbeat detection mechanism or its configurable timeouts.
- Any iOS active-probe / subscription-state corroboration to reduce the false-
  positive *window* (a paused peer still gets a clean reconnect; we don't try to
  suppress the reconnect itself on iOS). Could be a later refinement.
- Renumbering the I338 backlog entry (it sits in the `I300–I399` DDD band per the
  ID-allocation scheme; a both-platform domain bug would renumber out of it —
  flagged, not actioned here).

## Phase 0 findings (2026-05-30)

### 0.1 — Native callback queue & "announce before forward"

**iOS — HOLDS.**

`CBPeripheralManager` is created with `queue: nil` (`PeripheralManagerImpl.init`,
line 57), which means CoreBluetooth delivers all callbacks on the **main thread**
(Apple's documented nil-queue behavior). The impl uses a single `PeripheralManagerDelegate`
(a serial single-thread context), so all callbacks are serialized.

In both `didReceiveRead` (line 537) and `didReceiveWrite` (line 567):
`trackCentralIfNeeded(request.central)` (which calls `flutterApi.onCentralConnected`
when the central is new) is invoked **before** the request is forwarded.

- `didReceiveRead`: announce call at line 537
  (`trackCentralIfNeeded(request.central)`), forward call at line 555
  (`flutterApi.onReadRequest(request:)`).
- `didReceiveWrite`: announce call at line 567
  (`trackCentralIfNeeded(firstRequest.central)`), forward call at line 590
  (`flutterApi.onWriteRequest(request:)`).

Both are synchronous sequential calls on the same main-thread context.
Announce-before-forward holds trivially.

**Android — DOES NOT HOLD as an in-callback invariant; race exists.**

Android's `BluetoothGattServerCallback` methods run on binder threads (not a
single serial queue). `onConnectionStateChange` (which emits `onCentralConnected`,
line 701) and `onCharacteristicWriteRequest` (line 836) are independent binder
callbacks. The connect announce is dispatched to the main thread via
`handler.post { flutterApi.onCentralConnected(...) }` (line 701–703); the write
request is also dispatched to the main thread via `handler.post { flutterApi.onWriteRequest(...) }` (line 881–883). Because both are `handler.post`
from potentially different binder threads, **a write request arriving on a binder
thread can be posted to the main looper ahead of a connect that was also recently
posted**. The write handler does **not** announce the central itself (no
`connectedCentrals[deviceId]` check or equivalent `trackCentralIfNeeded` in the
write callback). Arrival order at the main looper is binder-thread-race-dependent.

**Design implication:** The "announce-before-forward" invariant holds naturally on
iOS, but not on Android. On Android, a write can reach Dart before the connect
event in a race window. The epoch fallback described in the design ("per-central
session epoch stamped on `onCentralConnected` and every request, so Dart matches
the epoch rather than arrival order") is needed to make the session-gate safe on
Android — or the write handler must be modified to announce first before posting
the forward (mirroring the iOS `trackCentralIfNeeded` pattern). The latter is the
simpler fix (no epoch field on the wire) and should be evaluated in Stage 2.

### 0.2 — Flutter cross-channel ordering

Each `BlueyFlutterApi` method (both platforms) is registered on a distinct
`BasicMessageChannel` keyed by a per-method channel name of the form
`dev.flutter.pigeon.<package>.BlueyFlutterApi.<method><suffix>`.

Android (`bluey_android/lib/src/messages.g.dart`):
- `onCentralConnected` → channel `dev.flutter.pigeon.bluey_android.BlueyFlutterApi.onCentralConnected`
- `onWriteRequest` → channel `dev.flutter.pigeon.bluey_android.BlueyFlutterApi.onWriteRequest`

iOS (`bluey_ios/lib/src/messages.g.dart`):
- `onCentralConnected` → channel `dev.flutter.pigeon.bluey_ios.BlueyFlutterApi.onCentralConnected`
- `onWriteRequest` → channel `dev.flutter.pigeon.bluey_ios.BlueyFlutterApi.onWriteRequest`

These are **separate channels** on the same `BinaryMessenger`. Flutter's
`BinaryMessenger` is backed by a single platform-message queue on the main thread
(messages are dispatched in arrival order to the Dart isolate). Therefore: if the
native side posts both calls from the same thread in order (connect then write),
Flutter delivers them to Dart in that order — the single queue serializes them.
This property is **not documented in the Pigeon/Flutter API surface** (no official
guarantee is written), but it is the relied-upon property of the implementation
that makes the serial-queue pattern on iOS sufficient. On Android the guarantee
only holds if both `handler.post` calls come from the same execution context in
the correct order — which the race in 0.1 may violate.

**Design implication:** The cross-channel ordering guarantee is a relied-upon
property of Flutter's main-thread message dispatch, not an explicit contract.
It is safe to rely on for iOS (single-thread native delivery). On Android, the
announcement-before-forward fix (posting both from the same binder-thread context
before any `handler.post`, or using an explicit announce inside the write
callback) is necessary to make the ordering reliable without the epoch fallback.

### 0.3 — Server-recreation native-manager reuse

**Android — native `GattServer` is REUSED across `BlueyServer` recreations.**

`BlueyPlugin.kt` creates exactly one `GattServer` instance at plugin attach time
(line 90–94: `gattServer = GattServer(context, bluetoothManager, flutterApi)`).
When `Bluey.server()` is called a second time (`bluey.dart` line 859:
`return BlueyServer(_platform, _eventBus, ...)`), a new Dart `BlueyServer` is
constructed, but the underlying Kotlin `GattServer` object is the same singleton
held by `BlueyPlugin`. The `GattServer` is only replaced when the plugin is
detached and re-attached.

`closeServer` (called from `BlueyServer.dispose()` at `bluey_server.dart` line
833: `await _platform.closeServer()`) calls `gattServer?.cleanup()` (plugin line
666), which clears `connectedCentrals`, `centralMtus`, `subscriptions`,
`pendingReadRequests`, `pendingWriteRequests`, and `characteristicByHandle` (lines
551–562 of `GattServer.kt`), and also sets `gattServer = null` (line 551),
causing the next `addService` call to re-open the GATT server via
`ensureServerOpen()`. So `cleanup()` resets the `connectedCentrals` map (the
"announced" state) — **but only if `closeServer` (i.e., `BlueyServer.dispose()`)
is called between recreations.**

If `BlueyServer` is invalidated via adapter cycle (I333 path) rather than
explicit `dispose()`, or if a second `bluey.server()` call is made without
disposing the first, the `GattServer.connectedCentrals` map from the old server
**survives** and the new Dart `BlueyServer` inherits stale "already announced"
state.

**iOS — `CBPeripheralManager` is REUSED; `centrals` map IS reset on `closeServer`.**

`PeripheralManagerImpl` is created once in `BlueyIosPlugin` (not shown in
inspection, but `PeripheralManagerImpl.init` at line 55 creates the
`CBPeripheralManager` with `queue: nil`). `closeServer` (line 370) calls
`centrals.removeAll()` (line 399), fully clearing the announced state.
Same caveat: only if `closeServer` is called.

**Design implication:** Stage 2 must add a "reset announced-state on server
(re)init" step. Specifically, when a new `BlueyServer` is created (or when
`closeServer` is called), the native `centrals`/`connectedCentrals` map must be
cleared so each surviving central is re-announced on its next interaction.
`closeServer` already does this on both platforms, so the invariant holds as long
as `dispose()` is called between recreations — but the I333 adapter-cycle path
must be verified to call `closeServer` (or the reset must be moved to a dedicated
`resetServerState()` call triggered on `BlueyServer` construction). This is a
required Stage 2 task.

### 0.4 — Client-side application-range status delivery

**Android — carry path EXISTS and is complete.**

`ConnectionManager.kt` `onCharacteristicWrite` (lines 812–825): when
`status != BluetoothGatt.GATT_SUCCESS`, it calls `statusFailedError("Write",
status)` (line 821), which emits a `FlutterError` with code `"gatt-status-failed"`
and `details = status` (the raw int). The `statusFailedError` helper is defined at
lines 643–648. This reaches Dart as `GattOperationStatusFailedException(status)`
via the existing error-translation layer. The raw status int (including any value
in `0x80–0x9F`) is preserved without masking.

**iOS — carry path EXISTS and is complete.**

`CentralManagerImpl.swift` `didWriteValueForCharacteristic` (line 804): any
`NSError` is translated via `nsError.toPigeonError()` (line 810). The
`NSError+Pigeon.swift` extension (line 17): for `CBATTErrorDomain` errors, emits
`PigeonError(code: "gatt-status-failed", message: ..., details: self.code)` where
`self.code` is the numeric ATT status byte. Non-`CBATTErrorDomain` errors fall
through to `"bluey-unknown"` — but `CBATTErrorDomain` is the domain for write
responses, so the carry path is correct for application-range ATT status codes.

**Design implication:** The carry path exists on both platforms. The residual
question — whether the OS actually delivers a `0x80–0x9F` ATT write-response
status code to the app rather than normalizing it — is explicitly deferred to
empirical confirmation (as stated in the design spec). No code changes are needed
to establish the carry path itself.
