---
title: Deep Review (2026-04-26) — DDD Follow-up
review_origin: |
  External code review conducted via Claude.ai chat session. This is a
  follow-up addendum to REVIEW-2026-04-26-deep-review.md, focused
  specifically on DDD / Clean Architecture concerns that were either
  not raised in the original briefing or were raised only in passing.
review_date: 2026-04-26
parent_review: REVIEW-2026-04-26-deep-review.md
---

# Deep Review (2026-04-26) — DDD Follow-up

## Purpose & framing

This document captures three DDD-specific findings that came up after
the original deep-review briefing was processed. The original briefing
addressed correctness issues and architectural rewrites at the
implementation level (Pigeon schema, threading, error wrapping,
platform-tagged extensions, etc.). This addendum addresses concerns at
the bounded-context / domain-modeling level:

1. **A bounded-context boundary violation** between Connection and Peer.
2. **Primitive obsession** in the `ConnectionParameters` value object
   and `mtu` field.
3. **Ubiquitous-language ambiguity** around device / peripheral /
   central / client / peer.

As with the parent briefing, **every entry here is a suggestion, not
a directive.** Verify before acting.

## ID allocation

The post-review additions to the parent briefing exhausted the
cross-platform cluster (I050-I099). The findings below are domain /
architectural in nature and don't fit any existing cluster. Suggested
disposition: **the CLI should pick IDs**, either by extending the ID
allocation conventions in `docs/backlog/README.md` (e.g., add a
"I300-I399 — architectural / DDD refinement" cluster) or by reusing
the next available numeric slot. Placeholder IDs are used below as
`I-DDD-1`, `I-DDD-2`, `I-DDD-3` to make discussion possible without
committing to numbers.

## Confidence levels

- **`I-DDD-1`** (Connection ↔ Peer boundary): **confidence: high.**
  The boundary violation is explicit in code (`Connection.isBlueyServer`,
  `Connection.serverId`, `BlueyConnection.upgrade(...)`).
- **`I-DDD-2`** (primitive obsession): **confidence: high.** Direct
  read of the value-object declarations.
- **`I-DDD-3`** (ubiquitous-language ambiguity): **confidence: medium.**
  The reviewer identified ambiguity but did not survey every API
  surface; the CLI should confirm the survey is complete before
  committing to a renaming plan.

---

## NEW ENTRIES — to verify and create

### I-DDD-1 — Connection bounded context bleeds into Peer (architectural rewrite)

```yaml
---
id: I-DDD-1            # CLI: pick concrete ID
title: Connection aggregate carries Peer-context state; bounded-context boundary inverted
category: bug
severity: high
platform: domain
status: open
last_verified: 2026-04-26
related: [I089]
---
```

**Confidence: high.**

**Symptom.** The `Connection` interface declares two members that
belong to the Peer bounded context:

- `bool get isBlueyServer` — a peer-protocol-aware predicate.
- `ServerId? get serverId` — a Peer-module value object.

`BlueyConnection` mutates these via an `upgrade(...)` method that
takes a `LifecycleClient` and a `ServerId` and installs them in
place. The Connection aggregate root is therefore not stable across
its lifetime — its identity changes from "raw GATT connection" to
"Bluey peer connection" mid-flight, and consumers of the public
`Connection` interface have to runtime-check `isBlueyServer` to know
which kind they have.

This is a bounded-context boundary violation. Connection should be
upstream of Peer (Peer composes Connection); the current code makes
Connection know about Peer types, inverting the dependency.

**Symptoms in code:**

- `BlueyConnection.upgrade(lifecycleClient, serverId)` — mutates
  Connection state with Peer-context values.
- `_upgradeIfBlueyServer` in `Bluey.connect` — Connection is created,
  then conditionally promoted to a Peer connection, in the same
  call. Two distinct domain operations are conflated.
- `Connection.service(uuid)` filters out the lifecycle control
  service when `isBlueyServer == true` — a Peer-protocol concern
  leaking into the Connection-aggregate's GATT navigation.
- Tests that need to test Connection-only behavior have to either
  set up a non-Bluey peer or work around the upgrade path.

**Location.**
- `bluey/lib/src/connection/connection.dart:140-144` — the
  `isBlueyServer` and `serverId` getters on the Connection interface.
- `bluey/lib/src/connection/bluey_connection.dart:260-272` — the
  `upgrade()` method.
- `bluey/lib/src/connection/bluey_connection.dart:284-345` — the
  service-filtering branches keyed on `isBlueyServer`.
