---
id: I340
title: Remove the dormant silence-eviction machinery once Pattern B has soaked in production
category: cleanup
severity: low
platform: both
status: open
last_verified: 2026-06-02
related: [I338, I201]
---

> **Status note (2026-06-02).** Deferred follow-up to [I338](I338-lifecycle-silence-emits-disconnect-without-gatt-teardown.md).
> Do **not** action until Pattern B (presence-subscription disconnect
> detection) has soaked in production across a range of iOS versions /
> Bluetooth chipsets / field loss conditions. This is a deliberate
> "delete the fallback only after the primary is seasoned" item, not a
> bug.

## Background

I338's iOS half landed via **Pattern B**: the iOS GATT server detects a
client disconnect from a presence-characteristic unsubscribe
(`didUnsubscribeFrom(presence)`), so `Capabilities.iOS.reportsCentralDisconnects`
is `true` and heartbeat silence is purely advisory. The earlier **Stage 2
eviction handshake** (silence → session removal → reject the resumed
request with a reserved ATT status → client self-disconnect → clean
reconnect) was **not deleted** — it is retained *dormant* behind
`reportsCentralDisconnects == false` as a one-flag-flip fallback in case
the `didUnsubscribe(presence)` signal proves unreliable on hardware we
haven't yet exercised.

Real-device dogfood (2026-06-02) confirmed Pattern B works across all four
loss modes with clean reconnect. Once production telemetry confirms the
same over time, the dormant fallback becomes dead weight and should be
removed.

## The dormant surface to remove (when the time comes)

This deletion touches both the domain and the platform packages, so it
warrants its own review + dogfood — it must **not** be bundled into the
Pattern B landing.

- **`bluey_platform_interface`**: `PlatformGattStatus.lifecycleEviction`
  (the reserved `0x80` ATT status) and its Pigeon `GattStatusDto`
  carry-through.
- **Native conversions**: Android (Kotlin) and iOS (Swift) translation of
  the reserved status to/from the wire (`CBATTError.Code(rawValue: 0x80)`
  on iOS, the Android equivalent).
- **`bluey` connection layer**: `translatePlatformException` →
  `DisconnectedException(evictedByServer)` and the `LifecycleClient`
  self-disconnect fast-path on the reserved status (`_isEvictionSignal`).
- **`bluey` GATT-server layer**: the session-less request rejection gate
  in `bluey_server.dart` (currently a harmless safety net under the flip)
  and the `_handleLifecycleSilence` fallback branch that forwards silence
  to `_handleClientDisconnected` when `reportsCentralDisconnects == false`.
- **`resetServerSessions()`** re-announce path (platform-interface +
  `BlueyAndroid`/`BlueyIos` overrides + native `reannounceTrackedCentrals`),
  **iff** it exists solely for the eviction-reconnect recovery — verify it
  has no remaining Pattern-B purpose before removing.
- **Tests** asserting eviction behavior + the `DisconnectReason.evictedByServer`
  enum value (a public-API removal — gate on a deprecation cycle if it has
  shipped).
- **Docs**: the dormant-eviction notes in `cross-platform-quirks.md`,
  `IOS_BLE_NOTES.md`, `capabilities.dart`, and `bluey_server.dart`.

## Caveat

Removing `DisconnectReason.evictedByServer` is a breaking public-API change
if a release has shipped it. Check whether it has been published before
deleting; if so, deprecate-then-remove rather than dropping it outright.
