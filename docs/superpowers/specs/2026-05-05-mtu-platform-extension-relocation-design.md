# MTU Platform-Extension Relocation + `maxWritePayload`

**Tickets:** I325 (`maxWritePayload` + relocation), I326 (Android `onMtuChanged` listener — separate follow-up).

**Status:** design draft, awaiting review. No code written.

## Problem

Two related defects on the same surface:

1. **iOS `Connection.mtu` is a lie.** `BlueyConnection._mtu` is initialized to `23` and never updated, because CoreBluetooth has no public API that exposes the negotiated GATT MTU as a number. Apps reading `connection.mtu.value` on iOS get `23`, derive `chunkSize = 20` (`mtu - 3`), and write tiny chunks even though the link is running at MTU 185+. Throughput drops 5–10×; on writes-without-response, the proportionally higher write count proportionally raises silent-drop probability.

2. **`Connection.requestMtu` lies about portability.** The cross-platform `Connection` interface exposes `requestMtu`, which throws `UnsupportedCapabilityException` on iOS at runtime. The "throw at runtime" pattern is strictly worse than the platform-extension pattern already used for `bond`, `setPhy`, `requestConnectionPriority` etc., which surface platform asymmetry at compile time via `connection.android?.bond()`.

The two defects are bundled because the fix is the same surgery: the cross-platform `Connection` should not pretend MTU is a portable concept it can faithfully report. The honest model is "Android exposes MTU, iOS exposes the derived write-payload limit".

## Goal

Four changes:

1. **Introduce a `WritePayloadLimit` value object.** Domain value object wrapping the platform-supplied payload limit. Equality by value, validates `value > 0`. Mirrors the existing `Mtu` / `ConnectionInterval` pattern (I301). Avoids primitive obsession at the GATT-spec boundary.
2. **Add `Connection.maxWritePayload({required bool withResponse}): Future<WritePayloadLimit>`.** Platform-honest, async, returns the largest single ATT write payload the platform will accept. This is the API consumers should use for chunked writes.
3. **Relocate `Connection.mtu` and `Connection.requestMtu` to `AndroidConnectionExtensions`.** Compile-time absent on iOS; matches the established pattern.
4. **Add the supporting platform plumbing.** New `BlueyPlatform.getMaximumWriteLength` method (returns raw `int` — wrapping happens at the domain seam); new Android Pigeon method; iOS Pigeon method already exists, just needs Dart-side wiring.

### In scope

- New `WritePayloadLimit` value object in `bluey/lib/src/connection/value_objects/write_payload_limit.dart`.
- New `Connection.maxWritePayload({required bool withResponse}): Future<WritePayloadLimit>`.
- Move `mtu` getter and `requestMtu(Mtu)` method from `Connection` to `AndroidConnectionExtensions`.
- New `BlueyPlatform.getMaximumWriteLength(String deviceId, {required bool withResponse}): Future<int>` on the platform interface (raw int; domain layer wraps).
- Android: new Pigeon `getMaximumWriteLength` method; Kotlin impl reads from cached negotiated MTU.
- iOS: Dart-side wiring of the existing Pigeon `getMaximumWriteLength` to `BlueyPlatform`.
- Update `FakeBlueyPlatform` and `MockBlueyPlatform` (in tests) to support `getMaximumWriteLength`.
- Migrate ~20 internal call sites (tests + example app + UI display).
- Delete the iOS-throws-on-`requestMtu` test (`capability_gating_test.dart`); the API is compile-time absent on iOS post-refactor.
- Add tests: `maxWritePayload` returns platform value; `connection.android?.mtu` and `connection.android?.requestMtu` work on Android; iOS connection has `connection.android == null`.

### Out of scope (split into I326)

- **Wiring Android's `onMtuChanged` event into the cached `mtu`.** Today the cache only updates on explicit `requestMtu` calls. After this ticket, cached `_mtu` still goes stale on peer-initiated renegotiation. Filed as I326 — orthogonal because `maxWritePayload` round-trips to the platform on every call and is unaffected.

### Won't fix here

- **Pushing iOS's MTU into Dart at connect time.** iOS doesn't expose the MTU as a number; only the derived `maximumWriteValueLength`. Even if we wanted a synthetic iOS-side MTU number, we'd derive it from `maximumWriteValueLength + 3`, which means the value object's source of truth is the write-payload limit anyway. Cleaner to admit iOS doesn't have an MTU at the API level.

## Final API

