# Changelog

## 0.4.0

**Breaking changes:**

- `Capabilities` constructor now requires a `platformKind: PlatformKind`
  argument (`enum PlatformKind { android, ios, fake, other }`). Use the
  presets (`Capabilities.android`, `.iOS`, `.fake`, etc.) where possible.
- `Client.disconnect()` removed. Server consumers needing to force-disconnect
  a connected client must close the entire server. Cooperative
  disconnect via the lifecycle protocol remains future work.
- `BlueyConnection.requestMtu` now throws `UnsupportedOperationException`
  on iOS (was: `BlueyPlatformException` with null code). Check
  `bluey.capabilities.canRequestMtu` before calling.
- Every member of `connection.android` (`bond`, `bondState`, `requestPhy`,
  etc.) now throws `UnsupportedOperationException` when its corresponding
  capability flag is `false`. With the current `Capabilities.android`
  preset (Android Stage B unimplemented), every member throws — flip the
  per-feature flags to `true` as I035 Stage B lands.
- `Server.startAdvertising(manufacturerData: …)` now throws on iOS
  (the manufacturer data was previously silently dropped — see I204).
- `connection.android` and `connection.ios` getters now dispatch on
  `Capabilities.platformKind` instead of inferring from the absence of
  Android-only flags. Bug fix on Android: `connection.android` returns
  non-null on real Android devices regardless of which Stage B flags
  have landed.

**New:**

- `PlatformKind` enum and `Capabilities.platformKind` discriminator.
- `Capabilities.canAdvertiseManufacturerData` flag.
- `Capabilities.fake` preset for tests.

## Unreleased

**Server-side peer identification:**

- New `Server.peerConnections: Stream<PeerClient>` — emits a `PeerClient` the first time a connected central sends a lifecycle heartbeat write. Mirrors the connection-side `tryUpgrade` semantics: identification is per-session; reconnect-then-heartbeat re-identifies. Consumers that only care about Bluey peers can subscribe here and ignore `connections`.
- New `PeerClient` type — composition wrapper around `Client` (server-side analog of `PeerConnection`).

**Client-side peer watch:**

- New `Bluey.watchPeer(Connection): Stream<PeerConnection?>` — emits the initial `tryUpgrade` result, then re-attempts on every `connection.servicesChanges` emission until upgrade succeeds. Completes after the first non-null peer (the resulting `PeerConnection` handles in-place handle refresh internally) or when the connection disconnects. Resilient to stale GATT caches, where a freshly-launched server's lifecycle service isn't visible to the central until a Service Changed indication lands. `tryUpgrade` remains the one-shot snapshot; its docstring now points at `watchPeer` for the streaming case.

**PeerConnection.disconnect — fast server-side detection by default (breaking):**

