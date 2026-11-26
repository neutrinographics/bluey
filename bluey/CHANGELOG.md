# Changelog

## Unreleased

- **A link the peer dropped ends like one the app closed (H3, I381).** A
  `Connection` whose link drops now moves to `disconnected`, closes
  `stateChanges` and its other streams, and fails operations in flight with
  `DisconnectedException`. Before, only the app's own `disconnect()` cleaned
  up, and `await for` over a dropped Connection's streams never finished.
- **An ended Connection stays ended (L6, I391).** A late or repeated platform
  report can no longer move a `disconnected` Connection back to `linked`.
  **Behavior change:** a `connecting` or `connected` report from the platform
  about a live Connection no longer changes its state either.
- **One link per device, one `Connection`.** A second `bluey.connect(device)`
  to a device that is already linked returns the same `Connection` object, and
  publishes no `ConnectingEvent` or `ConnectedEvent`, since no link was opened.
- **Peer discovery leaves the app's links alone (H2, I380).**
  `discoverPeers()` and `BlueyPeer.connect()` read a device the app is already
  linked to over that link and leave it up, where the probe used to disconnect
  it. A link a probe opens is closed when the probe is done with it. One case
  is unchanged: on iOS, a probe of a device attached to our `Server` as a
  client still drops that client (I374).
- **`connectAsPeer` keeps a link the app holds.** On a device the app is
  already linked to, `connectAsPeer` leaves that link up when the device turns
  out not to be a peer, where it used to disconnect it. A link it opened itself
  is closed both when the device is not a peer and when the peer check fails,
  where a failed check used to leave it open with nothing able to close it.
- **Peer discovery stops at the end of its window (L9, I394).** Once the scan
  window closes no new probe starts: a candidate seen inside the window whose
  probe has not started when the window closes is not probed and not listed.
  `discoverPeers()` waits for the probe in flight before it returns, and a
  `stopScan` that fails is logged and no longer hides the results.
- **A `disconnect()` that fails leaves the Connection usable**, back in the
  state it had, instead of stuck in `disconnecting`.
- **A second `disconnect()` joins the one in flight.** Made while a
  disconnect is in flight, it waits for it and answers as it does, a failure
  included, where it used to return at once.
- **A probe can make the app's Connection `ready`.** A Connection the app
  holds in `linked` becomes `ready`, and reports it on `stateChanges`, when
  `discoverPeers()` or `BlueyPeer.connect()` reads over its link, since the
  probe discovers its services.
- **A failing connection-state stream ends the Connection as a drop.** An
  error on the platform's connection-state stream no longer reaches
  `Connection.stateChanges`; the Connection ends as if the link had dropped,
  and the platform is asked to close the link.
- **Disconnect reasons say what happened.** `DisconnectedException.reason` on
  an ended Connection is `requested` after the app's own `disconnect()` and
  `linkLoss` after a drop, where it was `unknown` for both.
- **`DisconnectedEvent` is published.** It was declared and never emitted; it
  is now published on `bluey.events` when a link ends, with `reason`
  `requested`, `linkLoss` or `radioOutage`. Links that peer discovery opens
  now appear on `bluey.events` like any other.
- **`BlueyEvent` is no longer sealed.** **API change:** a `switch` over every
  `BlueyEvent` needs a default branch.
- **`Mtu(value)` checks the specification's range and no longer takes
  `capabilities`.** **API change:** `Mtu(value, capabilities: caps)` is now
  `Mtu(value)`, which throws `ArgumentError` outside 23 to 517. Whether the
  platform can ask for that value is checked when the request is made:
  `connection.android?.requestMtu(mtu)` above the platform's maximum fails
  with `UnsupportedOperationException` (`requestMtu above <maximum>`). On a
  platform that cannot request an MTU at all it fails with
  `UnsupportedOperationException` (`requestMtu`) whatever the value.
- **`PlatformKind` is exported, and `Capabilities` is Bluey's own.**
  `Capabilities(platformKind: PlatformKind.android, ...)` can be written with
  `package:bluey` alone. `Capabilities` keeps its members and constants, but
  it is no longer the platform interface's class: an app that imports both
  packages now sees two types of that name, and `bluey.capabilities` answers
  Bluey's.