- `bluey/lib/src/bluey.dart:373-441` — `_upgradeIfBlueyServer` that
  combines Connection construction and Peer promotion.

**Root cause.** When the Peer module was introduced, the choice was
made to allow a `Bluey.connect(device)` call to return a `Connection`
that might or might not be peer-protocol-aware, with the consumer
checking `isBlueyServer` to disambiguate. This optimizes for "single
entry point" ergonomics at the cost of bounded-context purity. The
upgrade-in-place pattern is the implementation tax of that choice.

**Notes.** The DDD-clean shape is composition rather than upgrade-in-place:

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

  /// Lifecycle-protocol-specific operations live here, not on
  /// Connection.
  Future<void> sendDisconnectCommand();
  // ...
}
```

**API impact:**

- `Bluey.connect(device)` returns `Future<Connection>` — always raw.
  The consumer that wants peer-protocol behavior calls a separate
  method.
- New: `Bluey.connectAsPeer(device)` returns
  `Future<PeerConnection?>` — null if the device isn't a Bluey peer.
  Or returns `Future<PeerConnection>` and throws
  `NotABlueyPeerException`. Either is more honest than the runtime
  `isBlueyServer` check.
- `BlueyPeer.connect()` returns `Future<PeerConnection>` (already
  the natural return type for that path).
- `Connection.isBlueyServer` and `Connection.serverId` are removed.
- `BlueyConnection.upgrade()` is removed. The lifecycle-client
  installation moves into `PeerConnection`'s factory.
- `_upgradeIfBlueyServer` becomes `_tryBuildPeerConnection` and
  returns `PeerConnection?` instead of mutating an existing
  Connection.

**Consequences for adjacent code:**

- The control-service-filtering in `BlueyConnection.service` /
  `services` / `hasService` moves into a `PeerRemoteServiceView`
  (or similar) that wraps Connection's GATT navigation and hides
  the control service from the consumer of `PeerConnection`. The
  Connection-level navigation returns the full service tree
  unchanged.
- The two upgrade sites (`Bluey._upgradeIfBlueyServer` and
  `BlueyConnection._tryUpgrade` for late-discovery via
  Service Changed) collapse into one factory: build a
  `PeerConnection` if and only if the control service is present.
  The "late upgrade" becomes "the connection wasn't a peer; if
  Service Changed reveals it now is, the consumer can call
  `bluey.upgradeToPeer(connection)` — explicit, not implicit."
- Tests for Connection-only behavior no longer need to opt out of
  the upgrade path.

**Breaking change.** Yes. Plan as a major-version bump alongside
I089 (platform-tagged extensions), since both restructure the
`Connection` interface. A coherent two-rewrite spec covering both
would be cleaner than two separate ones.

**Verification steps for the CLI session.**

1. Confirm the cited locations match HEAD.
2. Decide whether this entry should be merged with I089 into a single
   "Connection bounded context refinement" spec.

**External references.**

- Eric Evans, *Domain-Driven Design: Tackling Complexity in the Heart
  of Software* (2003), Chapter 14: "Maintaining Model Integrity" —
  the canonical treatment of bounded-context boundaries and the
  diagrams used to map them. The "Anticorruption Layer" pattern is
  conceptually adjacent: Peer-protocol concerns are the corrupting
  influence on Connection's purity.
- Eric Evans, ibid., Chapter 5: "A Model Expressed in Software" —
  on aggregate roots and identity. The current `BlueyConnection`
  violates aggregate-identity stability by mutating from one kind to
  another via `upgrade()`.
- Vaughn Vernon, *Implementing Domain-Driven Design* (2013),
  Chapter 2: "Domains, Subdomains, and Bounded Contexts" —
  specifically the discussion of Context Maps and how upstream/
  downstream relationships should be acyclic.
- Vaughn Vernon, ibid., Chapter 13: "Integrating Bounded Contexts" —
  the "Open Host Service" pattern, which is what `Connection`
  currently is for Peer (Connection exposes a host service Peer
  consumes), but the current code has Connection holding a
  reference back to Peer state, breaking the directional integrity.

---

### I-DDD-2 — Primitive obsession in `ConnectionParameters` and `mtu`

```yaml
---
id: I-DDD-2            # CLI: pick concrete ID
title: ConnectionParameters and mtu use primitives where domain value objects would carry validation
category: limitation
severity: low
platform: domain
status: open
last_verified: 2026-04-26
related: []
---
```

**Confidence: high.**

**Symptom.** Several BLE-spec-bounded numeric quantities are typed by
their primitive types with valid ranges documented only in
doc-comments:

- `ConnectionParameters.intervalMs: double` — spec range 7.5ms to
  4000ms (per `Connection.connectionParameters` doc-comment).
- `ConnectionParameters.latency: int` — spec range 0 to 499.
- `ConnectionParameters.timeoutMs: int` — spec range 100ms to 32000ms,
  with the additional invariant `timeoutMs > (1 + latency) * intervalMs`
  (per the doc-comment).
- `Connection.mtu: int` — spec range 23 to 517 on Android, 23 to 185
  on iOS. Platform-asymmetric upper bound.

A consumer constructing `ConnectionParameters(intervalMs: 5000, latency: 600, timeoutMs: 50)`
gets a runtime construction with no validation. The library
delegates validation to the platform, which throws platform-specific
errors at request time. The doc-comment invariants are not enforced.

**Location.**
- `bluey/lib/src/connection/connection.dart:36-78` —
  `ConnectionParameters` class.
- `bluey_platform_interface/lib/src/platform_interface.dart:46-56` —
  `PlatformConnectionParameters` mirror.
- `bluey/lib/src/connection/connection.dart:159` — `mtu` getter
  (primitive `int`).

**Root cause.** Value-object discipline costs more in Dart than in
languages with cheap newtype wrappers (Rust, Haskell, F#). The
primitive-typed fields work; the cost only shows up when an invalid
value reaches the platform and produces a confusing error.

**Notes.** The DDD-pure shape introduces value objects that enforce
spec invariants at construction:

```dart
@immutable
class ConnectionInterval {
  final double milliseconds;
  const ConnectionInterval(this.milliseconds)
      : assert(milliseconds >= 7.5 && milliseconds <= 4000,
            'connection interval out of spec range (7.5–4000 ms)');
}

