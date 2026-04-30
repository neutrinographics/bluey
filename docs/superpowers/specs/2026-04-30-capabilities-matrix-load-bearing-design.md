# Capabilities matrix made load-bearing

**Date:** 2026-04-30
**Bundle:** I053 + I065 + I069 + I303 + I310 + I045-followup
**Shape:** Major-version bump (breaking changes)
**Sibling specs:** [2026-04-28-pigeon-gatt-handle-rewrite-design.md](2026-04-28-pigeon-gatt-handle-rewrite-design.md), [2026-04-29-typed-error-translation-rewrite-design.md](2026-04-29-typed-error-translation-rewrite-design.md)

## Goals

1. Make `Capabilities` load-bearing — cross-platform domain methods consult it before crossing the platform-interface seam (closes [I065](../../backlog/I065-capabilities-matrix-decorative.md)).
2. Replace the iOS-detection heuristic on `Connection.ios` with a precise `PlatformKind` discriminator (closes [I303](../../backlog/I303-capabilities-platform-kind-flag.md)).
3. Expand the matrix to cover currently-shipped surface — minimal additions only (closes [I053](../../backlog/I053-capabilities-matrix-incomplete.md) for the load-bearing scope).
4. Eliminate `BlueyPlatformException(null)` for capability-gated ops on iOS by gating in the domain layer (closes [I310](../../backlog/I310-ios-unsupported-error-falls-through-as-platform-exception.md)).
5. Resolve the I045 follow-up — by **removing** `BlueyClient.disconnect()` and `BlueyPlatform.disconnectCentral` rather than adding a flag, since neither supported platform can do this reliably.
6. Add tests exercising capability-gated branches via parameterized `FakeBlueyPlatform` (closes [I069](../../backlog/I069-fake-platform-capabilities-hardcoded.md)).

## Non-goals

- Adding flags for unimplemented features (`canL2capCoc`, `canStateRestoration`, `canDoExtendedAdvertising`, `canDoCodedPhy`, `canRetainPeripheralAcrossReinstall`, etc.). YAGNI: a flag must gate a currently-shipped Bluey method, otherwise it is decorative — exactly the I065 problem we are fixing. Flags get added when the corresponding API lands.
- Refactoring `connection.android` / `connection.ios` extension shapes. They stay as established by [I089](../../backlog/I089-connection-platform-tagged-extensions.md).
- Implementing [I035 Stage B](../../backlog/I035-android-bond-phy-conn-param-stubs.md) (Android Pigeon plumbing for bond/PHY/connection-parameters). When Stage B lands, the relevant Android `canBond` / `canRequestPhy` / `canRequestConnectionParameters` flags flip from `false` to `true`; the gating put in place by this bundle keeps working unchanged.
- Implementing the cooperative server-side disconnect via the lifecycle protocol (option C in [I045](../../backlog/I045-ios-disconnect-central-noop.md)). That is a substantively different feature and gets its own design pass when prioritized.
- Changing the `withErrorTranslation` helper or its defensive `Object` backstop. The backstop continues to handle genuinely-unknown native errors.

## Background

Today the `Capabilities` matrix exists at `bluey_platform_interface/lib/src/capabilities.dart` and is presented to consumers via `Bluey.capabilities`. It carries 11 fields and 5 platform presets. **One** production code path consults it (`Bluey.server()` returns `null` when `!canAdvertise`); every other capability-asymmetric API simply calls through to the platform adapter, which either silently no-ops (`bond` on iOS), returns synthetic defaults (`getBondState` returning `BondState.none` on iOS), or throws plain Dart `UnsupportedError` (`requestMtu` on iOS).

The post-[I099](../../backlog/I099-typed-error-translation-rewrite.md) typed-error translation rewrite converted most platform error paths into typed exceptions, but Dart `UnsupportedError` is not in the typed hierarchy and falls through the helper's defensive `Object` backstop into `BlueyPlatformException(error.toString(), code: null)`. Real-device stress tests on 2026-04-29 surfaced ~10 of these for the Mixed Ops test and 1 for the MTU probe, all from the iOS adapter's `UnsupportedError` throws.

Separately, the `connection.ios` getter introduced by I089/B.2 uses an absence-of-Android-flags heuristic to decide whether to expose iOS extensions. The heuristic is correct for today's two real platforms but conflates "no Android-only features" with "iOS"; a fake platform with all three Android-only flags `false` would incorrectly receive `connection.ios != null`. Compounding this, today's `Capabilities.android` preset has all three Android-only flags `false` (because [I035](../../backlog/I035-android-bond-phy-conn-param-stubs.md) Stage B has not landed), which means on real Android devices `connection.android` returns `null` — a latent bug.

