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

Ordered by impact per hour, based on the 2026-04-23 deep-review campaign. Treat as a recommendation, not a commitment — re-evaluate when circumstances change (user-visible bug reports, prioritized features, etc.).

1. **I070 + I073 + I078** — Lifecycle client guards. *Est. 1 day.* Tiny `_isRunning` flag + `start()` idempotency check + activity-signal handling during the `start()` → interval-read window. Prevents the zombie-timer pattern that accumulates across disconnect cycles. Promoted to #1 because (a) I070 is `high` severity, (b) the `LifecycleClient` code is warm after the I077 fix, and (c) small PR — cheap momentum before the larger #3/#4 blocks.

2. **I010 + I011** — Characteristic and descriptor UUID lookup ignores service/characteristic context. *Est. 2 days.* Fixes the descriptor-collision bug that misroutes CCCD writes on any multi-service peripheral (very common — CCCD is on every notifiable characteristic). Coherent single PR because both changes share a Pigeon-schema extension (adding `serviceUuid` / `characteristicUuid` context).

3. **I062 + I082 + I086** — "Phase 2c: thread-safety audit." *Est. 3–5 days.* One sustained pass through the Android native layer, wrapping all state mutations in `handler.post` and either locking or defensively copying subscription sets. These are the flaky-bug generators — they don't show up in dev/test but bite at scale.

4. **I060 + I061 + I074** — Disconnect / cleanup correctness. *Est. 1–2 days.* Android `disconnect()` fire-and-forget, `cleanup()` orphans pending callbacks, courtesy `sendDisconnectCommand` can hang the whole disconnect. Small, targeted, each mostly independent.

Opportunistic one-offs — pick up when you're already in nearby code:

- **I009** — `BlueyServer.respondToRead`/`respondToWrite` leak an internal platform-interface exception. Medium severity, one-file fix in the server error-translation path; natural to grab next time you're in `android_server.dart` / `ios_server.dart`.

Everything else (the other 40-odd open entries) can also proceed opportunistically — pick up related entries when you're already in the code for a higher-priority fix.

---

## Index

### Open — domain layer

| ID | Title | Severity |
|---|---|---|
| [I001](I001-disconnect-state-double-emission.md) | Disconnect state double-emission | medium |
| [I002](I002-gatt-ops-not-gated-by-connection-state.md) | GATT ops not gated by connection state | high |
| [I003](I003-notification-controllers-never-closed.md) | Memory leak: notification controllers never closed | high |
| [I004](I004-mtu-not-synced-with-platform-callbacks.md) | MTU not synced with platform-initiated changes | medium |
| [I005](I005-async-init-without-error-handling.md) | Async initialization without error handling | medium |
| [I006](I006-mac-to-uuid-truncation.md) | BlueyCentral MAC → UUID truncation | medium |
| [I007](I007-connection-state-init-race.md) | Connection state init race (mitigated, not prevented) | low |
| [I008](I008-notification-subscription-race.md) | Notification subscription race (mitigated, not prevented) | low |
| [I009](I009-server-respond-leaks-internal-exception.md) | `BlueyServer.respondToRead`/`respondToWrite` leak internal platform-interface exception | medium |
| [I070](I070-lifecycle-client-late-promise-callbacks.md) | LifecycleClient late promise callbacks fire after `stop()` | high |
| [I071](I071-upgrade-called-twice-leaks-lifecycle.md) | `upgrade()` called twice leaks previous lifecycle client | medium |
| [I072](I072-lifecycle-server-record-activity-race.md) | `LifecycleServer.recordActivity` races with timer cancellation | medium |
| [I073](I073-lifecycle-client-start-not-idempotent.md) | `LifecycleClient.start()` is not idempotent | low |
| [I074](I074-send-disconnect-command-can-hang.md) | `sendDisconnectCommand()` can hang entire disconnect path | high |
| [I075](I075-cached-services-race-with-invalidation.md) | `_cachedServices` race between `services()` and invalidation | medium |
| [I076](I076-handle-service-change-silent-swallow.md) | `_handleServiceChange` swallows exceptions silently | medium |
| [I078](I078-lifecycle-client-activity-drop-during-start.md) | `LifecycleClient.recordActivity()` silently drops signals during `start()` → interval-read window | low |
| [I090](I090-connect-disconnect-not-error-wrapped.md) | `connect()` / `disconnect()` bypass error translation | high |
| [I092](I092-scan-errors-not-translated.md) | Scan errors not translated to domain exceptions | medium |

### Open — Android native

| ID | Title | Severity |
|---|---|---|
| [I010](I010-characteristic-uuid-lookup-no-service-context.md) | Characteristic UUID lookup ignores service context | critical |
| [I011](I011-descriptor-uuid-lookup-no-char-context.md) | Descriptor UUID lookup ignores characteristic context | critical |
| [I012](I012-notification-completion-not-tracked-per-central.md) | Server notification completion not tracked per central | high |
| [I013](I013-scan-failure-error-code-not-propagated.md) | Scan failure error code discarded | medium |
| [I014](I014-manufacturer-data-only-first-entry.md) | Manufacturer data only first entry returned | low |
| [I015](I015-gatt-server-close-order-on-engine-detach.md) | GATT server close order on engine detach | low |
| [I060](I060-android-disconnect-fire-and-forget.md) | `disconnect()` fire-and-forget, doesn't wait for confirmation | high |
| [I061](I061-android-cleanup-orphans-pending-callbacks.md) | `cleanup()` orphans pending callbacks (connects hang forever) | high |
| [I062](I062-android-threading-violation-in-callbacks.md) | Threading violation: binder-thread mutation of main-thread maps | high |
| [I063](I063-android-late-callback-misroute-after-timeout.md) | Late GATT callback misrouted after app-level timeout | medium |
| [I064](I064-android-phase-2b-dead-legacy-maps.md) | Legacy pending-op maps are dead code (Phase 2b cleanup) | low |
| [I080](I080-add-service-advertising-race.md) | `addService` races with `startAdvertising` | high |
| [I081](I081-advertiser-concurrent-start.md) | Advertiser allows concurrent `startAdvertising` | medium |
| [I082](I082-notify-characteristic-unsynchronized-iteration.md) | `notifyCharacteristic` iterates subscriptions without sync | high |
| [I085](I085-cccd-malformed-bytes-silently-ignored.md) | CCCD write with malformed bytes silently ignored | medium |

