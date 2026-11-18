# Slice 1: link lifecycle (design)

Date: 2026-11-18. Status: approved by Joel on 2026-11-18. Follows the [architecture foundation design](2026-11-17-architecture-foundation-design.md) and `docs/ARCHITECTURE.md`.

## 1. Summary

A link to a device gets one owner. A pure state machine in Connection's domain decides what every event does to a link, and reaching an end state releases everything the link held, whatever ended it. One registry knows every live link, so a second `connect()` returns the Connection the app already has, and peer discovery reads over a link the app holds without ever closing it. The whole Connection context moves into the target layout around that core, in two pull requests. Only the GATT client classes stay where they are, for slice 6.

This closes two of the three open High findings, H3 (I381) and H2 (I380), and with them M3 and I369, L6 (I391) and L9 (I394). I374, the iOS shared-link case, moves to slice 5 (decision 4, section 6.9).

## 2. Why

The audit of 2026-11-17 found three structural causes. Two of them meet in Connection.

- **Teardown runs on one path only.** `BlueyConnection` cleans up inside `disconnect()`. When the peer drops the link, the platform's `disconnected` event only changes a field: `stateChanges` never closes, five platform subscriptions stay alive, and a later `disconnect()` returns early because the state already says disconnected (H3). The same class lets a repeated platform event move a disconnected Connection back to `linked` (L6).
- **Nobody owns the set of live links.** `Bluey.connect()` builds a new `BlueyConnection` each time, and `PeerDiscovery` opens and closes links through the raw platform. A probe of a device the app is already connected to therefore disconnects the app's link (H2), and on the real adapters the probe's connect has already replaced that device's stream controllers, so the app's Connection is never told (M3, I369).

Fixing each symptom where it shows would leave both causes in place. `docs/ARCHITECTURE.md` section 7 names the cure: one owner per state, and teardown is a transition. This slice is where Connection gets both.

## 3. Goals, non-goals, anti-goals

**Goals**

1. A link ends the same way whatever ended it: the peer, the radio, or the app.
2. One link per device and one Connection per link, known to one registry.
3. Peer discovery and `BlueyPeer.connect()` never close a link they did not open.
4. Connection in the target layout: domain, application, ports, adapters and the edge, with every placed file clean on arrival.
5. Every finding above closed by a test that failed first, with its name struck from the known-defect roster in the same commit.

**Non-goals**

- The GATT client (service discovery and cache, Service Changed, the `Remote*` classes, `AttributeHandle`) stays unplaced until slice 6. It only stops owning link state.
- The lifecycle protocol (`LifecycleClient`, `PeerSilenceMonitor`) and the rest of Peer wait for slice 5, as does L8 (I393, a second `tryUpgrade` starting a second heartbeat).
- No Kotlin or Swift changes. M3 and I369 are in the Dart halves of the two platform packages.
- What `Bluey.dispose()` does to live links does not change here.
- `shared/exceptions.dart` and `shared/uuid.dart` do not move (section 11, call 1).

**Anti-goals**

- No new public API beyond what section 7 lists. No `AlreadyConnectedException`, no handle counting an app can see.
- No port, unit or kernel type that this slice does not use.
- No behaviour change in the second pull request beyond what section 6.12 names.

## 4. What Joel decided

1. **One link per device, one Connection.** A second `bluey.connect(device)` to a device that is already linked returns the same live `Connection` object.
2. **`Capabilities` belongs to the Platform context**, not the shared kernel. `bluey.capabilities` stays. Connection is handed the few facts it needs through its own port. `Mtu(247)` checks only the BLE specification's range, and the platform's maximum is checked when the MTU is requested. `Mtu`'s constructor loses its `capabilities` argument, an accepted breaking change.
3. **The whole Connection context moves in this slice**, in two pull requests: the lifecycle, the registry and the discovery fix first, then the rest of Connection with no behaviour change.
4. **I374, the iOS shared link, moves to slice 5.** It is fixed with the GATT Server work, where the knowledge it needs lives. This slice leaves that one case as it is today (section 6.9).

Proposed earlier and not objected to: a link ends the same way whatever ended it; an ended Connection never revives; `disconnect()` on an ended Connection completes quietly; discovery reads an already linked device over the live link; a probe closes only links it opened; no new public API.

## 5. Approaches considered

| Approach | What it is | Why not, or why |
| --- | --- | --- |
| Patch in place | Call `_cleanup()` from the platform listener, and give `Bluey` a map of connections for discovery to consult | Closes the tests and leaves two owners of link state in a 1,657-line class. The next finding of this kind would be found the same way |
| Lifecycle core only | The state machine, the registry and the `Links` port placed; bonding, PHY, parameters and RSSI left in the old class | Smaller, but `BlueyConnection` would stay split between two layouts for four more slices |
| **The whole Connection context (chosen)** | The core, plus bonding, PHY, connection parameters, MTU and link readings as their own units over their own ports | One context finished. Two pull requests keep the risky half small and reviewable |

## 6. The design

### 6.1 Language

Inside the Connection context the radio link to one device is a **link**. The app's word stays `Connection`: a Connection is the public face of one link. `ConnectionState` keeps its six values. No public name changes.

