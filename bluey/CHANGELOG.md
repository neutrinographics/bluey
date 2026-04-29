# Changelog

## Unreleased

**Server-side peer identification:**

- New `Server.peerConnections: Stream<PeerClient>` — emits a `PeerClient` the first time a connected central sends a lifecycle heartbeat write. Mirrors the connection-side `tryUpgrade` semantics: identification is per-session; reconnect-then-heartbeat re-identifies. Consumers that only care about Bluey peers can subscribe here and ignore `connections`.
- New `PeerClient` type — composition wrapper around `Client` (server-side analog of `PeerConnection`).

**Client-side peer watch:**

- New `Bluey.watchPeer(Connection): Stream<PeerConnection?>` — emits the initial `tryUpgrade` result, then re-attempts on every `connection.servicesChanges` emission until upgrade succeeds. Completes after the first non-null peer (the resulting `PeerConnection` handles in-place handle refresh internally) or when the connection disconnects. Resilient to stale GATT caches, where a freshly-launched server's lifecycle service isn't visible to the central until a Service Changed indication lands. `tryUpgrade` remains the one-shot snapshot; its docstring now points at `watchPeer` for the streaming case.

**PeerConnection.disconnect — fast server-side detection by default (breaking):**

- `PeerConnection.disconnect()` now writes `0x00` to the lifecycle control characteristic before the platform disconnect, so the server fires its disconnect-detection path immediately instead of waiting for heartbeat-silence timeout. The courtesy write is bounded with a 1 s timeout (preserves I074: an unresponsive peer doesn't stall the disconnect).
- `PeerConnection.sendDisconnectCommand()` is **removed**. The fast-path semantics are now the default behavior of `disconnect()`. Callers who need a raw GATT disconnect with no peer-protocol involvement should call `peer.connection.disconnect()` directly.

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
