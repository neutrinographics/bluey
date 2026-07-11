# Bluey roadmap

The at-a-glance index of Bluey's development work — what's planned, what's in
progress, what's shipped, and what we've deliberately decided not to do.

This file is the **index**: it owns each item's **track**, **priority**, and
**status**, plus the project's design **guardrails**. The timeless, detailed
description of each item — symptom, root cause, `file:line` locations, fix
sketches — lives in its own file under [`backlog/`](backlog/), one file per
item, in the richer bug-tracker schema documented in
[`backlog/README.md`](backlog/README.md). When priority or status changes, edit
the line here; leave the backlog file alone.

Tracks mirror the library's bounded contexts (see `CLAUDE.md`): **Discovery**,
**Connection**, **GATT Client**, **GATT Server**, **Peer**, plus **Platform**
(Bluetooth state / permissions / native threading) and **Code health**
(architecture and test-fixture refinement).

**Legend** — Status: `☐` not started · `◐` in progress · `☑` done.
Priority: `High` · `Medium` · `Low` · `Launch` (gated to before a public
release). Priorities below are derived from each item's recorded severity and
are the maintainer's to adjust.

> **Health check (2026-07-06):** every open item is Medium or Low severity —
> **no high-severity bugs are open.** The last two highs, iOS write-without-
> response flow control (I339) and the Android `notifyTo` completion race
> (I332), both shipped. Remaining work is polish, feature-completeness, and
> architectural refinement.

## Guardrails (design invariants)

Non-negotiable constraints that shape *how* every item below gets implemented:

- **TDD** — Red → Green → Refactor. No production code without a failing test first.
- **DDD** — consistent ubiquitous language, respected bounded-context boundaries, immutable value objects with equality by value.
- **Clean Architecture** — dependencies point inward only; the domain layer has zero framework dependencies; platform implementations are swappable.
- **Coverage** — 90% minimum for the domain layer, 80% overall.
- **No singletons** — explicit `await Bluey.create()` with lifecycle via `dispose()`.
- **Streams over callbacks** — all async events are Dart `Stream`s.
- **Immutable data, mutable connections** — Device/Advertisement are snapshots; connection state is observable.
- **Pigeon for platform channels** — type-safe generated bindings, no hand-written `MethodChannel` code.
- **Sealed classes** for exceptions and domain events (exhaustive matching).
- **Handle-based attribute identity** — every GATT attribute is addressed by an opaque, per-connection `AttributeHandle`; UUIDs are for navigation only.

## Discovery

Scanning and inbound advertisement data.

- ☐ **Medium** — [Surface scan-failure reason codes](backlog/I013-scan-failure-error-code-not-propagated.md) · Android scan failures collapse to a generic "scan complete"; the error code is discarded.
- ☐ **Medium** — [Expose scan options (mode, filters, duplicates)](backlog/I052-scan-options-not-exposed.md) · Scan mode/dedup are hardcoded; no RSSI, manufacturer, name, or allow-duplicates controls.
- ☐ **Medium** — [Close scanner streams on dispose](backlog/I094-scanner-controller-never-closed.md) · Platform scanner broadcast controllers are never closed (leak across instances).
- ☐ **Low** — [Return all manufacturer-data entries](backlog/I014-manufacturer-data-only-first-entry.md) · Android returns only the first company-ID entry in an advertisement.
- ☐ **Low** — [Support overlapping scans](backlog/I336-scanner-overlapping-scan-not-supported.md) · A second `scan()` clobbers the first; concurrent scanners aren't multiplexed.

## Connection

Connecting, disconnecting, bonding, PHY, connection parameters, MTU, RSSI, and reconnection.