| Term | Meaning |
| --- | --- |
| Link | The radio link from this device, as GATT client, to one remote device. In code, `Link` |
| Link id | The name the radio gives a link when it opens. Every later request about that link carries it |
| Link lifecycle | The states a link moves through and what each event does to it |
| Link end | Why a link reached an end state: the app asked, the link dropped, or the radio went away |
| Radio outage | The adapter left `on` (off, unauthorized, unsupported, unknown), in Connection's own words |
| Live links | Every link that is opening, up or closing, and who is using each |
| Borrower | Code that uses a link for a short task and is not the app. Connection does not know why it borrows; today the one borrower is peer discovery |
| Session | The application object that lives as long as one link, is fed by a port's stream and holds what the radio last reported. The word is `docs/ARCHITECTURE.md`'s |

### 6.2 Where everything lands

```
lib/src/
├── api/
│   ├── failure_translation.dart          Failure to BlueyException
│   └── connection/
│       ├── connection.dart               the public Connection interface
│       ├── android_connection_extensions.dart, ios_connection_extensions.dart
│       ├── bluey_connection.dart         the thin implementation over one LinkSession
│       └── connections.dart              one public Connection per link
├── features/
│   ├── connection/
│   │   ├── domain/
│   │   │   ├── connection_state.dart     ConnectionState (public, unchanged)
│   │   │   ├── link_id.dart              LinkId
│   │   │   ├── link.dart                 Link: one link's identity and lifecycle, the pure state machine; LinkInput, LinkEnd, RadioOutage
│   │   │   ├── live_links.dart           LiveLinks: who may open, reuse and close each device's link
│   │   │   ├── connection_failure.dart   the sealed ConnectionFailure family
│   │   │   ├── connection_event.dart     ConnectingEvent, ConnectedEvent, DisconnectedEvent
│   │   │   ├── link_features.dart        what links can do on this platform        (PR 2)
│   │   │   └── value_objects/            BondState, Phy, ConnectionParameters and its three parts, Mtu, WritePayloadLimit   (PR 2)
│   │   ├── application/
│   │   │   ├── link_session.dart         runs one Link
│   │   │   ├── link_registry.dart        holds the live sessions and carries out LiveLinks' answers
│   │   │   ├── connect_device.dart       the app's connect
│   │   │   ├── borrow_link.dart          a borrower's use of a link
│   │   │   ├── bonding_session.dart, phy_session.dart, parameter_session.dart, mtu_session.dart   (PR 2)
│   │   │   ├── read_rssi.dart, read_write_payload_limit.dart                                      (PR 2)
│   │   │   └── ports/                    Links; Bonding, PhyControl, ParameterControl, MtuNegotiation, SignalStrength (PR 2)
│   │   └── infrastructure/adapters/      PlatformLinks; the five PR 2 adapters; the platform-error mapping
│   └── platform/                                                                    (PR 2)
│       ├── domain/capabilities.dart      Bluey's own Capabilities and PlatformKind
│       └── infrastructure/adapters/      platform_capabilities.dart
└── shared/
    ├── domain/                           + DeviceAddress, BlueyEvent
    ├── application/                      + EventPublisher, Log, BlueyLogLevel, BlueyLogEvent
    └── infrastructure/                   + BlueyEventBus, BlueyLogger
```

Tests mirror this tree. In-memory doubles and contract suites go in `test/fixtures/`.

### 6.3 The link lifecycle

`Link` is the domain's model of one link: its link id, the device it reaches and its lifecycle. It is a pure, synchronous value. It takes one input and answers the next `Link` and what must now happen. It holds no stream, no timer and no clock, so slice 3 can drive it with random input sequences.

A `Link` exists once the platform has connected, so its lifecycle starts at `linked`.

| State | Input | Next state | What must happen |
| --- | --- | --- | --- |
| `linked` | services discovered | `ready` | |
| `linked`, `ready` | radio reports connected or connecting | unchanged | |
| `linked`, `ready` | radio reports disconnecting | `disconnecting` | |
| `linked`, `ready` | disconnect requested | `disconnecting` | close the link |
| `disconnecting` | disconnect requested | unchanged | (the caller joins the close in flight) |
| `disconnecting` | close confirmed, or radio reports disconnected, or reports end | `disconnected`, end | release, announce |
| `disconnecting` | close failed | the state before the request | the failure goes back to the caller |
| `linked`, `ready` | radio reports disconnected, or reports end | `disconnected`, end | release, announce |
| any state that is not an end | radio outage | `invalidated`, end | release, announce |
| `disconnected`, `invalidated` | anything | unchanged | |

The last row is L6: an end state is final, so a late or repeated platform event cannot revive a link, and a disconnected link is never re-labelled invalidated. The two rows that reach `disconnected` are H3: a dropped link and a requested disconnect arrive at the same transition and ask for the same release.

An end state carries its `LinkEnd`: `requested`, `dropped`, or `radioOutage` with the `RadioOutage` that caused it. An ended link without a reason therefore cannot be built, and `disconnecting` carries the state to go back to if the close fails.

### 6.4 The session, and teardown

`LinkSession` is the application object that runs one link. It holds the current `Link`, and nothing else keeps a copy of a link's state.

- It feeds the `Link` from the `Links` port: the link's radio reports, the outage stream, and the answers to its own close request.
- It exposes the current `ConnectionState`, a stream of states that carries no errors and ends when the link ends, and the `LinkEnd` once there is one.
- **Release is part of the transition.** Anything that lives as long as the link registers a release with the session: the session's own port subscriptions, the GATT client's caches and notification controllers, and in the second pull request the bonding, PHY, parameter and MTU sessions. When the `Link` ends, the session runs every release once, whatever the cause. `disconnect()` awaits them; a drop or an outage starts them from the event.
- `whileUp(operation)` runs an operation that needs the link and answers the link's end as a failure if the link ends first, so no caller is left waiting on a dead link. It is generic in the failure it answers, so it never learns another context's failures, and the operation it is handed answers a value: nothing thrown crosses into placed code. The GATT client, which still throws, wraps each of its platform calls at that seam.
- `disconnect()` requests the transition. On a link that has already ended it answers success without calling the platform.
- When the `Link` says an announcement is due, the session publishes `DisconnectedEvent`. It logs each transition through the `Log` port under `bluey.connection`, as today.

