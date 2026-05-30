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
  identification, clears eviction state. Behavior unchanged; trigger narrowed.
- `_handleLifecycleSilence(clientAddress)` — **new**, wired to the lifecycle
  timer's `onClientGone`. Branches on the capability:
  - **`reportsCentralDisconnects == true` (Android — "authoritative"):** advisory
    only. Emit `ClientLifecycleTimeoutEvent`; do **not** touch `disconnections`,
    do **not** clear identification, do **not** evict. The platform callback
    remains the sole source of `disconnections`. A paused peer resumes
    seamlessly; the decoder is never torn down.
  - **`reportsCentralDisconnects == false` (iOS — "inferring"):** silence *is* the
    disconnect signal. Emit `disconnections` + clear identification (as today)
    **and** arm eviction for that client, so any return is forced through a clean
    reconnect instead of a corrupting mid-stream resume.

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
   `disconnections(clientAddress)`, clear identification, add to `_evicted`.
   Consumer tears down its decoder; no bytes are flowing (peer paused).
3. Peer resumes → first request (heartbeat or app write) hits `BlueyServer`'s
   chokepoint → in `_evicted` → answered with the reserved ATT status, not
   dispatched.
4. Client's bluey layer translates that status → clean `disconnect()`. App's
   existing reconnect logic runs.
5. Fresh connection → `centralConnections` (clears `_evicted`) → next heartbeat
   re-identifies → `peerConnections`. Consumer builds a fresh decoder on a
   frame-aligned stream. No corruption.

**iOS-server — peer truly drops:** silence fires → as step 2. Peer never returns
→ eviction never triggers; the entry ages out. `disconnections` was correct.

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

## Eviction handshake

**State:** `BlueyServer` holds an `_evicted` set of `ClientAddress`, armed only on
the inferring path (in `_handleLifecycleSilence` when capability is `false`).

**Server chokepoint:** `BlueyServer`'s read and write request listeners check
`_evicted` *before* dispatch. A request from an evicted client is answered with
the **reserved ATT status** and returned — `_lifecycle.handleWriteRequest` is not
run, the app is not forwarded to. Catches the first request after resume (read or
write), so the stray-byte window is one request wide.

**Client translation:** bluey's error-translation layer (which already preserves
the raw ATT status byte post-I091) maps the reserved status to a
connection-fatal condition: `BlueyConnection` initiates its own `disconnect()`
and surfaces `DisconnectedException(reason: evictedByServer)`. Handled at the
connection layer, so it's uniform whether the status lands on a `LifecycleClient`
heartbeat write or an app data write. **The app sees a normal disconnect** and
reconnects via existing logic; it never learns "eviction" exists.

**Eviction-state lifecycle:**
- Cleared on fresh reconnect: the `centralConnections` listener removes the
  address from `_evicted`. Straggler requests on the old link before teardown
  completes still hit the chokepoint and are re-rejected — correct.
- Cleared on a real platform disconnect (`_handleClientDisconnected`) too — belt
  and suspenders (Android never arms eviction).
- Bounded: a client evicted and never returning (truly-gone on iOS) would linger;
  the set is capped (drop-oldest) or entries expire after a few heartbeat
  intervals, so it can't grow unbounded.

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
   cleared + advisory event + client in `_evicted`; resumed **read and write** from
   an evicted client → reserved ATT status, not forwarded, lifecycle handler not
   run; fresh `centralConnections` → `_evicted` cleared → re-identify →
   `peerConnections` re-emits.
2. **Android / authoritative (`true`):** silence fires → advisory event only, **no**
   `disconnections`, identification intact, not evicted, still in
   `_connectedClients`; real platform disconnect → `disconnections` via
   `_handleClientDisconnected`; heartbeat resumes after a silence fire → timer
   re-arms, no disruption.
3. **Client-side translation:** GATT op failing with the reserved status →
   `BlueyConnection` self-disconnects + `DisconnectedException(evictedByServer)` —
   verified for a heartbeat write and an app data write.
4. **Bounded `_evicted`:** many evicted-never-returning clients → set stays within
   its cap/expiry.
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