- ☐ **Medium** — [Track platform-initiated MTU changes](backlog/I004-mtu-not-synced-with-platform-callbacks.md) · `Connection.mtu` goes stale when the peer renegotiates MTU; there's no `mtuChanges` stream.
- ☐ **Medium** — [Handle errors during connection init](backlog/I005-async-init-without-error-handling.md) · Post-connect init futures fire unsupervised with no error handling.
- ☐ **Medium** — [Implement Android bonding](backlog/I030-android-bonding-stub.md) · The bonding API throws `UnimplementedError`; no native create-bond / bond-state wiring.
- ☐ **Medium** — [Implement Android PHY control](backlog/I031-android-phy-stub.md) · The PHY API throws `UnimplementedError`; no set-preferred-PHY / PHY-update wiring.
- ☐ **Medium** — [Implement Android connection parameters](backlog/I032-android-connection-parameters-stub.md) · Get/request connection-parameters throw `UnimplementedError`.
- ☐ **Medium** — [Expose Android connection-priority request](backlog/I033-android-connection-priority-not-exposed.md) · No request-connection-priority API exists at all.
- ☐ **Medium** — [Wire Android bond/PHY/param Pigeon plumbing (Stage B)](backlog/I035-android-bond-phy-conn-param-stubs.md) · Umbrella over I030–I033: Stage A throws honestly, but the native + Pigeon plumbing is absent.
- ☐ **Medium** — [Reconnect to known iOS peripherals](backlog/I043-ios-no-retrieve-peripherals.md) · No `retrievePeripherals` / `retrieveConnectedPeripherals`, so iOS can't fast-reconnect to a known device.
- ☐ **Medium** — [Stop misrouting late Android GATT callbacks](backlog/I063-android-late-callback-misroute-after-timeout.md) · A callback that arrives after an app-level timeout can be delivered to the next operation.
- ☐ **Medium** — [Give stale-bond errors an actionable path](backlog/I321-ios-bond-mismatch-opaque-error.md) · iOS surfaces `CBError` 14 (pairing removed) as an opaque exception with no recovery guidance.
- ☐ **Low** — [Prevent the initial connection-state guess race](backlog/I007-connection-state-init-race.md) · A connection reports a state before the platform stream confirms it.
- ☐ **Low** — [Auto-update Android MTU on peer renegotiation](backlog/I326-android-mtu-onmtuchanged-listener.md) · `connection.android.mtu` isn't refreshed on a spontaneous MTU change.
- ☐ **Low** — [Wrap RSSI in a value object](backlog/I327-rssi-value-object.md) · `Connection.rssi` is a raw `int` with no validation or semantics.
- ☐ **Low** — [Guard against duplicate Android STATE_CONNECTED](backlog/I328-android-state-connected-double-init.md) · A repeat connected callback wipes in-flight queues and resets MTU to 23.

## GATT Client

Local-as-client reads, writes, notifications, and service discovery.

- ☐ **Medium** — [Separate iOS read responses from notifications](backlog/I041-ios-read-notification-race.md) · `didUpdateValue` conflates a read reply with an unsolicited notification.
- ☐ **Medium** — [Implement prepared / long writes](backlog/I050-prepared-write-flow-unimplemented.md) · The chunked long-write (prepared-write) flow is unimplemented on both roles.
- ☐ **Medium** — [Fix the service-cache re-discovery race](backlog/I075-cached-services-race-with-invalidation.md) · `services()` and Service-Changed re-discovery race on the cached service list.
- ☐ **Low** — [Prevent the first-listen subscription race](backlog/I008-notification-subscription-race.md) · Enabling notifications races the CCCD write on the first stream listen.

## GATT Server

Local-as-peripheral: advertising, request/response handling, and outbound notifications.

