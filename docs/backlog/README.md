# Bluey Backlog

A living index of every known bug, no-op stub, and unimplemented feature in the Bluey library.

This index supersedes the January 2026 historical docs now kept in [`../old/`](../old/) — `BUGS_ANALYSIS.md`, `ANDROID_IMPLEMENTATION_COMPARISON.md`, and `IOS_IMPLEMENTATION_COMPARISON.md`. Those files were written pre-Phase-2a and many of their findings are already fixed; they remain as historical context. Entries here link back to them via `historical_ref:` where relevant.

## Scope

An entry belongs here if any of these is true:

- **Bug** — code does the wrong thing or nothing when it should do something.
- **No-op stub** — an API is exposed but its implementation is empty or returns a hardcoded value.
- **Unimplemented feature** — a capability is missing entirely (no API, no native wiring).
- **Wontfix limitation** — a capability is impossible on a platform; recorded so it's not rediscovered.

A documented, worked-around workaround is not on its own a backlog entry. Only track it here if there's still unfinished work or a decision to revisit.

## Entry schema

Every entry file has YAML frontmatter followed by prose. Required fields:

```yaml
---
id: I001                          # globally unique, monotonically assigned
title: Short imperative title
category: bug | no-op | unimplemented | limitation
severity: critical | high | medium | low
platform: domain | android | ios | both | platform-interface
status: open | fixed | wontfix
last_verified: YYYY-MM-DD
fixed_in: <commit-sha>            # optional, only if status=fixed
historical_ref: BUGS-ANALYSIS-#7  # optional, link to predecessor doc
related: [I005, I012]             # optional
---
```

Prose sections (in this order, any may be omitted if empty):

- **Symptom** — user-observable effect.
- **Location** — current `file:line` reference(s).
- **Root cause** — why it happens.
- **Notes** — fix sketch, links to specs/plans, constraints.

## Status legend

| Status | Meaning |
|---|---|
| `open` | Still present in HEAD. Needs work. |
| `fixed` | Verified resolved in HEAD. Entry kept so we know the claim was tracked. |
| `wontfix` | Intentional — platform limit, out-of-scope, or superseded. |

## How to work with this index

- **Before starting work**, grep here for the affected subsystem. Don't start on a bug that's already been traced to a root cause in an existing entry without updating the entry.
- **When an entry is fixed**, don't delete it — set `status: fixed`, fill in `fixed_in`, and update `last_verified`.
- **When a new bug/stub/gap is discovered**, create a new numbered entry; don't reuse retired IDs.
- **Re-verify periodically**. Entries accumulate false certainty over time. Bulk re-verification against HEAD is a valid maintenance task.

## Suggested order of attack

Ordered by impact per hour, refreshed 2026-04-29 after Tier 3 was cleared and the iOS-cluster sweep closed I044 + I045. Treat as a recommendation, not a commitment — re-evaluate when circumstances change (user-visible bug reports, prioritized features, release targets, etc.).

### Where we are

Tiers 1–3 are cleared. The remaining backlog is Tier 4: opportunistic bundles, plus a long tail of low-severity stubs and limitations. The next coherent project of architectural significance is the **capabilities-matrix bundle**, which subsumes several open entries and is the recommended fix path for I310. Everything else is genuinely opportunistic — pick up when in nearby code or when a concrete consumer needs it.

### Tier 1 — Quick wins (sub-day each) — DONE