- **The three connection events take an optional `timestamp`.**
  `ConnectingEvent`, `ConnectedEvent` and `DisconnectedEvent` accept
  `timestamp:`, which defaults to now as before. Bluey stamps each with the
  instant the link changed, read from the clock it runs on, so under
  `fakeAsync` it is the fake clock's.
- **A Service Changed event no longer fails a link request in flight.**
  `requestMtu`, `maxWritePayload` and `readRssi` use no attribute handle, so
  they now fail only when the link ends, where a Service Changed event failed
  them with `AttributeHandleInvalidatedException`.
- **A link request rejected with status `0x80` reads as rejected.**
  `requestMtu`, `maxWritePayload`, `readRssi`, `bond`, `removeBond`,
  `requestPhy` and `requestConnectionParameters` rejected by the platform
  with GATT status
  `0x80` throw `GattOperationFailedException` with that status and leave the
  Connection connected, where they threw `DisconnectedException` with
  `evictedByServer`. On Android `0x80` is also the stack's own "out of
  resources" status, so the old reading could be wrong. GATT reads and writes
  keep today's reading.
- **The Android extension refuses through its future.** A call on
  `connection.android` refused because the radio is unavailable, because the
  platform lacks the feature, or because the MTU is above the maximum now
  answers a failed future, where it threw before returning one. Code that
  awaits the call, or tests it with `expect(() => ..., throwsA(...))`, sees no
  difference.
- **`bondStateChanges` and `phyChanges` after a radio outage answer the
  outage.** On a platform without bonding or PHY support, reading either
  stream after a radio outage answers a stream that fails with
  `StaleHandleException`, where the getter threw
  `UnsupportedOperationException`: the outage is reported before the missing
  feature, as every other member of the extension reports it.
- **A granted connection-parameters request is kept.** A first read of the
  link's connection parameters that answers after a request was granted no
  longer overwrites the granted value.
- **A platform error on the bond or PHY stream no longer reaches the app.**
  `bondStateChanges` and `phyChanges` carry no errors; such an error is
  logged (below) and the stream goes on.
- **No bond, PHY or parameter reads on other platforms.** On a platform that
  is neither Android nor iOS (`PlatformKind.fake` or `other`), connecting no
  longer reads the bond state, the PHY or the connection parameters, which
  nothing on such a platform could see.
- **Dispose is terminal for `Scanner` and `Server` (I368).** Calling
  `scan()`, `addService()`, `startAdvertising()` etc. on a disposed instance
  now throws `StaleHandleException` instead of partially restarting over
  closed streams. The exception gained a `cause` (`InvalidationCause`:
  `AdapterTransitionInvalidation(state)` or `DisposalInvalidation()`), so
  one type covers every way an instance becomes terminal. **API change:**
  `StaleHandleException.triggeringState` is now nullable (`null` for a
  disposed instance) and the constructor takes `cause:` instead of
  `triggeringState:`. Existing `on StaleHandleException` handlers that
  rebuild the instance are already correct for the dispose case.
- **Malformed lifecycle intervals are clamped (I358).** A served interval
  that is zero, negative, or too small to halve no longer drives the client
  heartbeat to a zero cadence; the new public `LifecycleInterval` value object owns
  that rule and decodes malformed wire values to the protocol default.
  **Behavior change:** `Bluey.server(lifecycleInterval:)` now throws
  `ArgumentError` for an interval shorter than `LifecycleInterval.minimum`
  (15 ms — twice the BLE-spec minimum connection interval, exposed as
  `ConnectionInterval.specMinimum`) instead of accepting a configuration
  that times out every client before a heartbeat can cross the link.

### `bluey.logEvents`

- **Connection's log lines.** `connect failed` under `bluey.connection` now
  names the failure's type (`ConnectFailed`, for one) as `exception` and
  `errorCode`, where it named the platform exception's type. A probe's
  failed connect now logs that line at `error` under `bluey.connection`,
  where it logged only a `debug` line under `bluey.peer.discovery`. A failed
  first read of a link's bond state, PHY or connection parameters logs a
  `warn` line under `bluey.connection` (`bond state read failed`, `phy read
  failed`, `connection parameters read failed`) and the default is kept.
