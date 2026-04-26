---
id: I300
title: Connection aggregate carries Peer-context state; bounded-context boundary inverted
category: bug
severity: high
platform: domain
status: open
last_verified: 2026-04-26
related: [I089]
---

## Symptom

The `Connection` interface declares two members that belong to the Peer bounded context:

- `bool get isBlueyServer` — a peer-protocol-aware predicate.
- `ServerId? get serverId` — a Peer-module value object.

`BlueyConnection` mutates these via an `upgrade(...)` method that takes a `LifecycleClient` and a `ServerId` and installs them in place. The Connection aggregate root is therefore not stable across its lifetime — its identity changes from "raw GATT connection" to "Bluey peer connection" mid-flight, and consumers of the public `Connection` interface have to runtime-check `isBlueyServer` to know which kind they have.

This is a bounded-context boundary violation. Connection should be upstream of Peer (Peer composes Connection); the current code makes Connection know about Peer types, inverting the dependency.

**Symptoms in code:**

- `BlueyConnection.upgrade(lifecycleClient, serverId)` — mutates Connection state with Peer-context values.
- `_upgradeIfBlueyServer` in `Bluey.connect` — Connection is created, then conditionally promoted to a Peer connection, in the same call. Two distinct domain operations are conflated.
- `Connection.service(uuid)` / `services()` / `hasService()` filter out the lifecycle control service when `isBlueyServer == true` — a Peer-protocol concern leaking into the Connection-aggregate's GATT navigation.
- Tests that need to test Connection-only behavior have to either set up a non-Bluey peer or work around the upgrade path.

## Location

- `bluey/lib/src/connection/connection.dart:140-144` — the `isBlueyServer` and `serverId` getters on the Connection interface.
- `bluey/lib/src/connection/bluey_connection.dart:281-293` — the `upgrade()` method.
- `bluey/lib/src/connection/bluey_connection.dart:306, 342, 352, 370` — the `isBlueyServer` filtering branches inside `service()`/`services()`/`hasService()`.
- `bluey/lib/src/bluey.dart:374-442` — `_upgradeIfBlueyServer` that combines Connection construction and Peer promotion.

## Root cause

When the Peer module was introduced, the choice was made to allow a `Bluey.connect(device)` call to return a `Connection` that might or might not be peer-protocol-aware, with the consumer checking `isBlueyServer` to disambiguate. This optimizes for "single entry point" ergonomics at the cost of bounded-context purity. The upgrade-in-place pattern is the implementation tax of that choice.

## Notes

The DDD-clean shape is composition rather than upgrade-in-place:

```dart
// Connection knows nothing about Peer protocol:
abstract class Connection {
  UUID get deviceId;
  ConnectionState get state;
  Stream<ConnectionState> get stateChanges;
  int get mtu;
  RemoteService service(UUID uuid);
  Future<List<RemoteService>> services({bool cache = false});
  Future<bool> hasService(UUID uuid);
  Future<int> requestMtu(int mtu);
  Future<int> readRssi();
  Future<void> disconnect();
  // (platform-tagged extensions per I089)
}

// Peer wraps Connection without mutating it:
abstract class PeerConnection {
  /// The underlying GATT connection. Composed, not inherited.
  Connection get connection;

  /// The peer's stable identity.
  ServerId get serverId;

  /// Lifecycle-protocol-specific operations live here, not on Connection.
  Future<void> sendDisconnectCommand();
  // ...
}
```

**API impact:**

- `Bluey.connect(device)` returns `Future<Connection>` — always raw. The consumer that wants peer-protocol behavior calls a separate method.
- New: `Bluey.connectAsPeer(device)` returns `Future<PeerConnection?>` — null if the device isn't a Bluey peer. Or returns `Future<PeerConnection>` and throws `NotABlueyPeerException`. Either is more honest than the runtime `isBlueyServer` check.
- `BlueyPeer.connect()` returns `Future<PeerConnection>` (already the natural return type for that path).
- `Connection.isBlueyServer` and `Connection.serverId` are removed.
- `BlueyConnection.upgrade()` is removed. The lifecycle-client installation moves into `PeerConnection`'s factory.
- `_upgradeIfBlueyServer` becomes `_tryBuildPeerConnection` and returns `PeerConnection?` instead of mutating an existing Connection.

**Consequences for adjacent code:**

- The control-service-filtering in `BlueyConnection.service` / `services` / `hasService` moves into a `PeerRemoteServiceView` (or similar) that wraps Connection's GATT navigation and hides the control service from the consumer of `PeerConnection`. The Connection-level navigation returns the full service tree unchanged.
- The two upgrade sites (`Bluey._upgradeIfBlueyServer` and `BlueyConnection._tryUpgrade` for late-discovery via Service Changed) collapse into one factory: build a `PeerConnection` if and only if the control service is present. The "late upgrade" becomes "the connection wasn't a peer; if Service Changed reveals it now is, the consumer can call `bluey.upgradeToPeer(connection)` — explicit, not implicit."
- Tests for Connection-only behavior no longer need to opt out of the upgrade path.

**Breaking change.** Yes. Plan as a major-version bump alongside I089 (platform-tagged extensions), since both restructure the `Connection` interface. A coherent two-rewrite spec covering both would be cleaner than two separate ones.

**Spec hand-off.** Suggested spec name: `2026-XX-XX-connection-peer-composition-design.md` (or fold into the I089 spec).

External references:
- Eric Evans, *Domain-Driven Design: Tackling Complexity in the Heart of Software* (2003), Chapter 14: "Maintaining Model Integrity" — the canonical treatment of bounded-context boundaries. The "Anticorruption Layer" pattern is conceptually adjacent: Peer-protocol concerns are the corrupting influence on Connection's purity.
- Eric Evans, ibid., Chapter 5: "A Model Expressed in Software" — on aggregate roots and identity. The current `BlueyConnection` violates aggregate-identity stability by mutating from one kind to another via `upgrade()`.
- Vaughn Vernon, *Implementing Domain-Driven Design* (2013), Chapter 2: "Domains, Subdomains, and Bounded Contexts" — Context Maps and acyclic upstream/downstream relationships.
- Vaughn Vernon, ibid., Chapter 13: "Integrating Bounded Contexts" — the "Open Host Service" pattern.