Events are built by the application units that publish them and never by `Link` or `LiveLinks`: an event stamps itself with the current time, and the domain reads no clock.

### 6.5 Live links, connecting and borrowing

`LiveLinks` is a pure value in the domain, keyed by `DeviceAddress`. For each device it knows whether an attempt to open a link is in flight and, once there is a link, whether the app holds it and how many borrowers are using it. It keeps no copy of a link's state: asked about a device that has a link, it is handed that `Link` and reads from it whether the link is closing. It answers decisions and never touches the radio:

| Question | The device has no link | An open is in flight, or the link is closing | The link is up |
| --- | --- | --- | --- |
| The app wants this device | open a link, held by the app | wait, then ask again | reuse it; the app now holds it |
| A borrower wants this device | open a link, with one borrower | wait, then ask again | reuse it; one more borrower |

| Event | What `LiveLinks` answers |
| --- | --- |
| A borrower gives the link back | close it, if no one else is borrowing and the app does not hold it; otherwise keep it |
| A borrower keeps the link | the app now holds it |
| An open failed, or the link ended | forget the device |

Its invariants: at most one entry per device, never two attempts at once for one device, and a give-back never closes a link the app holds.

**Waiting, and whose timeout counts.** An attempt belongs to the caller that started it and runs with that caller's timeout. A caller that finds an open or a close in flight waits for it to settle and then asks again, so it reuses a link that came up, and makes its own attempt if the other one failed or the link is gone. A borrower's short connect that fails (peer discovery allows three seconds) therefore never fails the app's `connect()`, and a Connection that is about to end is never handed out. Each caller's own timeout bounds its own wait: a caller whose time runs out while waiting fails with a connect timeout and leaves the attempt in flight untouched, so a slow app connect cannot stall discovery.

`LinkRegistry` is the application object around `LiveLinks`, as `LinkSession` is around `Link`. It holds the live sessions, carries out `LiveLinks`' answers through the `Links` port, creates the `LinkSession` for each link it opens, and forgets a link as part of that link's teardown. It announces the opens it runs: `ConnectingEvent` when one starts and `ConnectedEvent` when the link is up. A caller that reuses a link opens nothing, so nothing is announced for it.

Two units use it:

- **`ConnectDevice`** is the app's `connect()`. The edge hands it the device's address and the caller's timeout, so Connection never names Discovery's `Device`. It answers the link's session, new or existing. Two concurrent calls for one device never start two platform connects.
- **`BorrowLink`** is a borrower's access. It answers a `BorrowedLink`: the session, and the two ways a borrow ends, `giveBack()` and `keep()`. Exactly one of them takes effect, once. If the app connects to a device while a borrower has its link, the app now holds that link and the give-back leaves it alone.

`connectAsPeer()` is a borrow too. It borrows the link, keeps it when the device is a Bluey peer and gives it back when it is not. A device that turns out not to be a peer therefore loses its link only if this call opened it and nobody else is using it, with no rule of its own.

### 6.6 Ports and adapters

Each port speaks Connection's language, answers `Either<ConnectionFailure, T>`, and has a contract suite run against its in-memory double and against its adapter over `FakeBlueyPlatform`.

| Port | What Connection asks of the radio | Adapter | PR |
| --- | --- | --- | --- |
| `Links` | Open a link to a device, close a link, the radio's reports about one link, and radio outages. The reports stream carries no errors and ends when the platform has nothing more to say; a stream the platform fails is logged and ended, which the lifecycle reads as a drop | `PlatformLinks` | 1 |
| `Bonding` | A link's bond state and its changes; bond; remove the bond | `PlatformBonding` | 2 |
| `PhyControl` | A link's PHY pair and its changes; request a PHY | `PlatformPhyControl` | 2 |
| `ParameterControl` | A link's connection parameters; request new ones | `PlatformParameterControl` | 2 |
| `MtuNegotiation` | A link's negotiated MTU; request an MTU; the write payload limit that follows from it | `PlatformMtuNegotiation` | 2 |
| `SignalStrength` | Read the RSSI | `PlatformSignalStrength` | 2 |

A port is one kind of fact. The MTU and the write payload limit are one fact seen twice, how much one packet carries. Connection parameters are the link's timing. Signal strength is neither.

Adapters map DTOs and errors and decide nothing. One mapping in Connection's adapters turns everything `BlueyPlatform` throws into a `ConnectionFailure`; a throw it does not recognise becomes `UnexpectedPlatformFailure` carrying the cause. A parity test holds this mapping, followed by the translator, to the exception `translatePlatformException` gives today, for every platform error a Connection operation can meet. Two rows of that table need saying.

- An operation the platform fails because the link is gone answers the link-ended failure with a drop as its end, which translates to `DisconnectedException` with `linkLoss`, as today.
- A rejected operation carries its status and translates to `GattOperationFailedException` with that status, whatever the status is. Today's shared translation reads status `0x80` as an eviction by a Bluey server on every path, Connection's included. Only a GATT read or write can be answered that way by a Bluey server, and those stay on the GATT client's path with today's translation. So neither Connection's mapping nor its translator learns the lifecycle protocol (call 10).