- **Failures are named by their code.** The `failed` lines of `requestMtu`,
  `getMaximumWriteLength` and `readRssi` under `bluey.gatt` now carry a
  failure code as `errorCode` and as the data's `exception`
  (`OperationTimedOut`, `OperationRejected`, `LinkEnded`,
  `UnexpectedPlatformFailure`, ...), where they carried the thrown
  exception's type. The same goes for `exception` on a failed first read of
  the bond state, PHY or connection parameters: `StateError`, for one, is now
  `UnexpectedPlatformFailure`. A filter on the old type names misses these
  lines.
- **Bond and PHY stream errors.** An error on the platform's bond-state or
  PHY stream logs a `warn` line under `bluey.connection`, `bond state reports
  failed` or `phy reports failed`, in place of reaching the app's stream.

## 0.5.0

**Lifecycle-silence ⇄ transport reconciliation (I338):**

- `Server.disconnections` is now a faithful projection of transport-level
  connection lifetime on **both** platforms. The source of truth is the
  most authoritative signal the platform offers — a native disconnect
  callback where one exists (Android), inferred from heartbeat silence
  where it does not (iOS).
- **Behavior change (Android):** a mere heartbeat lull no longer fires
  `Server.disconnections`. Silence is advisory on Android — it surfaces
  only as a `ClientLifecycleTimeoutEvent`; the real `disconnections`
  emission waits for the platform's native disconnect callback. A peer
  that pauses past the timeout and resumes is now identified seamlessly
  with no phantom disconnect. Consumers that leaned on the old
  phantom-disconnect will see fewer, truthful `disconnections` events.
- **iOS clean reconnect on eviction:** on iOS (no native client-disconnect
  callback), heartbeat silence still drives `disconnections` and now
  *evicts* the client's session. Because the GATT link stays up, the
  evicted peer's next request is rejected with a reserved application-range
  ATT status and not dispatched; the peer self-disconnects and reconnects
  cleanly into a fresh, frame-aligned session instead of resuming
  mid-stream. This closes the I338 stream-framing corruption path (a
  paused-then-resumed peer no longer re-identifies mid-frame on
  `peerConnections`).
- New additive `DisconnectReason.evictedByServer` — lets a consumer
  distinguish an eviction-driven reconnect from a link-loss one. The
  underlying GATT link is dropped before the exception surfaces, so no
  extra cleanup is required.
- `ClientLifecycleTimeoutEvent` remains the public "peer went
  heartbeat-silent" advisory; on Android it is now emitted *without* a
  co-emitted `disconnections`.
- Native "announce-before-forward" ordering plus `resetServerSessions()`
  re-announce survivors of a prior server instance on (re)init, so a
  legitimately-connected central re-establishes its session rather than
  being evicted.