@immutable
class PeripheralLatency {
  final int events;
  const PeripheralLatency(this.events)
      : assert(events >= 0 && events <= 499,
            'peripheral latency out of spec range (0–499 events)');
}

@immutable
class SupervisionTimeout {
  final int milliseconds;
  const SupervisionTimeout(this.milliseconds)
      : assert(milliseconds >= 100 && milliseconds <= 32000,
            'supervision timeout out of spec range (100–32000 ms)');
}

@immutable
class ConnectionParameters {
  final ConnectionInterval interval;
  final PeripheralLatency latency;
  final SupervisionTimeout timeout;

  ConnectionParameters({
    required this.interval,
    required this.latency,
    required this.timeout,
  }) {
    // Cross-field invariant from the BLE spec:
    final minTimeout = (1 + latency.events) * interval.milliseconds;
    if (timeout.milliseconds <= minTimeout) {
      throw ArgumentError(
        'supervision timeout must exceed (1 + latency) * interval '
        '($minTimeout ms); got ${timeout.milliseconds} ms',
      );
    }
  }
}
```

`Mtu` is more interesting because of platform asymmetry:

```dart
@immutable
class Mtu {
  final int value;
  const Mtu._(this.value);

  factory Mtu(int value, {required Capabilities capabilities}) {
    if (value < 23) {
      throw ArgumentError('MTU must be ≥ 23 (BLE spec minimum)');
    }
    if (value > capabilities.maxMtu) {
      throw ArgumentError(
        'MTU $value exceeds platform maximum ${capabilities.maxMtu}',
      );
    }
    return Mtu._(value);
  }