```dart
@immutable
class WritePayloadLimit {
  factory WritePayloadLimit(int value) {
    if (value <= 0) {
      throw ArgumentError.value(
        value,
        'value',
        'WritePayloadLimit must be positive',
      );
    }
    return WritePayloadLimit._(value);
  }

  /// Bypasses validation. Use only for platform-reported values.
  factory WritePayloadLimit.fromPlatform(int value) =>
      WritePayloadLimit._(value);

  const WritePayloadLimit._(this.value);

  final int value;

  @override
  bool operator ==(Object other) =>
      other is WritePayloadLimit && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'WritePayloadLimit($value)';
}

abstract class Connection {
  ConnectionState get state;
  Stream<ConnectionState> get stateChanges;
  // ... services, RSSI, etc.

  /// Largest single ATT write payload the platform will accept on this
  /// connection. Use this — not `mtu - 3` — when sizing chunked writes.
  ///
  /// On Android: derived from the negotiated GATT MTU.
  /// On iOS: returned by `CBPeripheral.maximumWriteValueLength(for:)`,
  /// which is the only API CoreBluetooth exposes.
  Future<WritePayloadLimit> maxWritePayload({required bool withResponse});

  AndroidConnectionExtensions? get android;
  IosConnectionExtensions? get ios;

  Future<void> disconnect();
}

abstract class AndroidConnectionExtensions {
  // existing
  BondState get bondState;
  Stream<BondState> get bondStateChanges;
  Future<void> bond();
  Future<void> removeBond();
  Phy get txPhy;
  Phy get rxPhy;
  Stream<PhyChange> get phyChanges;
  Future<void> requestPhy({Phy? txPhy, Phy? rxPhy});
  ConnectionParameters get connectionParameters;
  Future<void> requestConnectionParameters(ConnectionParameters params);

  // moved from Connection (new):
  Mtu get mtu;
  Future<Mtu> requestMtu(Mtu desired);
}
```

## Migration map

### Library code (1 site)

| File | Line | Before | After |
|---|---|---|---|
| `bluey/example/lib/features/connection/presentation/connection_screen.dart` | 592 | `connection.mtu.value` | `connection.android?.mtu.value ?? '—'` (UI-side null fallback) |

### Tests (read of `connection.mtu`)

| File | Lines | Action |
|---|---|---|
| `bluey/test/connection_test.dart` | 14, 25, 58–59, 140, 220 | `MockConnection.mtu` → move to a `MockAndroidConnectionExtensions`; tests assert via `connection.android!.mtu` |
| `bluey/test/bluey_connection_test.dart` | 853 | `connection.mtu` → `connection.android!.mtu` |
| `bluey/test/integration/advanced_scenarios_test.dart` | 331 | same |

### Tests (callers of `requestMtu`)

| File | Lines | Action |
|---|---|---|
| `bluey/test/connection_test.dart` | 55–60, 216, 224 | use `connection.android!.requestMtu(...)` |
| `bluey/test/bluey_connection_test.dart` | 845 | same |
| `bluey/test/connection/capability_gating_test.dart` | 79, 93–95 | iOS-throws test deleted; Android test → `connection.android!.requestMtu(...)` |
| `bluey/test/connection/bluey_connection_activity_test.dart` | 59 | `connection.android!.requestMtu(...)` |
| `bluey/test/integration/advanced_scenarios_test.dart` | 327 | same |
| `bluey/test/integration/state_machine_test.dart` | 453–459 | same |
| `bluey/test/integration/real_world_scenarios_test.dart` | 269–272 | same |

### Example app

| File | Lines | Action |
|---|---|---|
| `bluey/example/lib/features/stress_tests/infrastructure/stress_test_runner.dart` | 188, 378, 570 | `connection.android?.requestMtu(...)` — guard with `if (connection.android != null)` since stress tests run on both platforms |
| `bluey/example/test/fakes/fake_connection.dart` | 17, 32, 35–39 | move `_mtu`, `mtu` getter, `requestMtu` method to a `_FakeAndroidConnectionExtensions` returned from `fake.android` |

### Mocks throwing `UnimplementedError`

| File | Lines | Action |
|---|---|---|
| `bluey/test/peer/peer_connection_test.dart` | 90, 437 | remove `requestMtu` from `Connection`-shaped mocks (no longer in interface); add to a mock `AndroidConnectionExtensions` only if a test reads it |
| `bluey/test/peer/peer_remote_service_view_test.dart` | 91 | same |

### Platform interface (no change)

`BlueyPlatform.requestMtu(String deviceId, int mtu)` stays where it is. The decision to relocate is a *domain-layer* decision; the platform interface is a wire-style contract, and Android's `requestMtu` Pigeon method is already there. Hiding it from a sub-interface gains nothing — only the `BlueyConnection` ↔ `AndroidConnectionExtensions` plumbing changes.

## Pigeon plumbing additions

### iOS — already exists, just needs Dart-side wiring