- See `bluey/docs/cross-platform-quirks.md` (section "Heartbeat silence is
  advisory on Android, a disconnect on iOS") for the consumer-facing
  divergence and tuning via `lifecycleInterval` / `peerSilenceTimeout`.

*`Capabilities.reportsCentralDisconnects` (Android `true`, iOS `false`)
was added in the Stage 1 increment that drives the branch above.*

## 0.4.0

**Peer-discovery scan-response slot (I313):**

- Android `Server.startAdvertising(peerDiscoverable: true)` now routes the
  Bluey lifecycle control UUID through the scan-response slot instead of
  the primary advertisement, freeing the 31-byte primary-AD budget for
  app-supplied UUIDs. Cross-platform peer discovery (Android server →
  iOS central) no longer fails with `ADVERTISE_FAILED_DATA_TOO_LARGE`.
- `ADVERTISE_FAILED_DATA_TOO_LARGE` now surfaces as the typed
  `AdvertisingException(AdvertisingFailureReason.dataTooBig)` instead
  of generic `bluey-unknown`.
- iOS plugin folds `scanResponseServiceUuids` into
  `CBAdvertisementDataServiceUUIDsKey` (prepended for primary-slot
  priority via overflow ordering) so cross-platform discovery works in
  both directions.

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
- `Bluey.bondedDevices` now throws `UnsupportedOperationException` on
  platforms where `capabilities.canBond` is `false` (iOS) instead of
  silently returning an empty list. Check `bluey.capabilities.canBond`
  before calling.
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
- `PeerConnection.disconnect()` now writes `0x00` to the lifecycle
  control characteristic before the platform disconnect, so the server
  fires its disconnect-detection path immediately instead of waiting
  for heartbeat-silence timeout. The courtesy write is bounded with a
  1 s timeout (preserves I074: an unresponsive peer doesn't stall the
  disconnect).
- `PeerConnection.sendDisconnectCommand()` is **removed**. The fast-path
  semantics are now the default behavior of `disconnect()`. Callers who
  need a raw GATT disconnect with no peer-protocol involvement should
  call `peer.connection.disconnect()` directly.
- `Bluey.errorStream` is **removed**. It was populated by the legacy
  string-matching `_wrapError` path and offered no information that
  isn't already available either through the typed exception thrown at
  the failing call site or through `bluey.logEvents`. Callers that
  subscribed to it should pattern-match on the typed `BlueyException`
  thrown from the failing call, or filter `bluey.logEvents` to
  `level >= warn` for an observability sink.

**New:**

- `PlatformKind` enum and `Capabilities.platformKind` discriminator.
- `Capabilities.canAdvertiseManufacturerData` flag.
- `Capabilities.fake` preset for tests.
- `Server.peerConnections: Stream<PeerClient>` — emits a `PeerClient`
  the first time a connected central sends a lifecycle heartbeat
  write. Mirrors the connection-side `tryUpgrade` semantics:
  identification is per-session; reconnect-then-heartbeat
  re-identifies. Consumers that only care about Bluey peers can
  subscribe here and ignore `connections`.
- `PeerClient` type — composition wrapper around `Client` (server-side
  analog of `PeerConnection`).
- `Bluey.watchPeer(Connection): Stream<PeerConnection?>` — emits the
  initial `tryUpgrade` result, then re-attempts on every
  `connection.servicesChanges` emission until upgrade succeeds.
  Completes after the first non-null peer (the resulting
  `PeerConnection` handles in-place handle refresh internally) or when
  the connection disconnects. Resilient to stale GATT caches, where a
  freshly-launched server's lifecycle service isn't visible to the
  central until a Service Changed indication lands. `tryUpgrade`
  remains the one-shot snapshot; its docstring now points at
  `watchPeer` for the streaming case.

**Typed error translation (I099 + I090 + I092):**

- New `bluey/lib/src/shared/error_translation.dart` houses the
  anti-corruption layer: a pure
  `translatePlatformException(Object) → BlueyException` plus a Future
  sugar `withErrorTranslation<T>(...)` with optional `LifecycleClient`
  accounting (preserves I097's user-op activity hooks). Replaces the
  prior split between `_runGattOp`'s typed catch ladder and
  `Bluey._wrapError`'s string-matching fallback.
- Every `_wrapError` call site (`configure`, `state`, `requestEnable`,
  `authorize`, `openSettings`, `connect`, `bondedDevices`, plus the
  state-stream `onError` translator) now routes through the typed
  helper. Pattern-matching on `BlueyException` subtypes is reliable on
  these paths for the first time. Behavioral note: a few sites
  previously yielded `BluetoothUnavailableException` /
  `ConnectionException` via lucky keyword matches in the platform's
  free-text error messages; post-fix they yield more accurate
  `BlueyPlatformException` / `GattTimeoutException` / etc. preserving
  the wire-level codes.
- Connection extension methods (`disconnect`,
  `connection.android?.bond` / `removeBond` / `requestPhy` /
  `requestConnectionParameters`) previously bypassed translation
  entirely — raw `PlatformException` / typed platform-interface
  exceptions could leak unwrapped to callers. Closes I090.
- Scanner `onError` translates platform errors before forwarding on
  the scan stream's error channel. Subscribers that ignored `onError`
  are unaffected; subscribers that pattern-matched on the raw error
  channel will need to update — but they were broken anyway. Closes
  I092.

## 0.3.0

**Structured logging pipeline (I307):**

- New `Bluey.logEvents: Stream<BlueyLogEvent>` — broadcast stream of domain-layer and native (Android/iOS) log events in arrival order.
- New `Bluey.setLogLevel(BlueyLogLevel level)` — filters Dart-side and pushes the filter to native sides so no Pigeon traffic is incurred for filtered events. Default `info`.
- New types: `BlueyLogEvent` (timestamp / level / context / message / data / errorCode), `BlueyLogLevel { trace, debug, info, warn, error }`.
- All internal `dev.log` calls replaced; new emissions added at meaningful points (state transitions, op-queue events, lifecycle activity, errors).
- Bootstrap caveat: events emitted during `Bluey.create()` construction are dropped if no listener has subscribed yet (broadcast stream semantics).

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