## Design

### `Capabilities` schema changes

Add one enum and one new field. No flag is added that does not gate a currently-shipped method.

```dart
enum PlatformKind { android, ios, fake, other }

class Capabilities {
  final PlatformKind platformKind;       // new, required
  final bool canAdvertiseManufacturerData; // new
  // ... existing 11 fields unchanged ...
}
```

Updated presets:

```dart
static const android = Capabilities(
  platformKind: PlatformKind.android,
  canAdvertise: true,
  canRequestMtu: true,
  maxMtu: 517,
  canBond: false,                          // I035 Stage B pending
  canRequestPhy: false,                    // I035 Stage B pending
  canRequestConnectionParameters: false,   // I035 Stage B pending
  canRequestEnable: true,
  canAdvertiseManufacturerData: true,
);

static const iOS = Capabilities(
  platformKind: PlatformKind.ios,
  canAdvertise: true,
  maxMtu: 185,
  canScanInBackground: true,
  canAdvertiseInBackground: true,
  canBond: false,                          // I200 wontfix
  canRequestPhy: false,                    // I200 wontfix
  canRequestConnectionParameters: false,   // I200 wontfix
  canAdvertiseManufacturerData: false,     // I204 wontfix
);

static const fake = Capabilities(
  platformKind: PlatformKind.fake,
  // permissive defaults for tests:
  canScan: true,
  canConnect: true,
  canAdvertise: true,
  canBond: true,
  canRequestPhy: true,
  canRequestConnectionParameters: true,
  canAdvertiseManufacturerData: true,
);

// macOS / windows / linux presets gain platformKind: PlatformKind.other
```

Equality, `hashCode`, and `toString` are extended to include the two new fields.

**Flags considered and rejected** (per the load-bearing rule):
- `canRequestConnectionPriority` ([I033](../../backlog/I033-android-connection-priority-not-exposed.md)) — no Bluey API exposes the call yet.
- `canRefreshGattCache` — no Bluey API.
- `canForceDisconnectRemoteCentral` ([I045](../../backlog/I045-ios-disconnect-central-noop.md), [I207](../../backlog/I207-android-force-disconnect-remote-central.md)) — the method itself is removed; flag would gate nothing.
- `canStateRestoration`, `canDoExtendedAdvertising`, `canL2capCoc`, `canDoCodedPhy`, `canRetainPeripheralAcrossReinstall` — no Bluey API.

### Domain-layer gating helper

Each context that has a `_platform` reference defines a private 3-line guard:

```dart
void _requireCapability(bool flag, String op) {
  if (!flag) {
    throw UnsupportedOperationException(
      op,
      _platform.capabilities.platformKind.name,
    );
  }
}
```

`UnsupportedOperationException` already exists at `bluey/lib/src/shared/exceptions.dart:408` with `(operation, platform)` constructor. `platformKind.name` yields `"android" / "ios" / "fake" / "other"`.

The helper composes with the existing `_ensureConnected()` discipline as a synchronous one-line guard at the top of each method. Capability checks fire **before** connection checks — "this op never works on this platform" is a stronger statement than "you are not currently connected."

The helper is duplicated across `BlueyConnection`, `BlueyServer`, and `_AndroidConnectionExtensionsImpl` (three near-identical 3-line methods). Abstracting the shared state would cost more in indirection than it would save.

### Call-site changes

**`BlueyConnection.requestMtu`** — gate on `canRequestMtu` before `_ensureConnected()`. iOS adapter's `UnsupportedError` becomes unreachable from domain code.

**`BlueyConnection.android` getter** — replace the heuristic with:
```dart
AndroidConnectionExtensions? get android {
  if (_platform.capabilities.platformKind != PlatformKind.android) return null;
  return _androidExtensions ??= _AndroidConnectionExtensionsImpl(this);
}
```

**`BlueyConnection.ios` getter** — replace the heuristic with:
```dart
IosConnectionExtensions? get ios {
  if (_platform.capabilities.platformKind != PlatformKind.ios) return null;
  return _iosExtensions;
}
```

**`_AndroidConnectionExtensionsImpl`** — every member gates on its per-feature flag:
- `bond()`, `removeBond()`, `bondState`, `bondStateChanges` → `canBond`.
- `requestPhy()`, `txPhy`, `rxPhy`, `phyChanges` → `canRequestPhy`.
- `requestConnectionParameters()`, `connectionParameters` → `canRequestConnectionParameters`.