- `PeerConnection.disconnect()` now writes `0x00` to the lifecycle control characteristic before the platform disconnect, so the server fires its disconnect-detection path immediately instead of waiting for heartbeat-silence timeout. The courtesy write is bounded with a 1 s timeout (preserves I074: an unresponsive peer doesn't stall the disconnect).
- `PeerConnection.sendDisconnectCommand()` is **removed**. The fast-path semantics are now the default behavior of `disconnect()`. Callers who need a raw GATT disconnect with no peer-protocol involvement should call `peer.connection.disconnect()` directly.

**Typed error translation (I099 + I090 + I092):**

- `Bluey.errorStream` is **removed (breaking)**. It was populated by the legacy string-matching `_wrapError` path and offered no information that isn't already available either through the typed exception thrown at the failing call site or through `bluey.logEvents`. Callers that subscribed to it should pattern-match on the typed `BlueyException` thrown from the failing call, or filter `bluey.logEvents` to `level >= warn` for an observability sink.
- New `bluey/lib/src/shared/error_translation.dart` houses the anti-corruption layer: a pure `translatePlatformException(Object) → BlueyException` plus a Future sugar `withErrorTranslation<T>(...)` with optional `LifecycleClient` accounting (preserves I097's user-op activity hooks). Replaces the prior split between `_runGattOp`'s typed catch ladder and `Bluey._wrapError`'s string-matching fallback.
- Every `_wrapError` call site (`configure`, `state`, `requestEnable`, `authorize`, `openSettings`, `connect`, `bondedDevices`, plus the state-stream `onError` translator) now routes through the typed helper. Pattern-matching on `BlueyException` subtypes is reliable on these paths for the first time. Behavioral note: a few sites previously yielded `BluetoothUnavailableException` / `ConnectionException` via lucky keyword matches in the platform's free-text error messages; post-fix they yield more accurate `BlueyPlatformException` / `GattTimeoutException` / etc. preserving the wire-level codes.
- Connection extension methods (`disconnect`, `connection.android?.bond` / `removeBond` / `requestPhy` / `requestConnectionParameters`) previously bypassed translation entirely — raw `PlatformException` / typed platform-interface exceptions could leak unwrapped to callers. Closes I090.
- Scanner `onError` translates platform errors before forwarding on the scan stream's error channel. Subscribers that ignored `onError` are unaffected; subscribers that pattern-matched on the raw error channel will need to update — but they were broken anyway. Closes I092.

## 0.3.0

**Structured logging pipeline (I307):**

- New `Bluey.logEvents: Stream<BlueyLogEvent>` — broadcast stream of domain-layer and native (Android/iOS) log events in arrival order.
- New `Bluey.setLogLevel(BlueyLogLevel level)` — filters Dart-side and pushes the filter to native sides so no Pigeon traffic is incurred for filtered events. Default `info`.
- New types: `BlueyLogEvent` (timestamp / level / context / message / data / errorCode), `BlueyLogLevel { trace, debug, info, warn, error }`.
- All internal `dev.log` calls replaced; new emissions added at meaningful points (state transitions, op-queue events, lifecycle activity, errors).
- Bootstrap caveat: events emitted during `Bluey()` construction are dropped if no listener has subscribed yet (broadcast stream semantics).

## 0.2.0

**Breaking changes (I088, I089, I066, I300, I301)** — bundled major-version rewrite:

- **GATT routing by opaque handle (I088, I011).** `readCharacteristic` / `writeCharacteristic` / `setNotification` / `readDescriptor` / `writeDescriptor` / `notifyCharacteristic` / `notifyCharacteristicTo` now route by `int characteristicHandle` (and `int descriptorHandle` where applicable). UUIDs are retained on DTOs for display and navigation only; the wire is handle-only.
- **Singular accessors throw on ambiguity.** `Connection.service(uuid)`, `RemoteService.characteristic(uuid)`, and `RemoteCharacteristic.descriptor(uuid)` now throw `AmbiguousAttributeException(uuid, matchCount)` when more than one attribute matches the UUID. Use the new plural accessors `RemoteService.characteristics({UUID? uuid})` and `RemoteCharacteristic.descriptors({UUID? uuid})` to disambiguate.
- **Service Changed surfaces as a typed exception.** Stale-handle ops post-Service-Changed fail with `AttributeHandleInvalidatedException`. Cached service trees are invalidated; re-call `services()` to obtain fresh handles.
- **`Connection` interface trimmed (I089/I066).** Bond / PHY / connection-parameters / connection-priority / refreshGattCache moved to `connection.android?` (a typed null on iOS). `Connection.mtu` is now `Mtu` (was `int`); `Connection.requestMtu(Mtu)` takes the value object.
- **Peer composition (I300).** `Bluey.connect()` returns a raw `Connection` — no implicit peer upgrade. New `Bluey.connectAsPeer(device): Future<PeerConnection>` (throws `NotABlueyPeerException` on miss) and `Bluey.tryUpgrade(connection): Future<PeerConnection?>` for the rare post-connect upgrade path.
- **Value objects (I301).** `Mtu`, `ConnectionInterval(double ms)`, `PeripheralLatency(int events)`, `SupervisionTimeout(int ms)`, `ConnectionParameters` (with cross-field invariant), `AttributeHandle`. Validation at construction.
- **`RemoteCharacteristic.handle` and `RemoteDescriptor.handle` getters** expose the platform-assigned `AttributeHandle` for direct addressing on duplicate-UUID peripherals.

See `docs/superpowers/specs/2026-04-28-pigeon-gatt-handle-rewrite-design.md` for the full design.