  /// The minimum guaranteed across all platforms.
  static const Mtu minimum = Mtu._(23);
}
```

This is the kind of value-object that earns its keep — the `Capabilities`
parameter forces the construction site to confront the platform-asymmetric
upper bound, eliminating an entire class of "user requested 517-byte
MTU on iOS" support tickets.

**Cost-benefit.** This is a refinement, not a critical fix. The
existing primitive-typed code works. The benefit is:

- Construction-time validation surfaces errors immediately at the
  call site rather than later at the platform call.
- The cross-field invariant (`timeout > (1 + latency) * interval`)
  becomes enforced, not just documented.
- The platform-asymmetric Mtu bound is encoded in the type, not
  in prose.
- Reading code that handles connection parameters, the type names
  carry domain meaning rather than just "ms" suffix conventions.

The cost is more files, more imports, more `Mtu.value` /
`interval.milliseconds` accesses at use sites.

This is worth a small follow-on backlog entry to be addressed during
one of the larger Connection-aggregate refactors (I089 or I-DDD-1).

**Verification steps for the CLI session.**

1. Confirm the four cited primitives match HEAD.
2. Consider bundling with I089 / I-DDD-1 since all three rewrite
   parts of the Connection aggregate — coherent shapes are easier to
   review than piecemeal refactors.

**External references.**

- Eric Evans, *Domain-Driven Design* (2003), Chapter 5: "A Model
  Expressed in Software" — value objects, invariants, and immutability.
- Vaughn Vernon, *Implementing Domain-Driven Design* (2013),
  Chapter 6: "Value Objects" — practical value-object design,
  including validation in constructors.
- Martin Fowler, "Primitive Obsession" code smell:
  https://refactoring.guru/smells/primitive-obsession
- Bluetooth Core Specification 5.4, Vol 6 (Low Energy Controller),
  Part B, §4.5.2: "LE Connection Parameters" — the canonical source
  for the spec ranges.
- Apple Accessory Design Guidelines (R8 BLE), §3.6: connection
  parameter recommendations for iOS:
  https://developer.apple.com/accessories/Accessory-Design-Guidelines.pdf

---

### I-DDD-3 — Ubiquitous-language ambiguity around device / peripheral / central / client / peer

```yaml
---
id: I-DDD-3            # CLI: pick concrete ID
title: Inconsistent vocabulary across the public API for "thing on the other end of the link"
category: limitation
severity: low
platform: domain
status: open
last_verified: 2026-04-26
related: []
---
```

**Confidence: medium.** The reviewer identified ambiguity by sampling
several public-API surfaces. A complete survey across all public
classes is part of the verification step.

**Symptom.** Five overlapping terms appear in the public API and
docs, used inconsistently:

- **`Device`** (`bluey/lib/src/discovery/device.dart`) — a
  discovered BLE device, regardless of role. The thing returned by
  `Scanner`. Has a UUID `id` and a platform-specific `address`.
- **"Peripheral"** — used in CoreBluetooth-aligned vocabulary
  (iOS `CBPeripheral`, the role that hosts a GATT server). Implicitly
  the "remote device" from the central's perspective.
- **`Central`** — used both in the GATT-server context (a connected
  client device speaking GATT-client role) and in the CoreBluetooth-
  aligned vocabulary (iOS `CBCentral`). `BlueyServer.connectedClients`
  uses the term but the object is named `Client`. Mixed.
- **`Client`** (`Server.connectedClients` returns `List<Client>`) —
  the peripheral-side view of a connected GATT client.
  Indistinguishable in name from "BLE Client" (which usually means
  central).
- **`BlueyPeer`** — only the Bluey-protocol-aware peer. A
  protocol-level promotion of "device + lifecycle protocol."

A consumer reading the public API encounters: `Bluey.connect(Device)`,
`Server.disconnectCentral(centralId)`, `Server.connectedClients`,
`bluey.discoverPeers()`, `BlueyPeer.connect()`. The mental model
needed to navigate this is non-obvious.

A specific confusion: `Server.disconnectCentral` and
`Server.connectedClients` use different terms for the same conceptual
entity (a connected GATT client). And `Bluey.connect(Device)` returns
a `Connection` that might or might not be a "Peer" connection — but
the device passed in was already a `Device`, not a `Peer`.

**Location.**
- `bluey/lib/src/discovery/device.dart` — `Device`.
- `bluey/lib/src/gatt_server/server.dart` (and similar) — `Client`
  and `Central` terminology.
- `bluey/lib/src/peer/bluey_peer.dart` — `BlueyPeer`.
- `bluey_platform_interface/lib/src/platform_interface.dart` —
  `PlatformDevice`, `PlatformCentral`. The platform interface is
  internally consistent but the domain layer doesn't fully follow
  through.

**Root cause.** Each module evolved with the vocabulary that fit
its bounded context:

- Discovery module: "device" (you find devices, you don't yet know
  their role).
- Server module: "central" or "client" (peripheral's-eye view).
- Peer module: "peer" (protocol-aware, role-symmetric).

The contexts each chose internally-coherent terms; the gaps appear
at the seams.

**Notes.** Two-step refinement:

**Step 1 — Glossary.** Add a glossary section to `CLAUDE.md` (or a
new `GLOSSARY.md`) that defines each term, its scope, and its
relationships:

> - **Device** — a BLE peripheral discovered via scanning. The role
>   is implicitly "remote peripheral" (the thing the local device
>   would connect *to* as a central). Use this term in the Discovery
>   bounded context.
> - **Connection** — an established GATT link to a remote Device.
>   The local role is GATT central. Use this term in the Connection
>   bounded context.
> - **Server** — the peripheral role, hosted by this device. The
>   local role is GATT server. Use this term in the GATT-Server
>   bounded context.
> - **ConnectedClient** (renamed from `Client`) — a GATT central
>   that has connected to our local Server. The remote role is
>   GATT client.
> - **Peer** — a Device or ConnectedClient that speaks the Bluey
>   lifecycle protocol. Promotion to Peer happens after control-
>   service discovery. Use this term only in the Peer bounded
>   context.

**Step 2 — Renaming.** Where the API surface allows backward-
compatible deprecations, introduce the canonical names alongside
the existing ones with `@Deprecated`:

- `Server.connectedClients` → `Server.connectedClients` returns
  `List<ConnectedClient>` (rename `Client` → `ConnectedClient`).
- `Server.disconnectCentral` → `Server.disconnect(ConnectedClient)`
  or `Server.disconnect(connectedClientId)`. (The "Central"
  terminology in the method name conflicts with the `Client` return
  type elsewhere.)
- `PlatformCentral` → `PlatformConnectedClient`.

**Cost-benefit.** This is the lowest-priority finding in this
addendum. The cost (deprecation cycle, doc updates, test renames)
is non-trivial; the benefit (a more legible API for consumers) is
real but diffuse. Worth doing during the next major-version bump
alongside I089 / I-DDD-1, not on its own.

**Verification steps for the CLI session.**

1. **Survey the public API.** The reviewer sampled but did not
   exhaustively enumerate. Run `grep -rn "class \|abstract class "`
   over the `bluey/lib/src/` tree and identify every type that names
   a "thing on the other end of the link." If the survey reveals
   the ambiguity is narrower than described (e.g., already cleaned
   up everywhere except `Server.disconnectCentral`), narrow this
   entry's scope accordingly.
2. **Decide whether to do this now or defer.** If a major-version
   bump is on the near-term roadmap, fold this into the same release.
   If not, leave the entry open as a low-priority deprecation pass
   for later.

**External references.**

- Eric Evans, *Domain-Driven Design* (2003), Chapter 2: "Communication
  and the Use of Language" — the foundational treatment of
  ubiquitous language. Specifically: "the language used by domain
  experts and developers should be the same."
- Vaughn Vernon, *Implementing Domain-Driven Design* (2013),
  Chapter 1: "Getting Started with DDD" — practical advice on
  building and maintaining a glossary.
- Bluetooth Core Specification 5.4, Vol 1, Part A, §1.2: defines
  the BLE-spec terminology (Central / Peripheral / GATT Client /
  GATT Server) that is the upstream source of the vocabulary
  collisions.

---

## Suggested order if implementing all three

If the CLI session (or a follow-up planning session) decides to act
on these entries, the suggested order is:

1. **I-DDD-3 first** (glossary only, no code changes). Pin down the
   canonical vocabulary in `CLAUDE.md`. This makes the subsequent
   refactors easier to talk about.
2. **I-DDD-1 second** (Connection ↔ Peer composition). The biggest
   structural change; do it before piecemeal refinements that would
   be invalidated by it.
3. **I-DDD-2 last** (value objects). Mostly mechanical once the
   Connection aggregate's shape is settled. Easier as a clean-up
   pass than as a parallel concern.

A unified spec covering all three (plus I089 from the parent
briefing) would be the cleanest deliverable: a single
"Connection-aggregate DDD refinement" spec under
`docs/superpowers/specs/` that addresses the bounded-context
boundary, the platform-tagged extensions, and the value-object
refinements coherently.

---

## Verification log

### 2026-04-26 — full sweep

**I-DDD-1 — verified.** All cited locations match HEAD with minor line-drift due to the I097 (peer-silence) merge:

- `connection.dart:140-144` — `isBlueyServer` and `serverId` getters present as cited.
- `bluey_connection.dart` — `upgrade()` method now at lines 281–293 (review cited 260–272); the service-filtering branches keyed on `isBlueyServer` are at lines 306, 342, 352, 370 (review cited 284–345). The pattern is identical, only the line numbers shifted from `_runGattOp`'s expansion.
- `bluey.dart` — `_upgradeIfBlueyServer` at lines 374–442 (review cited 373–441); virtually unchanged.

The "two distinct domain operations are conflated" framing is exactly right — `_upgradeIfBlueyServer` constructs a Connection then mutates it into a Peer connection via `rawConnection.upgrade(lifecycleClient, serverId)`.

**I-DDD-2 — verified.** All four primitive citations confirmed:

- `connection.dart:36-78` — `ConnectionParameters` with `intervalMs: double`, `latency: int`, `timeoutMs: int` and validation only in doc-comments.
- `platform_interface.dart:46-56` — `PlatformConnectionParameters` mirror with the same primitive shape.
- `connection.dart:159` — `int get mtu` getter.

The cross-field invariant the doc-comment mentions (`timeoutMs > (1 + latency) * intervalMs`) is documented but not enforced.

**I-DDD-3 — partially invalidated.** The broader thesis (cross-context vocabulary inconsistency) is defensible, but the specific user-facing API examples the review cites are wrong:

- **No `Server.disconnectCentral` exists in the public API.** The user-facing `Server` interface (`bluey/lib/src/gatt_server/server.dart`) uses `Client` consistently — `connectedClients` returns `List<Client>`, and disconnect is exposed as `Client.disconnect()` at line 26. `disconnectCentral` exists only at the platform-interface boundary (`_platform.disconnectCentral` called from `bluey_server.dart:540`). The Domain ↔ Platform-Interface seam is where the vocabulary mismatch lives, not within the user-facing API.
- **No domain-layer `Central` class exists.** Survey of `bluey/lib/src/` found `Client` / `BlueyClient`, `Device`, `BlueyPeer`, `PeerDiscovery`, but no `Central` class. The "Central" name surfaces only at `PlatformCentral` (`platform_interface.dart:662`).

The remaining valid concerns are narrower than the review described:

- **Domain ↔ Platform seam mismatch.** `PlatformCentral` translates to `Client` at the boundary; `PlatformDevice` translates to `Device`. This is internally consistent (each context uses its own term) but worth documenting.
- **Cross-context vocabulary.** `Device` (Discovery), `Client` (Server), `BlueyPeer` (Peer) are different terms for structurally similar concepts. A glossary would help, especially for consumers navigating between Discovery, Connection, Server, and Peer modules.

Proposed disposition for I-DDD-3 if filed: tighten the symptom to the actual seam mismatch and the cross-context terminology gap, and drop the proposed renames of `Server.disconnectCentral` (doesn't exist) and the `Client` → `ConnectedClient` proposal (which is purely cosmetic — `Client` is already consistent within the Server bounded context). The "Step 1 glossary" recommendation remains useful as-is.

### 2026-04-26 — entries filed

All three entries filed under the new I300-I399 cluster (DDD / architectural refinement):

- **[I300](I300-connection-peer-bounded-context.md)** — full original prose preserved.
- **[I301](I301-connection-params-mtu-primitive-obsession.md)** — full original prose preserved.
- **[I302](I302-ubiquitous-language-glossary.md)** — **scope-tightened** per the partial-invalidation note above. The original `Server.disconnectCentral` and `Client → ConnectedClient` rename proposals are dropped. The entry preserves a "scope-tightening note" section pointing back to this verification log for the full original framing.

`docs/backlog/README.md` updated: new "Open — DDD / architectural refinement" subsection, ID-allocation note extended with the I300-I399 cluster.

---

## External references — collected reading list

(Supplements the parent briefing's reading list; does not duplicate
the BLE / iOS / Android references already collected there.)

**Domain-Driven Design canon:**

- Eric Evans, *Domain-Driven Design: Tackling Complexity in the Heart
  of Software*, Addison-Wesley (2003). The original. Chapters 2, 5,
  and 14 are most directly relevant.
- Vaughn Vernon, *Implementing Domain-Driven Design*, Addison-Wesley
  (2013). The practical companion. Chapters 2 (bounded contexts), 6
  (value objects), 13 (context integration) are most directly relevant.
- Vaughn Vernon, *Domain-Driven Design Distilled*, Addison-Wesley
  (2016). A condensed introduction; useful as a refresher.

**Code-level refactoring patterns:**

- Martin Fowler, *Refactoring: Improving the Design of Existing Code*
  (2nd ed., 2018). Specifically: "Replace Primitive with Object,"
  "Replace Type Code with Subclasses," "Move Method."
- Martin Fowler, "Primitive Obsession":
  https://refactoring.guru/smells/primitive-obsession
- Martin Fowler, "ValueObject":
  https://martinfowler.com/bliki/ValueObject.html

**Project-internal artefacts:**

- `docs/backlog/REVIEW-2026-04-26-deep-review.md` — parent briefing
  document.
