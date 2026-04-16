# BlueyPeer — Stable Identity for Bluey-to-Bluey Connections

> **Note:** This spec guided initial design. The implementation diverged
> in several ways — notably `PeerConnection` was merged into
> `BlueyConnection` (single connection class with in-place upgrade),
> `connect()` auto-upgrades instead of being protocol-free, and the
> manufacturer-data scan-time marker was replaced with post-connect
> detection. The code and its doc comments are the source of truth
> for current behavior.

## Problem

Cross-platform BLE identity is fundamentally unstable. Today, connecting to a previously-seen server requires an app to scan again every time, because:

- **iOS** assigns `CBPeripheral.identifier` values that are stable within a single CoreBluetooth session but can change across sessions (app restarts, device reboots). A cached identifier from yesterday may point to nothing today.
- **Android** supports MAC randomization (default on most modern devices), so the platform-reported address for the same physical device varies over time.
- **Zombie advertisements** (already partially addressed by `requireLifecycle` on the in-flight feature branch) occur when a server app is force-killed but the OS still advertises a stale peripheral with cached services. A client that connects gets a half-dead connection whose GATT database no longer exists.

The current API requires callers to think in terms of `Device.address`, which is really a transient platform handle — not a stable reference to the logical peer an app wants to talk to.

This spec introduces **`BlueyPeer`**, a stable peer identity layered on top of the Bluey lifecycle protocol, and the supporting API surface to discover, construct, and connect to peers by a protocol-level `ServerId` rather than a platform address.

## Non-goals for v1

- **No library-managed persistence.** The library does not store `ServerId`s across app restarts on either side. The hooks to do so cleanly are part of the v1 API — `bluey.server(identity: ...)` lets the app supply a persisted `ServerId` from its own storage, and apps can save `peer.serverId` however they like. The library simply doesn't automate it.
- **No auto-reconnect.** `peer.connect()` is one-shot. The app drives retry logic.
- **No advertisement-level identity.** `serverId` lives as a readable characteristic on the control service; it is not placed in advertisement data. Discovery requires a brief connect-read-disconnect.
- **No impact on generic BLE usage.** `bluey.connect(device)` continues to work against any BLE peripheral; it just loses its protocol awareness (which moves into `BlueyPeer`).

v2+ additions (library-managed persistence, client-side peer cache, auto-reconnect) are quality-of-life conveniences on top of the v1 hooks — see "Roadmap" below.

## Solution

### 1. Protocol extension

One new readable characteristic on the existing control service:

```
control service (b1e70001-...)
├── heartbeat  (b1e70002-...)  write-with-response
├── interval   (b1e70003-...)  read  (4-byte ms, little-endian)
└── serverId   (b1e70004-...)  read  (16-byte UUID)                 ← NEW
```

`LifecycleServer` is given a `ServerId` at construction. When a client reads the `serverId` characteristic, the server responds with the 16 raw UUID bytes.

Additions to the shared kernel (`lifecycle.dart`):

- `serverIdCharUuid = 'b1e70004-0000-1000-8000-00805f9b34fb'`
- `encodeServerId(ServerId) -> Uint8List` / `decodeServerId(Uint8List) -> ServerId`
- `buildControlService()` extended to include the new characteristic

### 2. Public API

#### ServerId value object

A dedicated domain type, distinct from `UUID`, in `bluey/lib/src/peer/server_id.dart`:

```dart
class ServerId {
  const ServerId(this.value);              // canonical lowercase UUID string
  factory ServerId.generate();             // Uuid.v4()
  factory ServerId.fromBytes(Uint8List);   // expects 16 bytes
  Uint8List toBytes();

  final String value;

  @override bool operator ==(Object other);
  @override int get hashCode;
  @override String toString();
}
```

Equality by `value`; string values are normalized to lowercase; `fromBytes` rejects lengths other than 16.

#### BlueyPeer interface

In `bluey/lib/src/peer/peer.dart`:

```dart
abstract class BlueyPeer {
  /// The stable Bluey identifier of the remote server.
  ServerId get serverId;

  /// Connect to this peer. Performs a targeted scan if no cached
  /// platform identifier is known, connects, verifies the discovered
  /// server's [serverId] matches, and returns a live [Connection] with
  /// the Bluey lifecycle protocol active.
  ///
  /// Throws [PeerNotFoundException] if no matching server is advertising
  /// within [scanTimeout]. Throws [PeerIdentityMismatchException] if a
  /// cached-device-hint connection resolves to a different [serverId]
  /// (only reachable in v2+ with caching). Throws [ConnectionException]
  /// for BLE-level connection failures.
  Future<Connection> connect({
    Duration? scanTimeout,
    Duration? timeout,
  });
}
```