### Open — Android GATT server stubs / no-ops

| ID | Title | Severity |
|---|---|---|
| [I022](I022-gatt-server-descriptor-read-no-dart-api.md) | Descriptor read auto-responded; no Dart API | medium |
| [I023](I023-gatt-server-notification-sent-no-tracking.md) | `onNotificationSent` not tracked for completion | medium |
| [I024](I024-gatt-server-mtu-change-not-propagated.md) | Server-side MTU change not propagated to Dart | medium |
| [I025](I025-gatt-server-phy-events-logging-only.md) | Server-side PHY update/read events are logging-only | low |

### Open — Android connection-level stubs

| ID | Title | Severity |
|---|---|---|
| [I030](I030-android-bonding-stub.md) | Bonding API stubbed (hardcoded returns) | high |
| [I031](I031-android-phy-stub.md) | PHY API stubbed (hardcoded returns) | high |
| [I032](I032-android-connection-parameters-stub.md) | Connection parameters API stubbed (hardcoded returns) | high |
| [I033](I033-android-connection-priority-not-exposed.md) | Connection priority request not exposed | medium |
| [I034](I034-android-maximum-write-length-not-exposed.md) | Maximum write length query not exposed | medium |

### Open — iOS stubs / no-ops / bugs

| ID | Title | Severity |
|---|---|---|
| [I040](I040-ios-notification-retry-on-ready.md) | `isReadyToUpdateSubscribers` does not retry failed notifications | medium |
| [I041](I041-ios-read-notification-race.md) | `didUpdateCharacteristicValue` conflates read response with notification | medium |
| [I042](I042-ios-services-cache-dead.md) | `services` cache dict is dead storage | low |
| [I043](I043-ios-no-retrieve-peripherals.md) | No `retrievePeripherals` / `retrieveConnectedPeripherals` API | medium |
| [I044](I044-ios-disconnect-on-disconnected-waits-timeout.md) | Disconnect of already-disconnected peripheral waits for timeout | low |
| [I083](I083-ios-powered-off-no-state-clear.md) | `peripheralManagerDidUpdateState(.poweredOff)` doesn't clear state | medium |
| [I091](I091-ios-unmapped-cbatt-error-to-unknown.md) | Unmapped `CBATTError` codes silently become `bluey-unknown` | medium |
| [I093](I093-ios-notfound-maps-to-wrong-error.md) | `notFound` for unknown characteristic maps to `gatt-disconnected` | medium |

### Open — cross-platform unimplemented features

| ID | Title | Severity |
|---|---|---|
| [I050](I050-prepared-write-flow-unimplemented.md) | Prepared-write (long-write) flow unimplemented | medium |
| [I051](I051-advertising-options-not-exposed.md) | Advertising options not exposed (TX power, mode, connectable) | medium |
| [I052](I052-scan-options-not-exposed.md) | Scan options not exposed (mode, RSSI filter, duplicates) | medium |
| [I053](I053-capabilities-matrix-incomplete.md) | `Capabilities` matrix incomplete | medium |
| [I084](I084-reconnect-loses-subscriptions.md) | Reconnected central loses subscriptions silently | medium |
| [I086](I086-remove-service-race-with-notify.md) | `removeService` races with in-flight notify fanout | medium |
| [I094](I094-scanner-controller-never-closed.md) | Scanner broadcast controllers never closed (both platforms) | medium |
| [I095](I095-server-controllers-never-closed.md) | AndroidServer / IosServer broadcast controllers never closed | medium |

### Fixed — verified in HEAD

| ID | Title | Fixed in |
|---|---|---|
| [I020](I020-gatt-server-auto-respond-characteristic-write.md) | GATT server auto-respond on characteristic write | `3539a42` |
| [I021](I021-gatt-server-auto-respond-characteristic-read.md) | GATT server auto-respond on characteristic read | `3539a42` |
| [I077](I077-lifecycle-client-disconnect-storm.md) | Client appears to toggle connected/disconnected during heartbeat activity | `0b97cc6` |
| [I100](I100-pending-callbacks-not-cleaned-on-disconnect.md) | Pending callbacks not cleaned on disconnect | `8d210c3` (Phase 2a) |
| [I101](I101-android-pending-callback-collision.md) | Android pending callback collision | `8d210c3` (Phase 2a) |
| [I102](I102-connection-timeout-not-cancelled.md) | Connection timeout not cancelled on success | Phase 2a |
| [I103](I103-scan-timeout-double-emit.md) | Scan timeout fires after manual stop | Scanner refactor |

### Wontfix — documented platform limitations

| ID | Title | Platform |
|---|---|---|
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

Gaps in the numbering are intentional — they reserve space for follow-up entries in the same cluster.
