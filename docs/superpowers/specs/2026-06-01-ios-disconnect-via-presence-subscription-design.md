# iOS-server disconnect detection via a presence subscription (Pattern B)

- **Date:** 2026-06-01
- **Status:** Approved (design)
- **Supersedes (functionally):** the iOS/inferring half of the I338 eviction handshake (Stage 2–3) — *not by deletion*; the eviction code is left dormant behind the capability flag as a fallback.
- **Builds on:** I338 Stage 1 (`Capabilities.reportsCentralDisconnects` gate). Android (authoritative) behavior is unchanged.
- **Related:** I201 (iOS no peripheral-side disconnect callback — the root constraint), I203 (iOS address rotation), the Codex-P1 review finding on PR #36, I339/I323 (separate, pre-existing).

## Problem

On an iOS GATT server there is **no peripheral-side client-disconnect callback (I201)**, so heartbeat *silence* was used as the only disconnect signal. The I338 work made silence on iOS remove the session and *evict* a resumed peer with a reserved ATT status, forcing a clean reconnect (to avoid the original I338 mid-stream-resume corruption). On hardware this exposed the **Codex-P1 loop**: the iOS native `centrals` map is never cleared on a disconnect (there's no callback to clear it), so a reconnecting central with the same `CBCentral.identifier` is never re-announced — its first heartbeat is re-evicted, over and over, until the identity finally rotates. The eviction *avoids corruption* but at the cost of an availability loop, plus significant machinery (reserved status, Pigeon, native gate, reset-on-init).

This design steps back and asks: given we now know *exactly* how iOS and Android behave, what's the cleanest pattern? The answer leans on an idiomatic iOS mechanism the original implementation deliberately avoided.

## Requirements (the contract — solution-independent)

1. **No mid-stream corruption.** Whenever the consumer's per-connection decoder is (re)bracketed (on `connections`/`peerConnections`/`disconnections`), it is at a frame boundary — never rebuilt mid-frame. *(The non-negotiable invariant — the original I338 bug.)*
2. **Detect genuine disconnects.** A peer that really leaves surfaces on `disconnections` so the consumer tears down.
3. **A pause must not corrupt.** A peer that merely paused (GC, backgrounding, isolate stall) and resumes ends up correct and non-corrupt.
4. **Converge / no loops.** After whatever the server does on silence, a returning peer reliably ends up cleanly connected. *(What the Codex-P1 loop violates.)*

Heartbeats are held as a fixed assumption for this design (revisit only if we wall).

## Decision: Pattern B — advisory silence + a real disconnect signal from a presence subscription

Give the iOS server a *real* disconnect signal, so silence stops being a disconnect inference and becomes a harmless advisory — making iOS behave like Android.

### Mechanism

1. **A dedicated presence notify characteristic** is added to the lifecycle control service (e.g. `b1e70005-…`, `canNotify: true`). Its sole purpose is connection-presence tracking.
2. **The client subscribes to it on connect** (in the peer-connect / `LifecycleClient.start` path) and **never voluntarily unsubscribes while connected.** The protocol guarantees this — so leaving the presence subscriber list can mean only one thing: the link dropped.
3. **iOS `didUnsubscribe(presenceChar)` → a disconnect:** the native iOS server removes the central from its `centrals` map and calls `onCentralDisconnected(centralId)` → the existing `centralDisconnections` stream → the existing `_handleClientDisconnected` → `disconnections` + session removal. *No new domain logic.* `didUnsubscribe` on any *other* (data) characteristic stays a no-op (preserving the false-positive protection the authors built — a client toggling data notifications must not be treated as gone).
4. **iOS `didSubscribe(presenceChar)` → connected:** already calls `trackCentralIfNeeded` → `onCentralConnected`. On a reconnect, because step 3 *cleared* the central on the prior disconnect, the central is no longer in `centrals`, so the subscribe **re-announces** and the session re-establishes.
5. **Flip `Capabilities.reportsCentralDisconnects` to `true` for iOS.** The iOS server now takes the authoritative path: `_handleLifecycleSilence` returns early → **silence is advisory (a no-op)**, never destructive. A pause → resume is seamless; the decoder is never torn down → no corruption.
6. **Heartbeats are retained** (they still carry the peer's `ServerId` for identification; harmless under advisory silence).
7. **The eviction machinery stays dormant** behind `reportsCentralDisconnects == false` — re-enable-able in one flag flip if hardware proves the signal unreliable.

### Why this resolves the Codex-P1 loop — and is robust to the identifier unknown

The loop existed because nothing cleared the iOS `centrals` map on disconnect, so a same-identity reconnect never re-announced. Pattern B **clears the central on the real disconnect signal (`didUnsubscribe`)**, so the reconnect's `didSubscribe` always re-announces — **independent of whether `CBCentral.identifier` is stable or rotates.** The identifier-stability question, which the eviction approach was hostage to, becomes moot.

### Why not the eviction handshake

It avoids corruption but: (a) produces the convergence loop unless paired with a fragile reconnect-distinguishing signal (the only clean candidate, `didSubscribe`, depends on the app subscribing to a data characteristic — not universal); (b) carries heavy machinery (reserved ATT status, Pigeon, native gate, reset); (c) costs a reconnect blip even in the happy path. Pattern B is simpler, idiomatic, and seamless. The eviction is kept as a dormant fallback rather than the primary path.

### The honest empirical bet

Pattern B rests on one platform fact: **a dropped iOS link fires `didUnsubscribe` for the subscribed presence characteristic** — promptly on a graceful disconnect, and after the BLE **link-supervision timeout** on an ungraceful loss (out of range / force-kill) — the same timeout-driven latency that drives Android's native callback. This is the established iOS-peripheral idiom for the missing disconnect callback, but it is the load-bearing bet:

- If reliable → Pattern B is clean; silence is a pure no-op; the eviction code is eventually deletable.
- If flaky (a real loss that *doesn't* fire `didUnsubscribe`) → that disconnect is missed (the session lingers). There is **no free runtime backstop**: a silence-driven disconnect can't distinguish a long pause from a missed-signal loss, and the only *non-corrupting* silence-disconnect is the eviction handshake. So the safety net is at the **code level** — re-enable the dormant eviction via the capability flag.

We do **not** hide this: the test suite makes it explicit (see TDD #6), and one dogfood run confirms reliability.

## The platform model (the key deliverable)

`FakeBlueyPlatform` gains a faithful, **parameterized** model of server-side connection behavior, so we TDD the domain against real OS semantics and adjust as hardware teaches us by changing *config*, not tests.

- **Raw signals:** `simulateCentralConnect/Disconnect`, `simulateSubscribe(centralId, char)` / `simulateUnsubscribe(centralId, char)` (presence vs data), `simulateHeartbeat(centralId)`, and the silence timer fired via `fakeAsync` `async.elapse(...)`.
- **Iteration knobs (the empirical unknowns as config):** `didUnsubscribeReliable: true|false`, `identifierStable: true|false`, plus the existing `reportsCentralDisconnects`.
- **Platform semantics encoded:** Android = native connect/disconnect that clears tracking; iOS = subscribe-announces / presence-unsubscribe-disconnects, sticky `centrals` (a same-identity reconnect re-announces *only because* the prior disconnect cleared it), no other native disconnect path.

**All timing is virtual.** Silence/supervision timeouts are tested by advancing a `fakeAsync` clock — never real `Future.delayed`/wall-clock waits.

## TDD shape

Domain-level, against the parameterized fake (same split as I338: domain green in CI; native confirmed by build + one dogfood). Red→green:

1. **iOS advisory silence** (`reportsCentralDisconnects: true`): connected+identified peer goes heartbeat-silent → **no** `disconnections`; session + identity retained.
2. **Disconnect via presence-unsubscribe:** `simulateUnsubscribe(presence)` → `disconnections` + session removed + central cleared from tracking. *(Red today — `didUnsubscribe` is inert.)*
3. **Data-unsubscribe is a no-op:** `simulateUnsubscribe(data)` → no disconnect.
4. **Reconnect recovery (Codex-P1 resolved):** connect → identify → presence-unsubscribe → reconnect (presence-subscribe) → clean re-establish. **Passes for both `identifierStable` values.**
5. **Pause → resume seamless:** heartbeats stop then resume on the same link → still connected, no re-identify, decoder never bracketed.
6. **`didUnsubscribeReliable: false`:** a real disconnect is **not** detected → session lingers. This test is the explicit, visible record of the empirical dependency (and where the dormant-eviction fallback is justified).
7. **Android regression:** existing authoritative-path tests stay green.
8. **Client subscribes to presence on connect:** the peer-connect path issues the presence subscription; the control service exposes the presence notify characteristic.

## Implementation footprint

- `bluey/lib/src/lifecycle.dart`: add the presence notify characteristic to `buildControlService` (+ its UUID constant).
- Client peer-connect path (`LifecycleClient.start` / `bluey_peer` / `bluey.dart`): subscribe to the presence characteristic on connect.
- `bluey_ios` native (`PeripheralManagerImpl.swift`): `didUnsubscribe(presence)` → remove from `centrals` + `flutterApi.onCentralDisconnected(...)`. Keep data-characteristic `didUnsubscribe` a no-op.
- `bluey_platform_interface` `Capabilities.iOS`: `reportsCentralDisconnects: true`.
- `FakeBlueyPlatform`: the parameterized model above.
- Update the Stage-1 iOS tests that asserted silence-evicts (they now assert advisory).
- Android native + the eviction code: untouched (dormant).

## Out of scope

- **Removing heartbeats entirely.** Under Pattern B heartbeats only carry identity; replacing that with a one-shot identity write on connect would let them go, but it's a much larger rework (Peer module, LifecycleClient/Server) and a separate, clearly-isolated follow-up — taken only once hardware confirms `didUnsubscribe` reliability.
- **Deleting the eviction code.** Kept dormant as the fallback; deletion is a later decision.
- **The silence-eviction dogfood test** (branch `i338-silence-eviction-test`) — separate; likely superseded by this design’s TDD coverage.

## Open question (hardware-confirm)

Does a real iOS link loss reliably fire `didUnsubscribe` for the subscribed presence characteristic, within the supervision-timeout window, across the loss modes (out-of-range, force-kill, BT toggle)? One dogfood run on the eventual implementation answers it; the parameterized model + dormant eviction cover us either way.