- ☐ **Medium** — [Expose server descriptor reads to Dart](backlog/I022-gatt-server-descriptor-read-no-dart-api.md) · Descriptor reads are auto-answered natively with no Dart handler.
- ☐ **Medium** — [Propagate server-side MTU changes to Dart](backlog/I024-gatt-server-mtu-change-not-propagated.md) · Per-central MTU changes are cached but never surfaced.
- ☐ **Medium** — [Respond to every batched ATT write on iOS](backlog/I047-ios-pending-write-requests-batch.md) · `respondToWriteRequest` answers only the first of a batched request group.
- ☐ **Medium** — [Expose advertising options (TX power, connectable, name)](backlog/I051-advertising-options-not-exposed.md) · Only advertise mode is exposed; the other knobs are hardcoded.
- ☐ **Medium** — [Reject concurrent startAdvertising on Android](backlog/I081-advertiser-concurrent-start.md) · Two overlapping start calls launch two advertisers before the success callback lands.
- ☐ **Medium** — [Clear iOS server state on power-off](backlog/I083-ios-powered-off-no-state-clear.md) · `.poweredOff` doesn't clear caches or drain pending requests.
- ☐ **Medium** — [Restore subscriptions after reconnect](backlog/I084-reconnect-loses-subscriptions.md) · A reconnecting central silently loses its prior subscriptions.
- ☐ **Medium** — [Reject malformed CCCD writes](backlog/I085-cccd-malformed-bytes-silently-ignored.md) · An unrecognized CCCD value is silently acked with success.
- ☐ **Medium** — [Fix the iOS removeService vs notify race](backlog/I086-remove-service-race-with-notify.md) · `removeService` races in-flight notify fanout (Android is already fixed).
- ☐ **Medium** — [Close server streams on dispose](backlog/I095-server-controllers-never-closed.md) · Server broadcast controllers are never closed.
- ☐ **Medium** — [Honor the advertised name on Android](backlog/I318-android-advertise-name-ignored.md) · `config.name` is treated as a boolean and dropped; the system adapter name is broadcast instead.
- ☐ **Medium** — [Fix the duplicate respondTo* root cause](backlog/I322-duplicate-respond-to-request.md) · A response can fire twice (`RespondNotFound`); only crash-containment has shipped, not the root-cause fix.
- ☐ **Low** — [Surface server-side PHY events](backlog/I025-gatt-server-phy-events-logging-only.md) · PHY update/read events are logging-only; there's no Dart API.
- ☐ **Low** — [Detect non-Bluey iOS client disconnect on Android server](backlog/I306-android-server-no-disconnect-on-ios-client-cancel.md) · Detection relies on the native supervision timeout; no mitigation.
- ☐ **Low** — [Purge stale iOS pending notifications on disconnect](backlog/I315-ios-pending-notification-stale-entries-on-disconnect.md) · The queue keeps entries for centrals that left mid-burst.
- ☐ **Low** — [Disambiguate Android advertise failures](backlog/I319-android-advertise-error-opaque.md) · Most advertise errors collapse to `bluey-unknown`.
- ☐ **Low** — [Don't wedge the ATT channel on a dropped write](backlog/I342-failure-injection-ios-server-att-wedge.md) · A failure-injected drop never acks, wedging the sequential ATT channel.

## Peer

The Bluey lifecycle protocol, stable peer identity, and peer discovery.

- ☐ **Medium** — [Fix the LifecycleServer activity/timer race](backlog/I072-lifecycle-server-record-activity-race.md) · `recordActivity` does a check-then-act on the heartbeat timer map (single-threaded, defensive).
- ☑ **Medium** — [Stop peer connect waiting out the full scan window](backlog/I349-peer-connect-waits-full-scan-window.md) · `connectTo`/`discover` collect-then-probe, so every peer connect costs the whole scanTimeout even on an instant match.
- ☐ **Low** — [Extract a shared peer-builder helper](backlog/I304-peer-builder-helper-extraction.md) · Two sites duplicate `PeerConnection` / `LifecycleClient` construction.
- ☐ **Low** — [Remove the dormant silence-eviction machinery](backlog/I340-remove-dormant-silence-eviction-machinery.md) · Deferred cleanup of the reserved ATT-status eviction path — hold until Pattern B soaks in production.
- ☐ **Low** — [Retry failed presence subscriptions](backlog/I341-presence-subscription-failure-degrades-ios-disconnect-detection.md) · A failed presence-characteristic subscription leaves an iOS-server peer's disconnect undetectable.

## Platform

Bluetooth adapter state, permissions, capabilities, and native threading / lifecycle.

- ☐ **Medium** — [Enable iOS state restoration](backlog/I048-ios-no-state-restoration.md) · Managers start without a restore identifier, so a background relaunch loses state.
- ☐ **Medium** — [Move bluey-ios off the main thread](backlog/I345-decouple-bluey-ios-from-main-thread.md) · CoreBluetooth delegates, Pigeon handlers, and timers all run on the iOS main thread.
- ☐ **Medium** — [Give the iOS central role a delegate seam](backlog/I350-ios-central-manager-delegate-seam.md) · `CentralManagerImpl` is welded to CB types; its delegate wiring (disconnect drain, write gate, power-off) is only testable on hardware. Server role got its seam in audit R5.
- ☐ **Low** — [Coordinate GATT-server teardown on engine detach](backlog/I015-gatt-server-close-order-on-engine-detach.md) · Redundant cleanup entry points with no teardown state machine.

## Code health

Architecture / DDD refinement and test-fixture consistency — no user-visible behavior change.

- ☐ **Low** — [Stop the domain catching Flutter's PlatformException](backlog/I308-domain-catches-flutter-platform-exception.md) · The domain catch ladder depends on a Flutter framework type.
- ☐ **Low** — [Route the domain through abstract repositories](backlog/I309-domain-imports-platform-interface-types-directly.md) · The domain imports platform-interface types directly instead of via a port.
- ☐ **Low** — [Make iOS connection extensions per-connection](backlog/I312-ios-extensions-singleton-asymmetry.md) · iOS uses a const singleton where Android is per-connection.
- ☐ **Low** — [Express advertise intent, not platform mechanism](backlog/I320-domain-server-names-platform-mechanism.md) · `BlueyServer` names the platform "scan response" slot directly instead of the intent.
- ☐ **Low** — [Reconcile the two fake requestMtu caps](backlog/I329-fake-mock-requestmtu-inconsistency.md) · Test fixtures disagree on whether to cap MTU at 512.
- ☐ **Low** — [Shape the fake's disconnected error like the real one](backlog/I330-fake-platform-getmaximumwritelength-exception-shape.md) · `FakeBlueyPlatform` throws a raw `Exception` instead of a `gatt-disconnected`-shaped one.
- ☑ **Low** — [Model the iOS shared-link trap in the fake platform](backlog/I346-fake-platform-shared-link-trap-model.md) · The fake's two roles can't share one physical link, so the documented bidirectional-discovery trap is untestable. Follow-up to the 2026-07-10 test audit; sequence after its R1–R9.
- ☑ **Low** — [Make the role-reversal ATT blackhole injectable in the fake](backlog/I347-fake-platform-role-reversal-att-blackhole.md) · No seam for "server silently receives nothing while the link looks healthy" (I208's condition), so death-watch convergence is untested. Follow-up to the 2026-07-10 test audit; sequence after its R1–R9.
- ☑ **Low** — [Accept inherited centrals before advertising in the fake](backlog/I348-fake-platform-inherited-central-before-advertising.md) · `simulateCentralConnection` throws pre-advertising, but real platforms deliver cached/inherited connections then. Follow-up to the 2026-07-10 test audit; sequence after its R1–R9.

## Shipped

Completed and verified in HEAD. Kept so the record survives; the linked file
carries the detail and the shipping commit. Sorted by ID.

| Item | What it was | Shipped in |
|---|---|---|
| [I001](backlog/I001-disconnect-state-double-emission.md) | Disconnect state double-emission | `8b02ccf` |
| [I002](backlog/I002-gatt-ops-not-gated-by-connection-state.md) | GATT operations not gated by connection state | `7da8795` |
| [I003](backlog/I003-notification-controllers-never-closed.md) | Memory leak: notification controllers never closed | `f69dafa` |
| [I006](backlog/I006-mac-to-uuid-truncation.md) | BlueyCentral MAC → UUID truncation | `3863358` |
| [I009](backlog/I009-server-respond-leaks-internal-exception.md) | `respondToRead`/`respondToWrite` leak internal platform-interface exception | `a6bd217` |
| [I010](backlog/I010-characteristic-uuid-lookup-no-service-context.md) | Characteristic UUID lookup ignores service context | `73656b4` |
| [I011](backlog/I011-descriptor-uuid-lookup-no-char-context.md) | Descriptor UUID lookup ignores characteristic context | `73656b4` |
| [I012](backlog/I012-notification-completion-not-tracked-per-central.md) | Server notification completion not tracked per central | `aa588f1` |
| [I016](backlog/I016-ios-server-characteristics-uuid-only.md) | iOS server `characteristics` dict keyed by UUID alone | `73656b4` |
| [I017](backlog/I017-peer-silence-timeout-defaults.md) | `peerSilenceTimeout` internally inconsistent, races OS supervision timeout | `a352c17` |
| [I020](backlog/I020-gatt-server-auto-respond-characteristic-write.md) | GATT server auto-respond on characteristic write | `3539a42` |
| [I021](backlog/I021-gatt-server-auto-respond-characteristic-read.md) | GATT server auto-respond on characteristic read | `3539a42` |
| [I023](backlog/I023-gatt-server-notification-sent-no-tracking.md) | `onNotificationSent` not tracked for completion | `aa588f1` |
| [I034](backlog/I034-android-maximum-write-length-not-exposed.md) | Maximum write length query not exposed | `47c3e5b` |
| [I040](backlog/I040-ios-notification-retry-on-ready.md) | `isReadyToUpdateSubscribers` does not retry failed notifications | `47ba2f5` |
| [I042](backlog/I042-ios-services-cache-dead.md) | iOS `services` dict is dead storage | `99893fd` |
| [I044](backlog/I044-ios-disconnect-on-disconnected-waits-timeout.md) | iOS disconnect of an already-disconnected peripheral waits for timeout | `683a1eb` |
| [I045](backlog/I045-ios-disconnect-central-noop.md) | iOS `disconnectCentral` returns success without disconnecting the central | `d015870` |
| [I046](backlog/I046-ios-max-write-length-not-exposed.md) | iOS `getMaximumWriteLength` implemented but not exposed via Pigeon | `47c3e5b` |
| [I053](backlog/I053-capabilities-matrix-incomplete.md) | `Capabilities` matrix incomplete | `e177f1d` |
| [I054](backlog/I054-events-dart-dead-types.md) | Several `BlueyEvent` subtypes defined but never emitted | `14bae42` |
| [I055](backlog/I055-peer-discovery-no-scan-filter.md) | PeerDiscovery scans without a service filter | `4abcba9` |
| [I056](backlog/I056-peer-discovery-probe-no-timeout.md) | PeerDiscovery probe-connect uses the platform default timeout | `4abcba9` |
| [I057](backlog/I057-mac-to-uuid-coercion-duplicated.md) | MAC-to-UUID coercion duplicated in two places | `510278e` |
| [I058](backlog/I058-server-advertising-mode-dropped.md) | `startAdvertising` drops the user-supplied advertising mode | `6ebcf53` |
| [I059](backlog/I059-server-remove-service-fire-and-forget.md) | `removeService` doesn't await the platform call | `6ebcf53` |
| [I060](backlog/I060-android-disconnect-fire-and-forget.md) | Android `disconnect()` is fire-and-forget | `c70d6d0` |
| [I061](backlog/I061-android-cleanup-orphans-pending-callbacks.md) | `ConnectionManager.cleanup()` orphans pending callbacks | `33c48fb` |
| [I062](backlog/I062-android-threading-violation-in-callbacks.md) | Binder-thread mutation of main-thread state in `onConnectionStateChange` | `f9d83d4` |
| [I064](backlog/I064-android-phase-2b-dead-legacy-maps.md) | Legacy pending-op maps in `ConnectionManager` are dead code | `3962e43` |
| [I065](backlog/I065-capabilities-matrix-decorative.md) | Capabilities matrix decorative; no production code consulted it | `e177f1d` |
| [I066](backlog/I066-connection-platform-specific-methods.md) | Cross-platform Connection interface declared platform-specific methods | `73656b4` |
| [I067](backlog/I067-connection-state-linked-vs-ready.md) | ConnectionState collapsed link-up and services-discovered | `8b02ccf` |
| [I068](backlog/I068-event-bus-missing-lifecycle-events.md) | Lifecycle protocol state changes not emitted as BlueyEvents | `d2fb012` |
| [I069](backlog/I069-fake-platform-capabilities-hardcoded.md) | FakeBlueyPlatform.capabilities hardcoded; no capability-branch coverage | `e177f1d` |
| [I070](backlog/I070-lifecycle-client-late-promise-callbacks.md) | LifecycleClient late promise callbacks fire after `stop()` | `136fa47` |
| [I071](backlog/I071-upgrade-called-twice-leaks-lifecycle.md) | `upgrade()` called twice leaks the previous lifecycle | `ccb5dc6` |
| [I073](backlog/I073-lifecycle-client-start-not-idempotent.md) | `LifecycleClient.start()` is not idempotent | `136fa47` |
| [I074](backlog/I074-send-disconnect-command-can-hang.md) | `sendDisconnectCommand()` can hang the `disconnect()` path | `3041eca` |
| [I076](backlog/I076-handle-service-change-silent-swallow.md) | `_handleServiceChange` swallowed all exceptions silently | `verified 2026-07-06` |
| [I077](backlog/I077-lifecycle-client-disconnect-storm.md) | Client toggles connected/disconnected during heartbeat activity | `0b97cc6` |
| [I078](backlog/I078-lifecycle-client-activity-drop-during-start.md) | `recordActivity()` drops signals during `start()` window | `136fa47` |
| [I079](backlog/I079-lifecycle-heartbeat-starves-behind-long-user-ops.md) | LifecycleServer declares clients gone while holding their requests | `4206343` |
| [I080](backlog/I080-add-service-advertising-race.md) | Android `addService` races with `startAdvertising` | `da80f52` |
| [I082](backlog/I082-notify-characteristic-unsynchronized-iteration.md) | Android `notifyCharacteristic` iterates subscriptions unsynchronized | `80ef2ed` |
| [I088](backlog/I088-pigeon-gatt-schema-rewrite.md) | Pigeon GATT schema rewrite — handle-based attribute identity | `73656b4` |
| [I089](backlog/I089-connection-platform-tagged-extensions.md) | Connection rewritten to platform-tagged extensions | `73656b4` |
| [I090](backlog/I090-connect-disconnect-not-error-wrapped.md) | `connect()`/`disconnect()` bypassed error translation | `5d4ba85` |
| [I091](backlog/I091-ios-unmapped-cbatt-error-to-unknown.md) | iOS unmapped `CBATTError` codes became `bluey-unknown` | `8875f4c` |
| [I092](backlog/I092-scan-errors-not-translated.md) | Scan errors not translated to domain exceptions | `8fd3428` |
| [I093](backlog/I093-ios-notfound-maps-to-wrong-error.md) | iOS `notFound` mapped to `gatt-disconnected` | `8875f4c` |
| [I096](backlog/I096-ios-nil-disconnect-error-to-unknown.md) | iOS nil-error disconnect produced `bluey-unknown` | `c145209` |
| [I097](backlog/I097-client-opslot-starves-heartbeat.md) | Client-side OpSlot starvation caused false heartbeat failures | `8f8a5a9` |
| [I098](backlog/I098-android-connection-manager-rewrite.md) | Coherent Android ConnectionManager rewrite | `051f415` |
| [I099](backlog/I099-typed-error-translation-rewrite.md) | Typed error-translation rewrite (typed catch ladder) | `6427cc8` |
| [I100](backlog/I100-pending-callbacks-not-cleaned-on-disconnect.md) | Pending callbacks not cleaned on disconnect | `8d210c3` |
| [I101](backlog/I101-android-pending-callback-collision.md) | Android pending callback collision | `8d210c3` |
| [I102](backlog/I102-connection-timeout-not-cancelled.md) | Connection timeout not cancelled on success | Phase 2a |
| [I103](backlog/I103-scan-timeout-double-emit.md) | Scan timeout fires after manual stop | Scanner refactor |
| [I300](backlog/I300-connection-peer-bounded-context.md) | Connection aggregate carried Peer-context state | `73656b4` |
| [I301](backlog/I301-connection-params-mtu-primitive-obsession.md) | ConnectionParameters/mtu primitives → value objects | `73656b4` |
| [I302](backlog/I302-ubiquitous-language-glossary.md) | Ubiquitous-language glossary + seam comments | `1c34d90` |
| [I303](backlog/I303-capabilities-platform-kind-flag.md) | `Connection.ios` dispatch via a precise capability flag | `e177f1d` |
| [I305](backlog/I305-example-bluey-badge-via-tryupgrade.md) | Re-introduce example BLUEY badge via `tryUpgrade` | `d29fe75` |
| [I307](backlog/I307-structured-logging-pipeline.md) | Structured logging pipeline (domain + native) | `db5a999` |
| [I310](backlog/I310-ios-unsupported-error-falls-through-as-platform-exception.md) | iOS `UnsupportedError` surfaced as null-code exception | `e177f1d` |
| [I311](backlog/I311-server-side-bypass-typed-translation.md) | Server-side methods bypassed the typed-translation helper | `013fb3c` |
| [I313](backlog/I313-android-control-uuid-in-scan-response.md) | Auto-include control UUID in Android scan response | `c91d32b` |
| [I314](backlog/I314-example-cubit-stale-services-on-cold-start.md) | Example app didn't refresh services on Service Changed | `53d5764` |
| [I316](backlog/I316-stress-runner-tight-timeout-and-partial-burst-discard.md) | Stress runner: tight timeout + discarded partial bursts | `ce65141` |
| [I317](backlog/I317-migrate-existing-consumers-to-event-publisher.md) | Migrate consumers to the `EventPublisher` port | `84a04dd` |
| [I323](backlog/I323-connectaspeer-no-existing-peer-detection.md) | `connectAsPeer` didn't detect an already-connected other-role device | fixed |
| [I324](backlog/I324-document-ios-peer-merge-behavior.md) | Document iOS CoreBluetooth peer-merge on dual-role connections | fixed |
| [I325](backlog/I325-expose-platform-max-write-payload.md) | Expose `maxWritePayload`; relocate `mtu`/`requestMtu` to Android ext | fixed |
| [I331](backlog/I331-blueyclient-mtu-hardcoded-from-lifecycle-identification.md) | `BlueyClient.mtu` hardcoded to 23 in the handshake path | `verified 2026-07-06` |
| [I332](backlog/I332-server-notifyto-does-not-await-onnotificationsent.md) | `Server.notifyTo` returned before `onNotificationSent` (Android) | `via I012 · verified 2026-07-06` |
| [I333](backlog/I333-bluetooth-adapter-state-not-observed.md) | Live instances not invalidated when the adapter cycles off | fixed |
| [I334](backlog/I334-statestream-no-current-value-replay.md) | `stateStream` didn't replay the current value on subscription | fixed |
| [I335](backlog/I335-scanner-stream-no-oncancel-stopscan.md) | `scan()` stream didn't stop the platform scan on cancel | fixed |
| [I337](backlog/I337-client-id-mismatch-between-peerconnections-and-disconnections.md) | `Client.id` mismatched `Server.disconnections`' identifier | resolved |
| [I338](backlog/I338-lifecycle-silence-emits-disconnect-without-gatt-teardown.md) | Lifecycle-silence fired `Server.disconnections` without GATT teardown | `d173d39` |
| [I339](backlog/I339-ios-write-without-response-no-flow-control.md) | iOS write-without-response had no flow control (silent drops/corruption) | `d8277b7 (#39)` |
| [I343](backlog/I343-ios-to-android-multi-chunk-writenoresponse-loses-2-bytes-per-frame.md) | iOS over-reported the WriteNoResponse max, truncating large frames | `c7f1446` |
| [I344](backlog/I344-write-integrity-stress-test.md) | Write-integrity stress test (repro/regression harness for I339/I343) | `e5ca4e7` |

## Limitations (wontfix)

Platform capabilities that are impossible or intentionally out of scope,
recorded so they aren't rediscovered. Not roadmap work.

| Item | Platform | Why it's off the table |
|---|---|---|
| [I087](backlog/I087-failure-injection-no-auto-reconnect.md) | ios | No auto-reconnect after a failure-injection-style disconnect (original premise was wrong) |
| [I200](backlog/I200-ios-bonding-not-exposed.md) | ios | iOS doesn't expose bonding / PHY / connection parameters |
| [I201](backlog/I201-ios-client-disconnect-callback.md) | ios | iOS has no client-disconnect callback (mitigated) |
| [I202](backlog/I202-ios-cancel-peripheral-unreliable.md) | ios | iOS `cancelPeripheralConnection` is unreliable |
| [I203](backlog/I203-ios-ble-address-rotation.md) | ios | iOS rotates BLE addresses per connection |
| [I204](backlog/I204-ios-advertising-limitations.md) | ios | iOS advertising: no manufacturer data, background limits, GAP name |
| [I205](backlog/I205-ios-device-name-restricted.md) | ios | iOS 16+ returns a generic model name for `UIDevice.current.name` |
| [I206](backlog/I206-android-force-kill-cleanup.md) | android | Android force-kill has no cleanup hook |
| [I207](backlog/I207-android-force-disconnect-remote-central.md) | android | Android cannot force-disconnect remote centrals |
| [I208](backlog/I208-android-dual-role-server-request-delivery.md) | android | Android drops GATT-server ATT requests after a client↔server role reversal on a live link |