#### New methods on `Bluey`

```dart
/// Scan for nearby Bluey servers. Filters by the control service UUID,
/// briefly connects to each candidate to read its [serverId], and
/// returns a list of [BlueyPeer]s deduplicated by [ServerId].
Future<List<BlueyPeer>> discoverPeers({
  Duration timeout = const Duration(seconds: 5),
});

/// Construct a peer handle from a known [ServerId]. No BLE activity
/// occurs until [BlueyPeer.connect] is called.
BlueyPeer peer(ServerId serverId, {int maxFailedHeartbeats = 1});
```

#### Updated `Server`

```dart
Server? server({
  Duration? lifecycleInterval = const Duration(seconds: 10),
  ServerId? identity,               // null → library auto-generates per-process
});

// New on Server:
ServerId get serverId;
```

#### Removed

- `requireLifecycle` disappears from `Bluey.connect()`.
- `maxFailedHeartbeats` moves from `Bluey.connect()` to `bluey.peer(...)`.

`Bluey.connect(device, {Duration? timeout})` reverts to the minimal generic-BLE signature.

#### New exceptions

In `bluey/lib/src/shared/exceptions.dart`:

- `PeerNotFoundException(ServerId expected, Duration timeout)`
- `PeerIdentityMismatchException(ServerId expected, ServerId actual)`

### 3. Internal implementation

#### File layout

```
bluey/lib/src/
  lifecycle.dart                             # +serverIdCharUuid, encode/decode, extended buildControlService
  shared/
    exceptions.dart                          # +PeerNotFoundException, +PeerIdentityMismatchException
  peer/                                      (NEW directory)
    server_id.dart                           # ServerId value object
    peer.dart                                # BlueyPeer interface
    bluey_peer.dart                          # BlueyPeer impl (constructed by Bluey)
    peer_connection.dart                     # thin decorator that filters the control service from services()
    peer_discovery.dart                      # stateless helper: scan → connect → read serverId → disconnect → collect
  bluey.dart                                 # +peer(), +discoverPeers(); connect() loses requireLifecycle & maxFailedHeartbeats
  connection/
    bluey_connection.dart                    # loses lifecycle wiring, becomes pure raw-BLE
    lifecycle_client.dart                    # unchanged interface; now instantiated by BlueyPeer only
  gatt_server/
    lifecycle_server.dart                    # takes ServerId, responds to serverId reads
    bluey_server.dart                        # accepts identity: ServerId? param; generates if null
```

#### Layering discipline

- **Raw BLE layer** — `BlueyConnection` becomes protocol-free. It no longer holds a `LifecycleClient`, no longer knows about the control service, no longer filters services, and no longer sends a disconnect command on teardown. Its `services()` returns whatever the platform returned. Its `disconnect()` is a pure platform tear-down.

- **Peer-protocol layer** — `BlueyPeer` orchestrates everything protocol-related. On `peer.connect()`:

  1. Use `PeerDiscovery` to scan + connect to a candidate whose `serverId` matches.
  2. Wrap the resulting `Connection` in `PeerConnection` (the filtering decorator).
  3. Start a `LifecycleClient` against the platform connection id, with heartbeat-failure handler that sends a disconnect command (best-effort) and then disconnects the wrapped connection.
  4. Return the `PeerConnection` to the caller.

  On `connection.disconnect()` from the caller, the `PeerConnection` delegates to the underlying `BlueyConnection.disconnect()` after instructing the `LifecycleClient` to send the control-service disconnect command.

- **`PeerConnection`** — thin `Connection` decorator:
  - Delegates all methods to the underlying `BlueyConnection` by default.
  - `services()` filters out the control service.
  - `service(controlServiceUuid)` throws `ServiceNotFoundException`.
  - `hasService(controlServiceUuid)` returns false.

- **`PeerDiscovery`** — stateless helper:
  - `discover(Duration timeout)` — scans filtered by the control service UUID, briefly connects to each unique candidate to read `serverId`, disconnects, emits `BlueyPeer(serverId)`. Deduplicates by `ServerId`.
  - `connectTo(ServerId expected, Duration scanTimeout, Duration? connectTimeout)` — processes scan results **serially**: for each unique candidate, connect, read `serverId`, and either return the open connection (on match) or disconnect and continue (on mismatch). Throws `PeerNotFoundException` when the scan window expires with no match found.

#### Concurrency and reentrancy