- **Pigeon declaration** (already present): `bluey_ios/pigeons/messages.dart:434–436`
  ```dart
  @async
  int getMaximumWriteLength(String deviceId, bool withResponse);
  ```

  *Note: the existing declaration appears to be synchronous (no `@async`). Verify and add `@async` if missing — this is a platform call that may take time. Even if the underlying CoreBluetooth API is synchronous, the Pigeon-from-Dart call is always a `Future`, so this is purely a Pigeon-side decision about whether the Swift handler can be `async`.*
- **Swift impl** (already present): `bluey_ios/ios/Classes/CentralManagerImpl.swift:376–382`. Calls `peripheral.maximumWriteValueLength(for: type)`.
- **Dart-side wiring needed**: `BlueyIos` plugin class (`bluey_ios/lib/src/...`) needs to expose `getMaximumWriteLength` as a `BlueyPlatform` method that forwards to the Pigeon API.

### Android — new

- **Pigeon declaration** (new): `bluey_android/pigeons/messages.dart`, alongside `requestMtu`:
  ```dart
  @async
  int getMaximumWriteLength(String deviceId, bool withResponse);
  ```
- **Kotlin impl** (new): in `ConnectionManager.kt`, return the cached negotiated MTU minus 3 for both write types. The `withResponse` parameter is preserved for API symmetry with iOS but produces the same value on Android (BluetoothGatt's ATT MTU does not distinguish).
- **Regenerate** Pigeon outputs: `dart run pigeon --input pigeons/messages.dart`.
- **Dart-side wiring needed**: `BlueyAndroid` plugin class (`bluey_android/lib/src/...`).

### Platform interface

New abstract method on `BlueyPlatform`:

```dart
/// Largest single ATT write payload the platform will accept for the
/// active connection to [deviceId]. See [Connection.maxWritePayload].
Future<int> getMaximumWriteLength(
  String deviceId, {
  required bool withResponse,
});
```

## Translation seam

```
Pigeon (raw int)              Platform interface (raw int)        Domain (value object)
       │                              │                                    │
       ▼                              ▼                                    ▼
getMaximumWriteLength    →    BlueyPlatform                  →    Connection.maxWritePayload
  (deviceId, withResp)            .getMaximumWriteLength               returns
   returns: int                      returns: int                      WritePayloadLimit
                                                                       (wrapped via
                                                                        WritePayloadLimit
                                                                        .fromPlatform)
```

The `WritePayloadLimit` type does not cross the Pigeon boundary, mirroring how `Mtu` is unwrapped at `BlueyPlatform.requestMtu(deviceId, int)`.

## Decisions

### D1 — `requestMtu` stays on the platform interface

The cross-platform `BlueyPlatform.requestMtu` is not symptomatic — iOS implements it as a noop/auto-negotiation result, which is fine at the wire-level abstraction. The lie is at the *domain* layer where `Connection.requestMtu` claims portability. Only the domain-layer surface relocates.

### D2 — `canRequestMtu` capability flag stays on `Capabilities`

`Capabilities.canRequestMtu` is currently used to gate `BlueyConnection.requestMtu` at runtime. After the relocation, the gate moves into `_AndroidConnectionExtensionsImpl.requestMtu`. The flag itself is still useful for runtime introspection (e.g., a UI that asks "should I show an MTU control?") and matches the pattern of `canBond`, `canRequestPhy`, etc. Keep.

### D3 — `gatt_timeouts.requestMtu` stays on the cross-platform `GattTimeouts`

The timeouts struct is configuration, not API surface. Even though the timeout is Android-only at the operational level, it's a single concrete value users may want to tune from a single place. No reason to fragment.

### D4 — `Mtu` value object stays cross-platform

`Mtu` is exported from `bluey/lib/src/connection/connection.dart` and re-exported via `package:bluey/bluey.dart`. It's a value object with no platform dependency; only the *getter that returns it* moves. Keep it where it is.

### D5 — `_AndroidConnectionExtensionsImpl` accesses cached MTU via private methods on `BlueyConnection`

Established pattern from `bond`, `requestPhy`, etc.: the impl class wraps `BlueyConnection` and calls private methods (`_bondStateValue`, `_requestPhyImpl`). Add `_mtuValue`, `_requestMtuImpl` to `BlueyConnection`. The cached `_mtu` field stays where it is.

### D6 — iOS `connection.android` is null; readers must handle that

The example UI's display of `connection.mtu.value` becomes `connection.android?.mtu.value ?? '—'`. This is intentional: it shows app developers the platform-asymmetry at the source. The example UI is a teaching surface; let it teach.

### D7 — `capability_gating_test.dart` "iOS throws on requestMtu" test is deleted, not migrated

The test exists to assert runtime behavior of an API that is now compile-time absent on iOS. There's no equivalent assertion to make — the type system enforces absence. Delete entirely.

### D8 — `withResponse` parameter is required, not defaulted

Forces the caller to think about which write type they're using. Defaulting to either value risks silent truncation on writes-with-response if the larger limit is used.

### D9 — `WritePayloadLimit` value object, not raw `int`

Per CLAUDE.md: "Value objects are immutable with equality by value." The existing `Mtu` value object validates `23 ≤ value ≤ maxMtu`; `WritePayloadLimit` follows the same pattern with a weaker invariant (`value > 0`) since the platform is the source of truth. The seam unwraps `Future<int>` from Pigeon and wraps to `WritePayloadLimit` in `BlueyConnection`, mirroring how `Mtu.fromPlatform(int)` is constructed at the same boundary. Avoids primitive obsession at the GATT-spec boundary.

The existing `Connection.rssi: int` is a known inconsistency (raw primitive) — this ticket does not fix it, but the new code does not perpetuate it.

## Test strategy

### Red tests

1. **Value object** — `bluey/test/connection/value_objects/write_payload_limit_test.dart` (new):
   - `WritePayloadLimit(0)` and `WritePayloadLimit(-1)` throw `ArgumentError`.
   - `WritePayloadLimit.fromPlatform(0)` does not throw (platform is authoritative).
   - Equality: `WritePayloadLimit(100) == WritePayloadLimit(100)`; `hashCode` consistent.
   - `toString()` includes the value.

2. **Domain-layer `maxWritePayload`** — `bluey/test/connection/max_write_payload_test.dart` (new):
   - `connection.maxWritePayload(withResponse: false)` returns `WritePayloadLimit` wrapping the fake's without-response value.
   - `connection.maxWritePayload(withResponse: true)` returns `WritePayloadLimit` wrapping the fake's with-response value (may differ on iOS-cap fakes).
   - Platform error from `getMaximumWriteLength` is wrapped via `withErrorTranslation` into the same exception types as other connection ops.

2. **Platform-extension relocation** — additions to `bluey/test/connection/bluey_connection_test.dart` (or new file):
   - `connection.android?.mtu` returns the cached value on Android.
   - `connection.android?.requestMtu(...)` updates the cache and returns the negotiated value.
   - On iOS-cap fake (`Capabilities.iOS`), `connection.android` returns null.
   - Compile-time: `Connection.mtu` no longer exists at the type level (assertion: `dart analyze` passes only after migration).

### Migration tests

For each call-site change in the migration map: edit the test, re-run, expect green.

### Coverage targets

Domain layer ≥90%. The new `maxWritePayload` is one round-trip method; coverage will be 100% with three tests (with/without response + error path).

## Sequencing

Each phase is a green checkpoint — full test suite passes, `flutter analyze` clean.

1. **Phase 1: Plumbing** — add `WritePayloadLimit` value object (with red tests first); add `BlueyPlatform.getMaximumWriteLength`, `FakeBlueyPlatform.getMaximumWriteLength`, iOS Dart-side plugin wiring (Pigeon already there), Android Pigeon + Kotlin + Dart-side plugin.
2. **Phase 2: `maxWritePayload`** — red tests, then `Connection.maxWritePayload` interface + `BlueyConnection` impl wrapping the platform `int` in `WritePayloadLimit.fromPlatform`. **No interface removals yet.**
3. **Phase 3: Relocation** — add `mtu` / `requestMtu` to `AndroidConnectionExtensions`; implement in `_AndroidConnectionExtensionsImpl`; remove from `Connection` interface; remove from `BlueyConnection` (move to private methods).
4. **Phase 4: Migration** — fix every call site listed above. Delete the iOS-throws test.
5. **Phase 5: Verify** — full test suite, `flutter analyze`, coverage check.

## Risks

- **R1: I missed a call site.** Mitigation: post-Phase-3 compile failure will surface every reader. The migration map is grep-driven; there should be no surprises, but the compiler is the backstop.
- **R2: Stress test infrastructure is platform-conditional and may break in non-obvious ways.** Mitigation: check the stress-test runner manually after Phase 4; it currently calls `connection.requestMtu` unconditionally on both platforms.
- **R3: `peer_connection_test.dart` mocks shaped like `Connection`.** Once `mtu` and `requestMtu` are gone from the interface, those mocks no longer need to implement them. Risk is forgetting to remove the mock methods (analyzer will warn about unused members). Trivial to fix.
- **R4: Android `withResponse` parameter is meaningless at the platform level.** We accept it and return the same value regardless. If a future Android update distinguishes them, the API is already shaped to support it. No risk; documenting the choice.

## Non-goals

- Surfacing iOS's MTU as a synthetic Dart-side number.
- Auto-requesting max MTU on connect.
- Notification fragment sizing (`maxNotifyPayload`) — separate ticket if needed.
- Exposing `maximumWriteValueLength` per characteristic (Apple's API is per-peripheral, not per-characteristic).