Tier 1 cleared. Done in this cycle:
~~I017~~ ([a352c17](#)),
~~I035 Stage A~~ ([cb1b24f](#)),
~~I009~~ ([a6bd217](#)),
~~I057~~ ([510278e](#)),
~~I067~~ ([8b02ccf](#)).

I035 Stage B (Pigeon plumbing for bond/PHY/conn-priority) remains open as a multi-day project — see I035 entry. The Stage A follow-up (domain-side capability gating in `BlueyConnection`) landed `ae76523` and unblocked Android-as-client manual testing.

### Tier 2 — Medium projects (multi-day, no breaking changes)

~~**I098** — Android `ConnectionManager` rewrite~~ ([051f415](#); 11 commits). Bundled I060 + I061 + I062 + I064 + concurrent-connect mutex into one coherent threading + disconnect-lifecycle pass. 15 new JVM unit tests (`ConnectionManagerLifecycleTest.kt`). Verified on real Android via stress tests.

~~**I003** — notification controllers never closed~~ ([f69dafa](#)). `BlueyConnection._cleanup()` now walks `_cachedServices` and disposes each. 3 new domain tests.

~~**I002** — GATT ops not gated by connection state~~ ([7da8795](#)). `_ensureConnected()` throws `DisconnectedException` from every public op on `BlueyConnection` / `BlueyRemoteCharacteristic` / `BlueyRemoteDescriptor`. 10 new domain tests.

~~**I082 + I086 (Android side)** — `notifyCharacteristic` concurrent-mutation safety~~ ([80ef2ed](#)). Defensive snapshot at iteration entry; binder-thread subscription mutations now go through `handler.post`. 3 new JVM tests. **iOS-side I086 remains open** (Tier 4, bundle with other iOS one-offs).

~~**I080** — `addService` / `startAdvertising` ordering~~ ([612d534](#) + [da80f52](#)). Platform-side: `pendingServiceCallback` is now a Map keyed by service UUID. Domain-side: `BlueyServer.startAdvertising` awaits in-flight `addService` futures. 1 new JVM test + 2 new Dart tests.

~~**I012** — server notification completion not tracked per central~~ ([aa588f1](#)). `pendingNotifications` per-central FIFO queue; `onNotificationSent` pops the head; 5 s timeout per send; `STATE_DISCONNECTED` and `cleanup()` drain. Pigeon contract stayed `Future<void>` (per-central observability not exposed). 8 new JVM tests.

**Tier 2 cleared.** Move on to Tier 3 — see below.

### Tier 3 — Major architectural rewrites (breaking; major-version bumps)

These rewrite portions of the public surface; plan as release events with a migration guide.

11. ~~**I088** — Pigeon GATT schema rewrite (handle-based identity).~~ ([73656b4](#); bundle `929e869..73656b4`). Drove I010 + I011 + I016 fixes. Handle-based identity threaded through every Pigeon GATT op.
12. ~~**I099** — Typed error translation rewrite.~~ ([6427cc8](#); bundle `0a72a42..6427cc8`). Drove I090 + I092. New `withErrorTranslation` helper consolidates the anti-corruption layer; `Bluey.errorStream` removed (breaking). 23 new tests.
13. ~~**I089 + I300 + I301** — Connection bounded-context refinement.~~ ([73656b4](#); bundle `929e869..73656b4`). Bundled with I088 into one major-version-bump release: composition over upgrade-in-place (`PeerConnection`), platform-tagged extensions (`connection.android` / `connection.ios`), value objects for connection parameters and MTU. I066 closed in the same bundle.

**Tier 3 cleared.**

### Tier 4 — Opportunistic (pick up when in nearby code)

Ordered by recommended sequence. Bundles preferred where the underlying concerns share architecture; one-offs land as small commits. Everything below is genuinely optional — there is no current production blocker in this list.

#### Recommended next bundle — Capabilities matrix (multi-day, Tier-3-shaped)

**I053 + I065 + I069 + I303 + I310 + I045-followup.** Expand the `Capabilities` matrix to cover every BLE-feature dimension (I053), make it load-bearing — domain-layer methods consult it before crossing the platform-interface seam (I065), parameterize `FakeBlueyPlatform` so tests can simulate any platform shape (I069), replace the iOS-detection heuristic with a precise platform-kind flag (I303), throw a typed `UnsupportedOperationException` when a capability flag is false instead of letting `UnsupportedError` fall through to `BlueyPlatformException(null)` (I310), and add the `canForceDisconnectRemoteCentral: false` flag so consumers can gate `Server.disconnectCentral` without try/catch (the I045 follow-up). I310 explicitly recommends this bundle as its preferred fix path. Estimate: 2–3 days. Worth a spec, similar to the I099 rewrite.

#### Smaller bundles (1–2 hours each)

- **Glossary + DDD docs** (I302) — add a glossary to CLAUDE.md documenting the Domain ↔ Platform-Interface vocabulary translation. ~1 hour. Best done alongside the capabilities bundle since both touch the bounded-context seam.
- **Server-API polish** (I058 + I059) — advertising mode dropped + `removeService` fire-and-forget. ~1–2 hours.
- **Peer-discovery polish** (I055 + I056) — scan filter + probe timeout. ~1–2 hours.
- **Diagnostic events** (I054 + I068) — emit dead `BlueyEvent` types + add lifecycle-protocol events. Bundle.
- **iOS NSError mapping cleanups** (I091 + I093) — unmapped `CBATTError` codes / `notFound` mapping. I091 was implicated in the `bluey-unknown` results from the 2026-04-29 stress-test session.

#### Remaining iOS one-offs

- **I046** — max-write-length plumbing. *Cross-platform; bundle with I034 (Android twin), not a true iOS one-off despite the cluster heading.*
- **I047** — batched ATT write response. *Needs real-hardware repro before any fix per the entry's verification plan; can't safely guess at the right behavior.*
- **I048** — iOS state restoration. *Multi-day plugin/AppDelegate/Info.plist work; not a one-off despite the cluster heading.*

#### Pure follow-ups (pick up only when concrete need surfaces)

- **I306** — non-Bluey iOS-client disconnect on Android-server. Peer-protocol case closed (`3041eca`); only raw-GATT iOS interop remains.
- **I308 + I309** — DDD seam refinement. Domain layer catches Flutter's `PlatformException` directly (I308) and imports `bluey_platform_interface` types directly (I309) instead of going through abstract repositories. Low severity; takes a multi-day refactor to address properly. Pick up only if a non-Flutter Dart consumer of the domain layer materializes.
- **I304** — peer-builder helper extraction. Low.

Everything else (the remaining 25+ open entries, mostly low-severity stubs and limitations on the index below) proceeds opportunistically — pick up related entries when you're already in the code for a higher-priority fix.

---

## Index

### Open — domain layer

| ID | Title | Severity |
|---|---|---|
| [I001](I001-disconnect-state-double-emission.md) | Disconnect state double-emission | medium |
| [I004](I004-mtu-not-synced-with-platform-callbacks.md) | MTU not synced with platform-initiated changes | medium |
| [I005](I005-async-init-without-error-handling.md) | Async initialization without error handling | medium |
| [I006](I006-mac-to-uuid-truncation.md) | BlueyCentral MAC → UUID truncation | medium |
| [I007](I007-connection-state-init-race.md) | Connection state init race (mitigated, not prevented) | low |
| [I008](I008-notification-subscription-race.md) | Notification subscription race (mitigated, not prevented) | low |
| [I054](I054-events-dart-dead-types.md) | Several `BlueyEvent` subtypes are defined but never emitted | low |
| [I055](I055-peer-discovery-no-scan-filter.md) | PeerDiscovery scans without service filter; probes every nearby device | medium |
| [I056](I056-peer-discovery-probe-no-timeout.md) | PeerDiscovery probe-connect uses platform default timeout | medium |
| [I058](I058-server-advertising-mode-dropped.md) | `BlueyServer.startAdvertising` drops user-supplied advertising mode | medium |
| [I059](I059-server-remove-service-fire-and-forget.md) | `BlueyServer.removeService` doesn't await the platform call | low |
| [I065](I065-capabilities-matrix-decorative.md) | `Capabilities` matrix is decorative; no production code consults it | medium |
| [I068](I068-event-bus-missing-lifecycle-events.md) | Lifecycle protocol state changes not emitted as `BlueyEvent`s | low |
| [I069](I069-fake-platform-capabilities-hardcoded.md) | `FakeBlueyPlatform.capabilities` hardcoded; no test coverage of capability gating | medium |
| [I072](I072-lifecycle-server-record-activity-race.md) | `LifecycleServer.recordActivity` races with timer cancellation | medium |
| [I075](I075-cached-services-race-with-invalidation.md) | `_cachedServices` race between `services()` and invalidation | medium |
| [I076](I076-handle-service-change-silent-swallow.md) | `_handleServiceChange` swallows exceptions silently | medium |

### Open — Android native

| ID | Title | Severity |
|---|---|---|
| [I013](I013-scan-failure-error-code-not-propagated.md) | Scan failure error code discarded | medium |
| [I014](I014-manufacturer-data-only-first-entry.md) | Manufacturer data only first entry returned | low |
| [I015](I015-gatt-server-close-order-on-engine-detach.md) | GATT server close order on engine detach | low |
| [I063](I063-android-late-callback-misroute-after-timeout.md) | Late GATT callback misrouted after app-level timeout | medium |
| [I081](I081-advertiser-concurrent-start.md) | Advertiser allows concurrent `startAdvertising` | medium |
| [I085](I085-cccd-malformed-bytes-silently-ignored.md) | CCCD write with malformed bytes silently ignored | medium |

### Open — Android GATT server stubs / no-ops

| ID | Title | Severity |
|---|---|---|
| [I022](I022-gatt-server-descriptor-read-no-dart-api.md) | Descriptor read auto-responded; no Dart API | medium |
| [I023](I023-gatt-server-notification-sent-no-tracking.md) | `onNotificationSent` not tracked for completion | medium |
| [I024](I024-gatt-server-mtu-change-not-propagated.md) | Server-side MTU change not propagated to Dart | medium |
| [I025](I025-gatt-server-phy-events-logging-only.md) | Server-side PHY update/read events are logging-only | low |
| [I306](I306-android-server-no-disconnect-on-ios-client-cancel.md) | Android server doesn't observe non-Bluey iOS client disconnect (peer-protocol case fixed; raw-GATT case remains, supervision-timeout-bound) | low |

### Open — Android connection-level stubs

| ID | Title | Severity |
|---|---|---|
| [I030](I030-android-bonding-stub.md) | Bonding API stubbed (hardcoded returns) | high |
| [I031](I031-android-phy-stub.md) | PHY API stubbed (hardcoded returns) | high |
| [I032](I032-android-connection-parameters-stub.md) | Connection parameters API stubbed (hardcoded returns) | high |
| [I033](I033-android-connection-priority-not-exposed.md) | Connection priority request not exposed | medium |
| [I034](I034-android-maximum-write-length-not-exposed.md) | Maximum write length query not exposed | medium |
| [I035](I035-android-bond-phy-conn-param-stubs.md) | Dart-side bonding/PHY/connection-parameter methods return silent success (umbrella for I030–I034) | high |

### Open — iOS stubs / no-ops / bugs

| ID | Title | Severity |
|---|---|---|
| [I040](I040-ios-notification-retry-on-ready.md) | `isReadyToUpdateSubscribers` does not retry failed notifications | medium |
| [I041](I041-ios-read-notification-race.md) | `didUpdateCharacteristicValue` conflates read response with notification | medium |
| [I042](I042-ios-services-cache-dead.md) | `services` cache dict is dead storage | low |
| [I043](I043-ios-no-retrieve-peripherals.md) | No `retrievePeripherals` / `retrieveConnectedPeripherals` API | medium |
| [I046](I046-ios-max-write-length-not-exposed.md) | `getMaximumWriteLength` implemented but not exposed via Pigeon | medium |
| [I047](I047-ios-pending-write-requests-batch.md) | `respondToWriteRequest` only responds to first of batched ATT requests | medium |
| [I048](I048-ios-no-state-restoration.md) | iOS managers initialized without restore identifier; state restoration disabled | medium |
| [I083](I083-ios-powered-off-no-state-clear.md) | `peripheralManagerDidUpdateState(.poweredOff)` doesn't clear state | medium |
| [I091](I091-ios-unmapped-cbatt-error-to-unknown.md) | Unmapped `CBATTError` codes silently become `bluey-unknown` | medium |
| [I093](I093-ios-notfound-maps-to-wrong-error.md) | `notFound` for unknown characteristic maps to `gatt-disconnected` | medium |
| [I310](I310-ios-unsupported-error-falls-through-as-platform-exception.md) | iOS adapter throws Dart `UnsupportedError` for capability-gated ops; surfaces as `BlueyPlatformException` with null code | medium |

### Open — cross-platform unimplemented features

| ID | Title | Severity |
|---|---|---|
| [I050](I050-prepared-write-flow-unimplemented.md) | Prepared-write (long-write) flow unimplemented | medium |
| [I051](I051-advertising-options-not-exposed.md) | Advertising options not exposed (TX power, mode, connectable) | medium |
| [I052](I052-scan-options-not-exposed.md) | Scan options not exposed (mode, RSSI filter, duplicates) | medium |
| [I053](I053-capabilities-matrix-incomplete.md) | `Capabilities` matrix incomplete | medium |
| [I084](I084-reconnect-loses-subscriptions.md) | Reconnected central loses subscriptions silently | medium |
| [I086](I086-remove-service-race-with-notify.md) | `removeService` races with in-flight notify fanout (iOS only; Android done in `80ef2ed`) | medium |
| [I094](I094-scanner-controller-never-closed.md) | Scanner broadcast controllers never closed (both platforms) | medium |
| [I095](I095-server-controllers-never-closed.md) | AndroidServer / IosServer broadcast controllers never closed | medium |

### Open — DDD / architectural refinement

| ID | Title | Severity |
|---|---|---|
| [I302](I302-ubiquitous-language-glossary.md) | Cross-context vocabulary lacks a glossary; Domain ↔ Platform seam silently translates terms | low |
| [I303](I303-capabilities-platform-kind-flag.md) | iOS-detection heuristic on `Connection.ios` should be a precise capability flag | low |
| [I304](I304-peer-builder-helper-extraction.md) | `_tryBuildPeerConnection` and `_BlueyPeer.connect` duplicate the LifecycleClient setup | low |
| [I308](I308-domain-catches-flutter-platform-exception.md) | Domain layer catches Flutter `PlatformException` directly (framework dependency leak) | low |
| [I309](I309-domain-imports-platform-interface-types-directly.md) | Domain imports `bluey_platform_interface` types directly instead of going through an abstract repository | low |
| [I311](I311-server-side-bypass-typed-translation.md) | Server-side methods (`notify`, `indicate`, `respondTo*`) bypass the I099 typed-translation helper | medium |

### Fixed — verified in HEAD

| ID | Title | Fixed in |
|---|---|---|
| [I020](I020-gatt-server-auto-respond-characteristic-write.md) | GATT server auto-respond on characteristic write | `3539a42` |
| [I021](I021-gatt-server-auto-respond-characteristic-read.md) | GATT server auto-respond on characteristic read | `3539a42` |
| [I070](I070-lifecycle-client-late-promise-callbacks.md) | LifecycleClient late promise callbacks fire after `stop()` | `136fa47` |
| [I073](I073-lifecycle-client-start-not-idempotent.md) | `LifecycleClient.start()` is not idempotent | `136fa47` |
| [I077](I077-lifecycle-client-disconnect-storm.md) | Client appears to toggle connected/disconnected during heartbeat activity | `0b97cc6` |
| [I078](I078-lifecycle-client-activity-drop-during-start.md) | `LifecycleClient.recordActivity()` silently drops signals during `start()` → interval-read window | `136fa47` |
| [I079](I079-lifecycle-heartbeat-starves-behind-long-user-ops.md) | LifecycleServer declares clients gone while holding their pending requests | `4206343` |
| [I096](I096-ios-nil-disconnect-error-to-unknown.md) | iOS `didDisconnectPeripheral` with `error: nil` produces `bluey-unknown` | `c145209` |
| [I097](I097-client-opslot-starves-heartbeat.md) | Client-side OpSlot starvation causes false-positive heartbeat failures | `8f8a5a9` |
| [I017](I017-peer-silence-timeout-defaults.md) | Default `peerSilenceTimeout` internally inconsistent (lib 20 s vs example 30 s); reconciled to 30 s | `a352c17` |
| [I009](I009-server-respond-leaks-internal-exception.md) | `BlueyServer.respondTo{Read,Write}` leaked platform-interface exception; translated to `ServerRespondFailedException` | `a6bd217` |
| [I057](I057-mac-to-uuid-coercion-duplicated.md) | MAC-to-UUID coercion duplicated; extracted `deviceIdToUuid` helper | `510278e` |
| [I067](I067-connection-state-linked-vs-ready.md) | `ConnectionState.connected` split into `linked` + `ready` (breaking) | `8b02ccf` |
| [I100](I100-pending-callbacks-not-cleaned-on-disconnect.md) | Pending callbacks not cleaned on disconnect | `8d210c3` (Phase 2a) |
| [I305](I305-example-bluey-badge-via-tryupgrade.md) | Example app lost its BLUEY badge after C.6; re-introduced via `bluey.tryUpgrade` | `d29fe75` |
| [I101](I101-android-pending-callback-collision.md) | Android pending callback collision | `8d210c3` (Phase 2a) |
| [I102](I102-connection-timeout-not-cancelled.md) | Connection timeout not cancelled on success | Phase 2a |
| [I103](I103-scan-timeout-double-emit.md) | Scan timeout fires after manual stop | Scanner refactor |
| [I064](I064-android-phase-2b-dead-legacy-maps.md) | Legacy pending-op maps in `ConnectionManager` are dead code | `3962e43` |
| [I062](I062-android-threading-violation-in-callbacks.md) | Threading violation: binder-thread mutation of main-thread maps in `onConnectionStateChange` | `f9d83d4` |
| [I060](I060-android-disconnect-fire-and-forget.md) | `disconnect()` fire-and-forget; now awaits STATE_DISCONNECTED with 5 s fallback | `c70d6d0` |
| [I061](I061-android-cleanup-orphans-pending-callbacks.md) | `cleanup()` orphans pending callbacks; now drains queues + fails-or-succeeds pending callbacks | `33c48fb` |
| [I098](I098-android-connection-manager-rewrite.md) | Coherent rewrite of Android `ConnectionManager` (threading + disconnect lifecycle); bundles I060/I061/I062/I064 + concurrent-connect mutex | `051f415` (11 commits) |
| [I003](I003-notification-controllers-never-closed.md) | Memory leak: per-characteristic notification controllers never closed; `_cleanup()` now walks `_cachedServices` and disposes each | `f69dafa` |
| [I002](I002-gatt-ops-not-gated-by-connection-state.md) | GATT ops not gated by connection state; `_ensureConnected()` now throws `DisconnectedException` from every public op | `7da8795` |
| [I082](I082-notify-characteristic-unsynchronized-iteration.md) | Android `notifyCharacteristic` iterated subscriptions unsynchronized; defensive snapshot + `handler.post` for binder-thread mutations | `80ef2ed` |
| [I080](I080-add-service-advertising-race.md) | `addService` races with `startAdvertising`; platform-side Map keyed by UUID + Dart-side `_pendingServiceAdds` awaited by `startAdvertising` | `da80f52` |
| [I012](I012-notification-completion-not-tracked-per-central.md) | Server notification completion not tracked per central; `pendingNotifications` FIFO queue + `onNotificationSent` wiring + 5 s timeout + `STATE_DISCONNECTED` drain | `aa588f1` |
| [I088](I088-pigeon-gatt-schema-rewrite.md) | Pigeon GATT schema rewrite: opaque `AttributeHandle` threaded through every characteristic/descriptor op; subsumes I010/I011/I016 | `73656b4` (bundle `929e869..73656b4`) |
| [I010](I010-characteristic-uuid-lookup-no-service-context.md) | Characteristic UUID lookup ignored service context; resolved by I088 handle rewrite | `73656b4` (bundle `929e869..73656b4`) |
| [I011](I011-descriptor-uuid-lookup-no-char-context.md) | Descriptor UUID lookup ignored characteristic context; resolved by I088 handle rewrite | `73656b4` (bundle `929e869..73656b4`) |
| [I016](I016-ios-server-characteristics-uuid-only.md) | iOS server `characteristics` dict keyed by UUID alone; resolved by I088 handle rewrite (server-side mirror) | `73656b4` (bundle `929e869..73656b4`) |
| [I089](I089-connection-platform-tagged-extensions.md) | `Connection` rewritten to platform-tagged extensions (`connection.android` / `connection.ios`); subsumes I066 | `73656b4` (bundle `929e869..73656b4`) |
| [I066](I066-connection-platform-specific-methods.md) | Cross-platform `Connection` interface declared platform-specific methods; resolved by I089 platform-tagged extensions | `73656b4` (bundle `929e869..73656b4`) |
| [I300](I300-connection-peer-bounded-context.md) | Connection aggregate carried Peer-context state; resolved via composition (`PeerConnection` wraps `Connection`); `Bluey.connect` / `connectAsPeer` / `tryUpgrade` split | `73656b4` (bundle `929e869..73656b4`) |
| [I301](I301-connection-params-mtu-primitive-obsession.md) | `ConnectionParameters` and `mtu` primitives replaced with value objects (`ConnectionInterval`, `PeripheralLatency`, `SupervisionTimeout`, `Mtu`) | `73656b4` (bundle `929e869..73656b4`) |
| [I307](I307-structured-logging-pipeline.md) | Structured logging pipeline (domain + Android + iOS native) unified into `bluey.logEvents` with Dart-set level filter; released as 0.3.0 | `db5a999` (bundle `bd0b433..db5a999`) |
| [I090](I090-connect-disconnect-not-error-wrapped.md) | `connect()` / `disconnect()` / extension-method bypass; resolved by I099 typed-translation rewrite | `5d4ba85` (bundle `0a72a42..6427cc8`) |
| [I092](I092-scan-errors-not-translated.md) | Scan errors not translated to domain exceptions; resolved by I099 | `8fd3428` (bundle `0a72a42..6427cc8`) |
| [I099](I099-typed-error-translation-rewrite.md) | Typed-error-translation rewrite; new `withErrorTranslation` helper; `Bluey.errorStream` removed (breaking) | `6427cc8` (bundle `0a72a42..6427cc8`) |
| [I074](I074-send-disconnect-command-can-hang.md) | `sendDisconnectCommand()` could hang the disconnect path; 1 s timeout in `PeerConnection.disconnect`; `BlueyConnection.disconnect` no longer carries lifecycle | `3041eca` (premise gone post-I300 `ccb5dc6`) |
| [I071](I071-upgrade-called-twice-leaks-lifecycle.md) | `BlueyConnection.upgrade()` double-upgrade leak; `upgrade()` removed entirely by I300 | `ccb5dc6` |
| [I044](I044-ios-disconnect-on-disconnected-waits-timeout.md) | iOS disconnect of an already-disconnected peripheral waited the full 30 s timeout; now short-circuits | `683a1eb` |
| [I045](I045-ios-disconnect-central-noop.md) | iOS `disconnectCentral` lied about success while the BLE link stayed up; now throws (breaking) | `d015870` |

### Wontfix — documented platform limitations & superseded premises

| ID | Title | Platform |
|---|---|---|
| [I087](I087-failure-injection-no-auto-reconnect.md) | Connection doesn't auto-reconnect after failure-injection-style disconnect (premise was wrong post-I079) | ios |
| [I200](I200-ios-bonding-not-exposed.md) | iOS does not expose bonding / PHY / connection parameters | ios |
| [I201](I201-ios-client-disconnect-callback.md) | iOS has no client disconnect callback (mitigated) | ios |
| [I202](I202-ios-cancel-peripheral-unreliable.md) | iOS `cancelPeripheralConnection` unreliable | ios |
| [I203](I203-ios-ble-address-rotation.md) | iOS rotates BLE addresses per connection | ios |
| [I204](I204-ios-advertising-limitations.md) | iOS advertising: no manufacturer data, background limits, GAP name | ios |
| [I205](I205-ios-device-name-restricted.md) | iOS 16+ `UIDevice.current.name` returns generic model name | ios |
| [I206](I206-android-force-kill-cleanup.md) | Android force-kill has no cleanup hook | android |
| [I207](I207-android-force-disconnect-remote-central.md) | Android cannot force-disconnect remote centrals | android |

---

## ID allocation

- `I001–I009` — domain layer
- `I010–I019` — Android native bugs (non-stub)
- `I020–I029` — Android GATT server stubs
- `I030–I039` — Android connection-level stubs / missing APIs
- `I040–I049` — iOS stubs / no-ops
- `I050–I099` — cross-platform features
- `I100–I199` — fixed
- `I200–I299` — wontfix
- `I300–I399` — DDD / architectural refinement (bounded-context boundaries, value objects, ubiquitous language)

Gaps in the numbering are intentional — they reserve space for follow-up entries in the same cluster.

**Cluster deviations.** A handful of entries from the 2026-04-26 deep review (I016 iOS server, I017 domain) landed in the I010–I019 range because the cross-platform cluster (I050–I099) was nearly full. The convention is "by content, not by ID" when reading the index — refer to the section the entry appears under, not its numeric range. When new IDs are assigned going forward, prefer fresh numbers in the I100s+ if all relevant cluster ranges are saturated, rather than overflowing into a sibling cluster.