- Multiple concurrent `peer.connect()` calls on different peers are isolated — each runs its own `PeerDiscovery`.
- Multiple concurrent `peer.connect()` calls on the *same* peer throw `StateError` on the second call. Simpler than queuing; callers can serialize if needed.
- `PeerDiscovery` uses an internally-owned `Scanner` instance so it does not interfere with any `Scanner` the app is operating for unrelated purposes.

### 4. Error handling and edge cases

**`discoverPeers`:**
- No matches → returns `[]`, not an error.
- Candidate with malformed or zero-length `serverId` → skipped silently.
- Candidate disconnects mid-read → skipped silently.
- Duplicate `ServerId` in the scan window → deduplicated.
- Platform-level scan failures (permissions, adapter off, etc.) → propagate as existing `ScanException`/`BluetoothException` types.

**`peer.connect`:**
- Multiple candidates, one matches → peer reads each, discards non-matches, returns the match.
- Matching server refuses connection → propagates the platform error after the scan window.
- Match found but heartbeat immediately fails after connection is returned → caller observes a normal transition to `disconnected` via `connection.stateChanges`. Not a special case.
- Candidate disconnects before `serverId` verified → treated as "try next."

**`Server.identity`:**
- Auto-generated identity uses `Uuid.v4()` and is logged at Server construction.
- App-supplied identity used verbatim.
- Runtime identity change is out of scope.

**`Server.connections` stream:** Unchanged. Discovery's short-lived connections briefly appear and disappear on the server's streams. The server's internal heartbeat timeouts are unaffected because discovery never writes to the heartbeat characteristic.

### 5. Testing strategy

**New unit tests:**
- `server_id_test.dart` — value object equality, generate, round-trip, validation, normalization.
- `peer_discovery_test.dart` — empty-result, multiple servers, dedup, malformed-id skip, timeout, `connectTo` match / mismatch-skip / not-found.
- `bluey_peer_test.dart` — orchestration: connect returns Connection, disconnect command sent on teardown, heartbeat failure disconnects, `serverId` exposed.
- `peer_connection_test.dart` — decorator: control service filtered, other methods delegate.

**Updated tests:**
- `lifecycle_test.dart` — keep server-side heartbeat coverage; add tests for `serverId` characteristic response, auto-generation, app-supplied override.
- The recent `bluey/test/connection/lifecycle_client_test.dart` content moves under `bluey/test/peer/`. `requireLifecycle` tests are deleted.

**New integration test:**
- `peer_e2e_test.dart` — end-to-end through `FakeBlueyPlatform`: `discoverPeers` finds multiple fakes; `peer.connect()` establishes and tears down; `bluey.peer(id).connect()` succeeds when the fake is advertising and fails with `PeerNotFoundException` when not.

**`FakeBlueyPlatform` extension:**
- Ability to advertise a peripheral with the full control service (heartbeat + interval + serverId) and a configurable `serverId` value.
- Ability to simulate multiple Bluey servers with distinct IDs concurrently.

### 6. Documentation updates

These are first-class deliverables, not afterthoughts.

**`CLAUDE.md`**
- New "Protocol layering" section explicitly naming the raw-BLE layer (`Scanner`, `Device`, `Connection`, `Server`) and the Bluey peer-protocol layer (`BlueyPeer`, `ServerId`, `discoverPeers`), with the opt-in boundary called out.
- Extends "Bounded contexts" with a Peer context.

**`BLUEY_ARCHITECTURE.md`**
- New "Peer Protocol" section covering:
  - The cross-platform identity problem (iOS identifier instability, Android MAC randomization, zombie advertisements).
  - Why `Device.address` is insufficient as a stable handle — concrete scenario.
  - The control-service extension with `serverId` and the updated ASCII diagram.
  - The `peer.connect()` flow: scan → connect → verify → heartbeat.
  - v1 limitations and v2+ roadmap (see below).

**`bluey/lib/src/peer/peer.dart` dartdoc**
- Thorough class-level comment on `BlueyPeer`: what it is, when to use `bluey.peer()` / `discoverPeers()` vs `bluey.connect()`.
- Named iOS/Android behavior: one paragraph each on why platform identifiers are unstable and how `ServerId` resolves it.
- Explicit v1 limitations block.

**`bluey/lib/src/bluey.dart` dartdoc**
- `connect()` documented as strictly raw BLE (no protocol awareness); pointer to `peer()` for Bluey-to-Bluey.

**`bluey/README.md`**
- Short "Peer protocol" section with code examples for both `discoverPeers()` and `bluey.peer(savedId)`.

### 7. Example app updates

Structural changes:

- Remove the `requireLifecycle` toggle from the connection settings dialog (keep the `maxFailedHeartbeats` slider — route it to `bluey.peer(id, maxFailedHeartbeats: ...)` when that path is taken).
- Add a new "Peers" tab, or extend the scanner UI with a "Bluey peers" section that calls `bluey.discoverPeers()` and lists results. Selecting a peer calls `peer.connect()`.
- `ConnectionScreen` accepts the returned `Connection` regardless of whether it came from `bluey.connect(device)` or `peer.connect()`. Minimal changes below the wrist.

Persistence demo (v1 reference implementation of the Path B pattern):

The example app wires up the persistence hooks end-to-end so the "connect to the restarted iOS server" scenario works without rediscovery, and so the example serves as a working reference implementation consumers can copy.

- Add `shared_preferences` as an example-app dependency.
- **Server side:** on `Server` construction, load a `ServerId` from `SharedPreferences` if present; otherwise generate one, persist it, and pass it to `bluey.server(identity: ...)`. A "reset server identity" button in the server UI clears the stored value and generates a fresh one — useful for testing the discovery path.
- **Client side:** after a successful `peer.connect()`, persist `peer.serverId` in `SharedPreferences` keyed by a slot (e.g., `'last_peer'`). On app startup, attempt `bluey.peer(stored).connect()` if a value is present; fall back to `bluey.discoverPeers()` on `PeerNotFoundException`. A "forget saved peer" action in the UI clears the stored ID.
- UI indicator: show the current server/peer `ServerId` (shortened) in the respective screen so users can visually verify identity stability across app restarts.

Out of scope for the demo:

- Account-scoped or per-user identity storage.
- Multiple saved peers (single slot only).
- Encryption or security hardening of the stored ID.

This persistence work is a separate task in the implementation plan. It depends on the library-level `Server.identity` parameter and `BlueyPeer.serverId` getter but is otherwise independent of the protocol changes.

### 8. Cross-restart stability: the app's responsibility in v1

v1 provides the hooks; the app wires them up. There are two paths:

**Path A — ephemeral identity (default):** The app does nothing. The server calls `bluey.server(...)` without an `identity`. The library generates a fresh `ServerId` on every launch. Clients must rediscover after a server restart. Fine for demos, ad-hoc pairings, and single-session workflows.

**Path B — stable identity (opt-in by the app):** The app persists a `ServerId` in whatever storage it already uses (SharedPreferences, a user-account-scoped backend, a config file, a hardware-derived value, etc.) and passes it to `bluey.server(identity: storedId)`. Clients holding that `ServerId` from a previous session reconnect via `bluey.peer(storedId).connect()` with no rescan required (beyond the targeted scan internal to `peer.connect()`).

Example (server side):
```dart
final stored = prefs.getString('bluey_server_id');
final id = stored != null ? ServerId(stored) : ServerId.generate();
await prefs.setString('bluey_server_id', id.value);
final server = bluey.server(identity: id);
```

Example (client side):
```dart
final stored = prefs.getString('bluey_peer_id');
if (stored != null) {
  try {
    final connection = await bluey.peer(ServerId(stored)).connect();
    // reuse the saved peer
  } on PeerNotFoundException {
    // fall back to discovery below
  }
}
final peers = await bluey.discoverPeers();
// show UI, save picked peer's serverId for next session
```

The library is deliberately agnostic about *where* identity is stored because storage choice is a domain concern: sometimes you want device-scoped persistence, sometimes user-scoped, sometimes tied to a particular account or session. Making that the app's call keeps the library focused and avoids imposing a storage dependency.

### 9. Roadmap beyond v1

Each step is purely additive and does not alter the v1 public API. These are conveniences, not correctness fills — v1 already supports the full feature set through app-managed storage.

- **v2: library-managed identity persistence.** Opt-in flag on `bluey.server(...)` and on `bluey.peer(...)` / `discoverPeers()` that tells the library to persist identity via a platform-appropriate default storage (e.g., `shared_preferences`). Saves apps a few lines of boilerplate for the common case.

- **v3: client-side device-identifier cache.** Persists the mapping `ServerId -> last-known platform device id` so that `bluey.peer(id).connect()` can skip the targeted scan when the platform still knows the device. Targeted scan remains as the fallback. Faster warm reconnects.

- **v4: auto-reconnect on `BlueyPeer`.** Opt-in flag that makes `BlueyPeer` a long-lived "subscription" — on disconnect it retries with backoff until explicitly told to stop. `peer.state` becomes the primary observable; the underlying `Connection` becomes an implementation detail.

Each of these is a self-contained feature and can be prioritized independently based on need.