Synchronous getters (`bondState`, `txPhy`, `rxPhy`, `connectionParameters`) and stream getters (`bondStateChanges`, `phyChanges`) throw synchronously at the call site. For streams, the throw happens before the stream is constructed, so consumers see a synchronous throw rather than a stream error — consistent with Dart conventions where stream constructors that fail throw rather than emit-and-close.

Today's `Capabilities.android` preset has all three flags `false`; consequently every Android extension method on a real Android device throws `UnsupportedOperationException("bond", "android")` until I035 Stage B lands. This is honest: those methods are unimplemented, not "no-ops that succeed silently." When Stage B lands, flipping the flags to `true` re-enables the methods automatically.

**`BlueyServer.startAdvertising`** — when `manufacturerData != null`, gate on `canAdvertiseManufacturerData`:
```dart
if (manufacturerData != null) {
  _requireCapability(
    _platform.capabilities.canAdvertiseManufacturerData,
    'startAdvertising(manufacturerData)',
  );
}
```
Calls without manufacturer data continue to work on iOS — the gate fires only when the consumer is asking for the unsupported feature. Operation name includes the parenthetical so the exception message is unambiguous.

### `BlueyClient.disconnect()` removal

Server consumers cannot reliably force-disconnect a connected client on either supported platform:
- iOS: `CBPeripheralManager` provides no force-disconnect method ([I045](../../backlog/I045-ios-disconnect-central-noop.md)).
- Android: `BluetoothGattServer.cancelConnection(device)` is unreliable for connections initiated by remote centrals ([I207](../../backlog/I207-android-force-disconnect-remote-central.md)). In the normal BLE topology centrals always initiate, so this caveat applies regardless of remote platform — Android-to-Android, iOS-to-Android, anything-to-Android.

A capability flag (`canForceDisconnectRemoteCentral`) that is `false` on every platform Bluey supports would gate a method whose only honest behavior is `throw`. Per the principle "if neither platform supports it, the cross-platform API shouldn't pretend it might," the method is removed entirely:

- `Client.disconnect()` removed from `bluey/lib/src/gatt_server/bluey_server.dart` (interface and `BlueyClient` impl).
- `BlueyPlatform.disconnectCentral` removed from `bluey_platform_interface/lib/src/platform_interface.dart`.
- iOS `disconnectCentral` impl removed from `bluey_ios/ios/Classes/PeripheralManagerImpl.swift:176-189`.
- Android `disconnectCentral` impl removed from `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/GattServer.kt:505-524` and `BlueyPlugin.kt:638`.
- iOS Pigeon stub removed from `bluey_ios/lib/src/bluey_ios.dart:124` (the `UnsupportedError` throw goes with it).
- Android Pigeon stub removed from `bluey_android/lib/src/bluey_android.dart:484`.
- Pigeon `messages.dart` files: remove `disconnectCentral` from the host API and regenerate Kotlin/Swift bindings.
- `bluey_android/android/src/test/kotlin/com/neutrinographics/bluey/GattServerTest.kt:323` test deleted.

Server consumers who need to force-kick a connected client must close the entire server (current Android workaround for non-Bluey clients). When the cooperative-disconnect feature lands as separate work, it provides a replacement for Bluey-aware peers via the lifecycle protocol.

### Defensive `UnsupportedError` throws on iOS

The remaining iOS adapter `UnsupportedError` throws (`removeBond`, `getPhy`, `requestPhy`, `getConnectionParameters`, `requestConnectionParameters`) become unreachable from domain code once `connection.android` returns `null` on iOS. They are kept as defense-in-depth: if the matrix ever lies (developer bug, custom platform-interface implementation), an `UnsupportedError` is at least an honest crash rather than silent success. The `withErrorTranslation` defensive backstop continues to handle these via the `Object` catch — they would surface as `BlueyPlatformException(null)` if reached, but should not be reachable in practice.

### `FakeBlueyPlatform` — already parameterized

`FakeBlueyPlatform` already accepts a `Capabilities` parameter (per a prior cycle that partially addressed I069). The structural fix is in place. This bundle adds the missing piece: actual tests that exercise capability-gated branches with non-default capabilities.

The fake's default `Capabilities` is updated to use `Capabilities.fake` (or its inline equivalent with `platformKind: PlatformKind.fake`), so existing tests that construct `FakeBlueyPlatform()` see the same permissive defaults they have today, just with a `platformKind` field present.

## Test plan

### New tests

`bluey/test/connection/capability_gating_test.dart`:

- `requestMtu` throws `UnsupportedOperationException("requestMtu", "ios")` when `canRequestMtu: false`.
- `connection.android` is `null` when `platformKind: PlatformKind.ios`.
- `connection.android` is non-null when `platformKind: PlatformKind.android` (regardless of which Android-only flags are set).
- `connection.ios` is non-null only when `platformKind: PlatformKind.ios`.
- `connection.android.bond()` throws when `canBond: false`.
- `connection.android.removeBond()` throws when `canBond: false`.
- `connection.android.bondState` throws synchronously when `canBond: false`.
- `connection.android.bondStateChanges` throws synchronously when `canBond: false`.
- `connection.android.requestPhy()` throws when `canRequestPhy: false`.
- `connection.android.txPhy / rxPhy / phyChanges` throw synchronously when `canRequestPhy: false`.
- `connection.android.requestConnectionParameters()` throws when `canRequestConnectionParameters: false`.
- `connection.android.connectionParameters` throws synchronously when `canRequestConnectionParameters: false`.
- `server.startAdvertising(manufacturerData: …)` throws when `canAdvertiseManufacturerData: false`.
- `server.startAdvertising(manufacturerData: null)` succeeds when `canAdvertiseManufacturerData: false` (gate fires only on the field).

Each test uses `FakeBlueyPlatform(capabilities: …)` with a custom matrix. Together they exercise both the `PlatformKind`-based getters and the per-flag method gates.

`bluey_platform_interface/test/capabilities_test.dart` (extended):

- Equality and `hashCode` include `platformKind` and `canAdvertiseManufacturerData`.
- Each preset (`android`, `iOS`, `macOS`, `windows`, `linux`, `fake`) constructs without error and has the expected `platformKind`.

### Existing test sweep

Tests that pass `Capabilities()` directly without a preset need a `platformKind:` argument. Most Bluey tests use `Capabilities.android` / `Capabilities.iOS` presets — those are unaffected. Direct calls (most notably `FakeBlueyPlatform`'s default) get `platformKind: PlatformKind.fake`.

The `Bluey.server()` returns null when `!canAdvertise` test continues to pass unchanged.

### Manual verification

Re-run the existing iOS-client / Android-server stress tests (Mixed Ops, MTU probe — the ones that surfaced the I310 `BlueyPlatformException(null)` results in the 2026-04-29 session). Expectations:
- Any operation that previously produced `BlueyPlatformException(null)` from an iOS `UnsupportedError` now produces a clean `UnsupportedOperationException` with a typed `(operation, platform)` payload.
- Or — more likely, after consumers migrate — the operation does not fire because the consumer checks `bluey.capabilities` first.
- No new `bluey-unknown` results from this surface.

## Rollout

The bundle is breaking. It lands as a single coherent release similar to [I089](../../backlog/I089-connection-platform-tagged-extensions.md) and [I099](../../backlog/I099-typed-error-translation-rewrite.md). Suggested commit sequence within the bundle:

1. **PlatformKind + heuristic replacement.** Add `PlatformKind` enum and `platformKind` field; update presets and direct call sites; replace `connection.android` / `connection.ios` heuristics with `platformKind` checks. (Closes I303.)
2. **canAdvertiseManufacturerData.** Add the field; update presets.
3. **Domain-layer gating.** Wire the `_requireCapability` helper and call-site checks for `requestMtu`, all Android extension members, and `Server.startAdvertising`. (Closes I065 and I310.)
4. **Remove `disconnectCentral`.** Delete the Dart, native, and Pigeon surface in one commit. (Closes I045-followup.)
5. **Capability-gating tests.** Add `bluey/test/connection/capability_gating_test.dart` and extend the platform-interface capability tests. (Closes I069.)
6. **Backlog + CHANGELOG + CLAUDE.md.** Mark closed entries; document breaking changes.

Each commit is independently reviewable. The bundle is shippable only after all six land.

## Backlog status after this lands

| ID | Status |
|---|---|
| I053 | closed (matrix expanded for currently-shipped surface; remaining flags are YAGNI per the load-bearing rule) |
| I065 | closed (matrix is load-bearing) |
| I069 | closed (capability-gated tests added) |
| I303 | closed (PlatformKind enum replaces heuristic) |
| I310 | closed (typed `UnsupportedOperationException` on iOS instead of `BlueyPlatformException(null)`) |
| I045-followup | closed via removal of `Client.disconnect()` and `BlueyPlatform.disconnectCentral` |

I045 itself was already fixed by `d015870` (iOS now throws); the followup tracked the matrix piece.