`ConnectionFailure` is one sealed family: the connect failed (with a reason in Connection's words), the link ended (with its `LinkEnd`), the radio is unavailable, a permission is missing, an operation timed out, an operation was rejected with a status, a feature is unsupported on this platform, a requested MTU is above the platform's maximum, and the unexpected platform failure.

### 6.7 The edge

`api/connection/` holds the public `Connection` interface, the two extension interfaces, and `BlueyConnection`, now a thin implementation: each member calls one application unit or the GATT client and translates a failure. A `Connection` is where Connection and GATT Client meet, and they meet here at the edge: Connection's own code names nothing of GATT Client.

`Connections` keeps one public object per session, which is how a second `connect()` returns the same `Connection`. It also answers the link id behind a `Connection` it made. `Bluey` reads it there for the lifecycle client, which writes to the platform with that id, and hands the same lookup to `BlueyPeer`, so neither casts.

Whether `connection.android` or `connection.ios` exists is the edge's question, answered from Platform's `Capabilities`. Connection's domain holds no fact about the public surface.

`api/failure_translation.dart` switches exhaustively over `ConnectionFailure` and throws the exception an app gets today. A link that ended becomes `DisconnectedException` (reason `requested` when the app asked, `linkLoss` when the link dropped), or `StaleHandleException` when a radio outage ended it.

The edge keeps today's stream conventions, since streams below it carry no errors: `stateChanges` replays the current state to each listener, emits the end state and closes; `servicesChanges`, `bondStateChanges` and `phyChanges` close on a disconnect and deliver `StaleHandleException` before closing on an outage.

The composition root stays `lib/src/bluey.dart` until `Bluey` itself moves. It builds the adapters, the registry and the units by constructor, and it must end this slice shorter than its 1,002 lines.

### 6.8 What stays behind

`lib/src/connection/bluey_connection.dart` keeps the GATT client: discovery and its cache, the Service Changed handler and its in-flight abort, and the three `Remote*` classes. Its link-facing class is renamed `LinkGattClient`; the file keeps its name because an unplaced file cannot be renamed, only emptied. It is handed its `LinkSession`, asks it whether the link is usable, runs its operations through `whileUp`, tells it when services are discovered, and registers its caches and notification controllers for release. It no longer subscribes to connection state or adapter state.

Those four uses are everything GATT Client asks of Connection, and they are the port slice 6 declares. Until then the GATT client holds the whole `LinkSession` (section 6.13).

In the first pull request this class also still carries bonding, PHY, parameters, MTU and the two readings, unchanged. The second pull request moves them out.

### 6.9 Peer discovery

`PeerDiscovery` stops calling `connect` and `disconnect` on the platform. `Bluey` hands it a borrow function whose type names only the public `Connection` and the two ways a borrow ends, so Peer names nothing of Connection's application. It reads the server id through the `Connection` it borrows.

- A candidate the app is already linked to is read over that link and left exactly as it was (H2). Reading may discover services, so a `linked` Connection can become `ready`; nothing else about it changes.
- A candidate nobody is linked to gets a temporary link that the probe gives back. `BlueyPeer.connect()` keeps the link of the peer it was looking for, and no longer casts to reach the platform's connection id.
- Once the scan window closes no new probe starts, and `discover()` waits for the probe in flight before it returns. A failing `stopScan` is logged and no longer hides the results (L9).

**The iOS shared link (I374) moves to slice 5 (decision 4).** On iOS one radio link carries both roles, so closing an outbound link to a device that is attached to our `Server` as a client also drops that client. A probe of such a device does exactly that, and `LiveLinks` cannot see it, because the link came in through GATT Server, not through Connection.

Joel decided to **move I374 to slice 5**, and this slice leaves the iOS case as it is today. Three facts decided it:

- The rule needs to know which clients are attached to the local server. That knowledge is GATT Server's. `Bluey.server()` builds a new `BlueyServer` on every call and keeps none (`bluey.dart:872`), so doing it now means glue in the composition root that slice 5 would rewrite as a port and a bridge.
- "Roles share one link" is not a fact `Capabilities` holds. Now it would be a test of `platformKind`; a capability is a platform-interface change that belongs with the server work.
- Skipping such a device has a cost that slice 5 can avoid. `discoverPeers()` would not list it, and `BlueyPeer.connect()` to it would fail with `PeerNotFoundException`, where today it connects. The server already knows the identity of a peer attached to it as a client, so with Peer and GATT Server placed, discovery can report that peer without probing it at all.

The alternative was to do the skip now for both probe paths, with the glue and the cost above. The app's own `connect()` is unchanged and the pattern in `cross-platform-quirks.md` still applies to it.

### 6.10 The platform packages (M3, I369)

In `bluey_android` and `bluey_ios`, Dart only:

- `connect` for a device whose streams are live reuses them. A stream handed out earlier is never orphaned.
- A device's controllers are closed and removed when its terminal disconnect event arrives and when a connect fails, not only inside `disconnect()`.

`FakeBlueyPlatform` makes the same promises, and the `Links` contract suite states them.

### 6.11 What moves into the kernel

Placed code cannot name unplaced code, so the kernel pieces Connection names move with it, each checked against the kernel's bar.

| Moves | To | Why it belongs there |
| --- | --- | --- |
| `DeviceAddress` | `shared/domain` | An identity with no context's rule, named by Discovery, Connection, GATT Server and Peer. `docs/ARCHITECTURE.md` already names it as passing |
| `BlueyEvent` | `shared/domain`, as the base of every context's events | Each context's events then live in that context's domain. `docs/ARCHITECTURE.md` calls it `DomainEvent`; it keeps its public name. This is the foundation design's approved call: `BlueyEvent` stops being sealed, so an exhaustive switch over every event needs a default branch. The 31 events of other contexts stay in `events.dart` until their slice |
| `Log` (new port), `EventPublisher`, `BlueyLogLevel`, `BlueyLogEvent` | `shared/application` | Two ports every context uses, and what the `Log` port speaks. A log level and a log record are neither an identity nor a measure, so they do not pass the bar for `shared/domain`, and no domain logs |
| `BlueyLogger`, `BlueyEventBus` | `shared/infrastructure` | Their implementations |

`LinkId` stays in Connection. `Capabilities` goes to Platform, not the kernel (decision 2).

### 6.12 The rest of Connection (second pull request)

- **Sessions and single reads.** A fact the radio keeps reporting has one session. `BondingSession`, `PhySession`, `ParameterSession` and `MtuSession` each hold the latest value of one fact about one link, fed by their port, and take the requests that change that fact, because a request and the reports that answer it are one conversation. Each registers its release with the `LinkSession`. A read that leaves nothing behind is a unit of its own: `ReadRssi` and `ReadWritePayloadLimit`.
- **`LinkFeatures`** is the small value Connection is handed about the platform: whether links can bond, request a PHY, request parameters or request an MTU, and the maximum MTU. It never changes while the app runs, so it is a value handed in at construction and not a port with one constant answer (call 11). An adapter in Connection's infrastructure maps it from the platform interface. Connection never names Platform's `Capabilities`.
- **`Capabilities`** and `PlatformKind` become Bluey's own, in `features/platform/domain`, with the same members and constants, mapped by an adapter. `lib/bluey.dart` stops re-exporting from `bluey_platform_interface`, which clears the last `public exports` entry.
- **`Mtu`**: `Mtu(value)` accepts 23 to 517, the specification's range. A request above `LinkFeatures`' maximum fails with `UnsupportedOperationException`.
- The extension implementations move to the edge. The value objects and the `_map*` functions move to the domain and the adapters.
- **The readings and the MTU request are bounded by the link's end.** Today `requestMtu`, `maxWritePayload` and `readRssi` are also aborted by a Service Changed event, as GATT operations are. None of them uses an attribute handle, so once they are Connection's they fail only when the link ends.
- **A rejected request reads as rejected.** A Connection request the platform rejects with status `0x80` becomes `GattOperationFailedException`, where today's shared translation turns it into an eviction (section 6.6). `0x80` is also the status Android's own stack reports when it is out of resources, so on these requests the old reading could be wrong.

Apart from `Mtu`'s constructor and those last two points, this pull request changes nothing an app or a test can observe.

### 6.13 Where contexts still meet after this slice

**What this slice ends**

- Peer no longer opens or closes links through the platform, and no longer builds or casts to Connection's implementation class.
- Connection no longer names Platform's `BluetoothState`, Discovery's folder for `DeviceAddress`, or anything of GATT Client. The GATT surface of a `Connection` is composed at the edge.
- Connection's failures are translated without the lifecycle protocol.
- `lib/bluey.dart` no longer re-exports the platform interface.

**What stays, and the slice that ends it**

| What still reaches across | Why it stays for now | Ended by |
| --- | --- | --- |
| The GATT client holds Connection's `LinkSession` and tells it when services are discovered | Its port is GATT Client's to declare, when that context moves | Slice 6 |
| Peer names the public `Connection` at the edge and is handed a borrow function | `PeerLink`, Peer's own port, is settled when Peer moves. Placed code cannot name the edge, so the `layers` rule forces the port then | Slice 5 |
| The lifecycle client and the silence monitor read and write through the platform with a link's id | They are Peer's protocol, still in the old `connection/` folder | Slice 5 |
| Peer discovery scans through the platform, not through Discovery | Scanning moves first | Slices 2 and 5 |
| `shared/error_translation.dart` knows the lifecycle protocol's eviction status and its accounting hooks, on the GATT paths | GATT Client's failures move with GATT Client | Slices 5 and 6 |

**What the shorter lists do not show.** Most `boundaries` entries that leave in this slice leave because a dependency is gone. Five leave without their dependency changing: the three from Peer to `connection/connection.dart`, and that file's own two, go because the public `Connection` interface moves to the edge, which `boundaries` does not judge. And the old `connection/` folder ends the slice holding only GATT Client's and Peer's code (`bluey_connection.dart`, `lifecycle_client.dart`, `peer_silence_monitor.dart`, `attribute_handle.dart`), which the lists go on counting as Connection, so the first and third rows above are on no list. The pull request's description says both, so a shorter list is not read as more than it is.

## 7. What an app can see

| Change | Kind |
| --- | --- |
| A link the peer dropped now emits `disconnected`, closes its streams and fails operations in flight with `DisconnectedException` | Fix (H3) |
| A second `connect()` to a linked device returns the same `Connection`, and announces nothing, since no link was opened | Decided |
| `discoverPeers()` and `BlueyPeer.connect()` leave the app's links alone | Fix (H2) |
| `disconnect()` that fails leaves the Connection usable instead of stuck in `disconnecting` | Fix |
| A `connecting` or `connected` report from the platform about a live Connection no longer changes its state (section 6.3's table) | Refinement (added during the build) |
| `connectAsPeer` on a device the app is already linked to leaves that link up when the device turns out not to be a peer, and a link it opened is closed when the peer check itself fails | Fix (section 6.5, plan ruling 3; added during the build) |
| A Connection the app holds in `linked` becomes `ready`, and reports it on `stateChanges`, when a probe reads over its link, because the probe discovers services (section 6.9) | Refinement (added during the build) |
| A second `disconnect()` made while one is in flight waits for it and answers as it does, a failure included, where it returned at once | Refinement (added during the build) |
| An error on the platform's connection-state stream no longer reaches `Connection.stateChanges`; the Connection ends as a drop, and the platform is asked to close the link | Refinement (added during the build) |
| `DisconnectedException.reason` on an ended Connection is `requested` after the app's own disconnect and `linkLoss` after a drop, where it was `unknown` for both | Refinement (call 4) |
| `DisconnectedEvent` is now emitted when a link ends, and probe links appear on `bluey.events` | Refinement (call 5) |
| `BlueyEvent` is no longer sealed | Breaking, approved in the foundation design |
| `Mtu(value)` without `capabilities` | Breaking, decided |
| `requestMtu`, `maxWritePayload` and `readRssi` in flight are no longer failed by a Service Changed event | Refinement (call 2) |
| A request about a link (an MTU, a PHY, parameters, a bond, a reading) that the platform rejects with status `0x80` throws `GattOperationFailedException`, where it threw `DisconnectedException` with `evictedByServer` | Refinement (call 10), second pull request |
| `PlatformKind` is exported, so `Capabilities(platformKind: ...)` can be written with `bluey` alone | Addition (call 6) |

The API dump changes for `BlueyEvent`, `Mtu` and `PlatformKind`, and for nothing else.

## 8. Findings closed

| Finding | Closed by | Proved by |
| --- | --- | --- |
| H3 (I381) | Sections 6.3 and 6.4 | The two known-defect tests, moved into the mirrored tree |
| L6 (I391) | The last row of the lifecycle table | A lifecycle test, and a test through the public API |
| H2 (I380) | Sections 6.5 and 6.9 | The known-defect test, moved |
| M3, I369 | Section 6.10 | `bluey_android`'s known-defect test, moved; the same test written for `bluey_ios`; a test for each prune path |
| L9 (I394) | Section 6.9 | New tests for the late candidate and the failing `stopScan` |
| I374 | Not closed here: moved to slice 5 (decision 4, section 6.9) | In slice 5, a test over the fake's shared-link model (I346) |

Each known-defect test moves into the mirrored tree, fails, is fixed, and has its name struck from the roster in the same commit. `bluey`'s roster keeps its six other names and `bluey_android`'s keeps M2.

## 9. Delivery

**Pull request 1, the lifecycle.** The kernel moves; Connection's domain core (state, lifecycle, live links, link id, failures, events); the session, registry, `ConnectDevice` and `BorrowLink`; `Links` with `PlatformLinks`, `InMemoryLinks` and its contract suite; the edge (`api/connection/`, `Connections`, the failure translator); the GATT client handed its session; peer discovery reworked; the two platform packages; every finding closed; `docs/ARCHITECTURE.md`, the backlog and the roadmap brought up to date, with I374 moved to slice 5's row.

**Pull request 2, the rest of Connection.** Section 6.12: no behaviour change beyond what it names.

Every list in `known_violations.dart` only shrinks in both. After the slice the `public exports` list is empty, `connection/bluey_connection.dart`, `bluey.dart` and `events.dart` have lower ceilings, and the boundary entries that name `discovery/device_address.dart` or point from Peer into `connection/bluey_connection.dart` are gone. Section 6.13 says which entries leave without their dependency changing.

## 10. Testing

- **Domain.** `Link` and `LiveLinks` are tested as tables of input and answer, every row of sections 6.3 and 6.5.
- **Application.** `LinkSession`, `LinkRegistry`, `ConnectDevice` and `BorrowLink` run against `InMemoryLinks`. No mocks.
- **Ports.** One contract suite per port in `test/fixtures/`, run against the double and against the adapter over `FakeBlueyPlatform`.
- **Edge.** The existing Connection tests move with their source and keep asserting through the public API. The 46 test files that connect through `bluey.connect` are the regression net for the second pull request.
- Test-first throughout, and the coverage floors hold: 95% of the domain, 90% of the package.
- Nothing native changes, so every gate this slice needs runs in the cloud.

## 11. Calls I made, and what is left

**Mine, for Joel to overrule**

1. **`shared/exceptions.dart` does not move to `api/` in this slice**, although one sentence of `docs/ARCHITECTURE.md` section 6 says it would. Nothing in it changes, the translator can name it where it is, and at 578 lines it cannot arrive in `api/` without splitting a sealed family, which deserves its own look. This slice corrects that sentence. `shared/uuid.dart` stays too: Connection's placed code does not name it.
2. **MTU and the write payload limit are link facts and belong to Connection**, so with RSSI they are bounded by the link's end and not by Service Changed. CLAUDE.md lists MTU under GATT Client; this slice corrects that line.
3. **Events are published by Connection's application layer, not by `Bluey`.** `ErrorEvent` on a failed connect stays with `Bluey`.
4. **Disconnect reasons.** `requested` after the app's own disconnect and `linkLoss` after a drop. Today an operation the platform fails on a dead link reports `linkLoss`, while one attempted after the drop reports `unknown`; one cause now gives one reason whichever gets there first. Five assertions in two test files pin `unknown` and change.
5. **Probe links are announced like any other link** on `bluey.events`. Today they are invisible because discovery bypasses everything.
6. **`PlatformKind` is exported** with Bluey's own `Capabilities`.
7. **The port cut** of section 6.6: one port per kind of fact, six in all.
8. **Platform errors are mapped inside Connection's adapters.** A shared classification in `shared/infrastructure` waits for the second context that needs it, in slice 2.
9. **Waiting instead of joining** (section 6.5): a caller that meets an attempt in flight waits and asks again, and only its own timeout bounds it.
10. **Connection's failures are translated without the lifecycle protocol** (section 6.6). A rejected request reads as rejected whatever its status, which changes what `0x80` means on Connection's own requests in the second pull request.
11. **`LinkFeatures` is a value handed in, not a port** (section 6.12). Decision 2 said port; the facts never change while the app runs, and the boundary is the same.
12. **The GATT client holds the whole `LinkSession`** until slice 6 gives it a port of its own (sections 6.8 and 6.13).

**Joel's, decided**

- I374 (section 6.9) moves to slice 5 (decision 4).

**Left to the builder**

- The shapes of `LinkInput`, `Link`'s answer and `LiveLinks`' entries, within the tables above, and how a waiting caller is woken.
- Method signatures on the ports and units, and how `Either` carries a success with no value. The async form of `flatMap` and `mapLeft` are added to `shared/domain` when the first unit needs them.
- The order of commits inside each pull request, and which existing tests move where.

## 12. Design review (cohesion, coupling, DDD, Clean Architecture)

**Bounded context and language.** Everything here is the Connection context except the kernel moves and Platform's `Capabilities`. Its own words are link, link id, link lifecycle, link end, radio outage, live links and borrower, and its class names use them: the model of a link is `Link`. `LiveLinks` speaks of borrowers and never of probes, which is Peer's word. The public vocabulary of CLAUDE.md's glossary is unchanged. Connection names no other context: the radio's state reaches it as `RadioOutage` through its own port, not as Platform's `BluetoothState`, and platform facts reach it as `LinkFeatures`, not as Platform's `Capabilities`. Peer and GATT Client reach Connection only from unplaced code and from the edge, which the rules allow until their slices; section 6.13 lists each reach that stays and the slice that ends it.

**Single responsibility.**

| Unit | Its one responsibility |
| --- | --- |
| `Link` | Hold one link's identity and decide what an input does to its state |
| `LiveLinks` | Decide who may open, reuse or close the link to a device |
| `LinkSession` | Run one link: feed `Link`, carry out what it asks, release on end |
| `LinkRegistry` | Hold the live sessions and carry out `LiveLinks`' answers |
| `ConnectDevice`, `BorrowLink` | One intent each: the app's connect, a borrower's use |
| `Links` and the five other ports | One kind of fact about a link each |
| `PlatformLinks` and the other adapters | Translate one port to `BlueyPlatform`, deciding nothing |
| `BlueyConnection` (edge) | Present one session as the public `Connection` and translate failures |
| `Connections` | One public object per session |
| `LinkGattClient` (unplaced) | The GATT client over one link, until slice 6 |
| `BondingSession`, `PhySession`, `ParameterSession`, `MtuSession` | Hold the latest value of one fact about one link and take its requests |
| `ReadRssi`, `ReadWritePayloadLimit` | One read each |

**Dependencies and their direction.** Domain names only `dart:core`, `package:meta` and `shared/domain`. Application names its domain, its ports and `shared/application`. Adapters name the ports, the domain and `bluey_platform_interface`. The edge names application and domain, and is handed every port by the composition root. Nothing in `features/connection` names `api/`, an unplaced file or another context. The unplaced GATT client names Connection's application, which is inward; unplaced Peer names only the public `Connection`. No dependency points out of the domain.

**Layer of each file.** As drawn in section 6.2. `Link` and `LiveLinks` are domain because they are pure decisions. The session and the registry are application because they own streams and call ports. `ConnectionState`, the events and the value objects are domain and are exported from there. The public interfaces and their thin implementations are edge.

**Cohesion and coupling.** Link state has one owner where it had three (the Connection class, the platform adapter's controllers, and discovery's raw calls), and `LiveLinks` reads it from the `Link` it is handed instead of keeping a second copy. Teardown has one path where it had two. The second pull request's units share nothing but the session's release, so each can be read and tested alone. The one coupling this slice keeps on purpose is the GATT client's hold on a `LinkSession`, which slice 6 replaces with a port.

**The architecture's three rules.** One owner per state: sections 6.3 to 6.5. Teardown is a transition: section 6.4. Completion by identity is slice 4's and is not touched.

**No abstraction ahead of its shape.** Every port, unit and kernel type here has a caller in this slice. No shared error classification, no `PeerLink` port, no narrowed view of `LinkSession` for the GATT client, no base type for units.

**Claims checked against today's source.**

- `BlueyConnection.disconnect()` returns early when the state is `disconnected` or `disconnecting` (`connection/bluey_connection.dart:793`); `_cleanup()` is called only from there (`:815`); the platform's state event reaches only `_setState` (`:217`).
- `_setState` refuses only `ready` to `linked` (`:528`), so `disconnected` to `linked` is allowed today.
- `PeerDiscovery` calls the platform's `disconnect` at `peer/peer_discovery.dart:183`, `:187` and `:238`, its `connect` at `:252`, and builds a `BlueyConnection` around a probe's link at `:171`.
- `Bluey.connect()` constructs a new `BlueyConnection` per call and is the only emitter of `ConnectingEvent` and `ConnectedEvent` (`bluey.dart:413-481`); `DisconnectedEvent` is declared (`events.dart:143`) and never emitted.
- `connectAsPeer()` disconnects the connection it just made when the device is not a peer (`bluey.dart:512-533`), which is why section 6.5 states the rule for it.
- Both platform adapters replace a device's controllers at the top of `connect` and close them only in `disconnect` (`android_connection_manager.dart:102`, `:129`; `ios_connection_manager.dart:110`, `:145`).
- `Capabilities.android` and `Capabilities.iOS` both set `canBond`, `canRequestPhy` and `canRequestConnectionParameters` to false, so the eager reads in `BlueyConnection`'s constructor (`:245-287`) do not run on a real device today and a probe's Connection costs no extra platform calls.
- `Mtu`'s factory takes `capabilities` (`connection/value_objects/mtu.dart:17`); 31 call sites pass it, all in tests and fakes; the example app uses `Mtu.fromPlatform`.
- `Bluey.dispose()` does not touch connections (`bluey.dart:960`).
- `Bluey.server()` returns a new `BlueyServer` per call and keeps no reference (`bluey.dart:872-884`), and `Capabilities` has no member about roles sharing a link, which is why I374 moves to slice 5 (section 6.9). A `PeerClient` carries the `ServerId` the client sent in its heartbeat (`peer/peer_client.dart`), which is the knowledge slice 5 can use.
- `translatePlatformException` gives `linkLoss` for `GattOperationDisconnectedException` and `evictedByServer` for the eviction status (`shared/error_translation.dart:39-52`), and `PeerDiscovery.defaultProbeTimeout` is three seconds (`peer/peer_discovery.dart:30`); sections 6.5 and 6.6 are written to both.
- `lib/bluey.dart` exports `Capabilities` alone from the platform interface, so `PlatformKind` cannot be named through `bluey` today.
- `MTU`, `maxWritePayload` and `readRssi` run through the Service Changed abort today (`:714`, `:734`, `:757`). They keep doing so in the first pull request. In the second they are bounded by the link's end instead, since none of them uses an attribute handle; no test pins the old behaviour (`test/connection/service_changed_handle_test.dart` covers reads and discovery only).
- `ConnectingEvent`, `ConnectedEvent` and `DisconnectedEvent` carry a `DeviceAddress` and nothing of Discovery's (`events.dart:121-155`), and `BlueyEvent`'s constructor stamps the current time (`events.dart:19`), which is why application units build them.
- `BlueyLogEvent` is a log record and `BlueyLogLevel` a severity (`log/log_event.dart`, `log/log_level.dart`), and `docs/ARCHITECTURE.md` section 11 sends `log/` to a port in `shared/application` and an implementation in `shared/infrastructure` without naming a home for either; section 6.11 gives them the port's.
- `translatePlatformException` reads status `0x80` as an eviction for every caller, and `requestMtu`, `maxWritePayload` and `readRssi` reach it without the lifecycle client's hooks (`connection/bluey_connection.dart:710-767`), so nothing of Peer's has to follow them into Connection.
- `LifecycleClient` reads and writes through the platform with the connection id it is handed (`connection/lifecycle_client.dart:363`), which `Bluey` and `BlueyPeer` get today by a cast (`bluey.dart:754`, `peer/bluey_peer.dart:117`).
- `boundaries` reads a target under `api/` as no context and the old `connection/` folder as Connection (`bluey_guards/lib/src/architecture/rules/boundary_rule.dart:72-94`); section 6.13's account of the lists rests on both, and on the five entries of `known_violations.dart` that name `connection/connection.dart`.
- The Android extension surface carries `mtu` and `requestMtu` beside the connection parameters, and `maxWritePayload` and `readRssi` are on `Connection` (`android_connection_extensions.dart:80-118`, `connection.dart:161-168`).
- The rosters hold the names section 8 strikes, and the six and one it keeps.

**Findings.** Five were fixed in this document before the verdict. The first draft had `Bluey` emit Connection's events, which would have left them with no owner once `Bluey` moves; the session publishes them now. A reviewer reading as the builder then found four gaps: a caller joining another caller's connect inherited its timeout and its failure; `LiveLinks` had no answer for a link that is closing; the disconnect reason differed by which path noticed the drop; and the I374 rule depended on server knowledge that Connection cannot reach. Sections 6.5, 6.6, 6.7 and 6.9 now answer them.

A second review, against DDD, cohesion, the boundaries between contexts and Clean Code, found nine more, all fixed here. The model of a link had no class of its name, and its identity lived in the application layer; it is `Link` now. `LiveLinks` kept its own copy of whether a link is closing, with no event to keep it true. Connection's rules spoke of probes, which is Peer's word. Two ports were not one kind of fact each: parameters shared one with the MTU, and one held two unrelated readings. The log's vocabulary was placed in `shared/domain` against the kernel's bar. Connection's failure translation would have known the lifecycle protocol's eviction status. `LinkFeatures` held a fact about the public surface. How Peer gets a link id was left to the builder, and this section called Peer a client of Connection's application when section 6.9 hands it a function. And no unit was named as the publisher of `ConnectingEvent`. The review also added section 6.13, so that what still reaches across contexts after this slice is written down. The one decision that was open (I374) is made: it moves to slice 5 (section 6.9).

Verdict: ready.
