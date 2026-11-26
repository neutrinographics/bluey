# Bluey slice 1: link lifecycle (implementation plan)

Nov 18, 2026 · @Joel

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every link to a device one owner, so a link ends the same way whatever ended it, a second `connect()` returns the Connection the app already has, and peer discovery never closes a link it did not open; and finish the Connection context in the target layout.

**Architecture:** A pure `Link` state machine and a pure `LiveLinks` table in Connection's domain make every decision. `LinkSession` and `LinkRegistry` in the application layer carry those decisions out through one port, `Links`, and run each link's releases once when it ends. The public `Connection` becomes a thin edge class over one session, the GATT client is handed that session, and peer discovery is handed a borrow function. The second pull request moves bonding, PHY, connection parameters, MTU and the two readings onto five more ports with a session or a read each, and gives Platform its own `Capabilities`.

**Tech Stack:** Dart 3.13 on Flutter 3.47.2, `flutter_test`, `fake_async`, `package:clock`, `package:meta`, the `bluey_guards` gates (architecture rules, list growth, public API dump, coverage gate, known-defect run), GitHub Actions.

**Spec:** [Bluey slice 1: link lifecycle (design)](https://claude.ai/artifact/86wbVvAwmHMJqMW3G23cTb), approved by Joel on 2026-11-18, which Task 1 commits as `docs/superpowers/specs/2026-11-18-link-lifecycle-design.md`. "The design" below means that document, and "section 6.5" means its section 6.5. `docs/ARCHITECTURE.md` is the authority on the rules every task is held to.

**Starting point:** commit `2c75f03` on `main`; branch `claude/project-thread-gufak0`. Tasks 1 to 16 are pull request 1. Tasks 17 to 26 are pull request 2, on the same branch name restarted from `main` once pull request 1 has merged. Nothing below is executed until Joel approves this plan.

## Global Constraints

Every task keeps these, whether or not it repeats them.

- **Flutter `3.47.2`.** Every command below assumes it is first on `PATH`. Commands run from `bluey/` unless a task names another package.
- **Test first.** No production code is written without a failing test that drove it. A moved file is driven by its moved test, a document by the command its task names.
- **Test style.** A `group` names the scenario and each test is laid out with `// arrange`, `// act`, `// assert`; the test code in this plan shows the values and assertions and leaves those comments to the implementer. In-memory doubles, never mocks: `FakeBlueyPlatform` at the platform seam, `InMemoryLinks` and its siblings at Connection's ports. Timers are driven with `fakeAsync` and `elapse`, events with `pumpEventQueue()`, and a broadcast subscription's cancel is never awaited (`docs/testing-conventions.md`). `bluey_android`'s moved M3 test keeps the mocktail mock it was written with. Two helpers the tests below use live in test/fixtures/either\_results.dart, created by the first task that needs them: rightOf(answer) answers an Either's value and fails the test on a Left, and resultOf(future) answers the value of a future that has completed inside fakeAsync and fails the test if it has not.
- **Tests mirror their source.** A test for `lib/src/features/connection/domain/link.dart` is `test/features/connection/domain/link_test.dart`. Doubles and contract suites live under `test/fixtures/`, mirroring the port's path.
- **New code is born placed and clean.** Every new file is under `lib/src/api/`, `lib/src/features/` or `lib/src/shared/{domain,application,infrastructure}/`, passes every architecture rule with no list entry, and is at most 300 lines. No list in any `known_violations.dart` and no roster gains an entry or a larger number.
- **Lists shrink in the commit that earns it.** A moved or deleted file's entries leave in the same commit. A shrunken oversized file's entry is lowered to its new count in the same commit. `lib/src/bluey.dart` never exceeds its entry on the pull request's base: 1,002 lines in pull request 1, and whatever pull request 1 lowered it to in pull request 2.
- **Failures are values below `api/`.** Placed code under `features/` and `shared/` answers `Either<ConnectionFailure, T>` and raises only `StateError`, `ArgumentError` or `UnimplementedError`, and only for a programming error. A success with no value is `Either<ConnectionFailure, void>`, built as `const Right(null)`. Only `api/` throws a `BlueyException`.
- **Layer imports** (`docs/ARCHITECTURE.md` section 3): domain names `dart:core`, `dart:typed_data`, `dart:collection`, `dart:math`, `package:meta` and `shared/domain`; application adds `dart:async`, `package:clock`, its ports and `shared/application`; infrastructure adds `package:bluey_platform_interface` and `package:flutter/services.dart`. Nothing under `features/` or `shared/` names `api/` or an unplaced file. Nothing under `api/` names infrastructure: `lib/src/bluey.dart`, which is unplaced and the composition root until `Bluey` moves, builds every adapter and hands the edge its ports.
- **Connection's language** (section 6.1): link, link id, link lifecycle, link end, radio outage, live links, borrower, session. Connection's code never says probe, peer or server, and never names `BluetoothState`, Platform's `Capabilities`, or anything of GATT Client.
- **No public API beyond the design's section 7.** The API dump changes only for `BlueyEvent` (no longer sealed) in pull request 1, and for `Mtu` and `PlatformKind` in pull request 2. Every dump change is made with `--write` and named in the commit message.
- **Log lines and events keep today's wording** unless a ruling below says otherwise: contexts `bluey` and `bluey.connection`, the messages `connect started`, `connect succeeded`, `connect failed`, `state transition`, `disconnect entered`, `disconnect resolved`, and their `data` keys.
- **Comments say why, never how.** Each public class and function carries a doc comment that says why a reader would use it and what non-obvious consequence to expect.
- **Known defects.** A defect's test moves into the mirrored tree, is seen failing, is fixed, and has its name struck from the roster, all in one commit.
- **Git.** One commit per task, Conventional Commits as in the repository's history (`feat(connection): ...`, `refactor(shared): ...`, `fix(android): ...`, `docs: ...`).
- **Gates before every commit:** the task's own tests, then `flutter analyze`, `flutter test test/architecture` and `dart run test/architecture/list_growth.dart origin/main test/architecture/known_violations.dart test/known_defects/roster.dart`. Tasks 16 and 26 run every gate CI runs.
- **A red gate stops the slice.** No test is skipped, tagged away or made non-blocking. A design question that comes up during the build goes to Joel before the slice goes on.

## Review Focus

Five conditions the design implies and a careless build would miss, most likely first. Each has its test in the task named.

1. **A platform event that arrives after the link ended, or arrives twice.** A second `disconnected`, a late `connected`, a radio outage after a drop. The link stays in the end it reached, one `DisconnectedEvent` is published, and every release runs once. (Task 3, `Link`: "an ended link ignores every input"; Task 9, `LinkSession`: "a second end report publishes nothing and releases nothing".)
2. **Two `disconnect()` calls at once, or a `disconnect()` while a drop is tearing the link down.** The platform is asked to close at most once, and every caller completes after the releases have run. (Task 9: "a second disconnect joins the close in flight", "disconnect during a drop's teardown completes after the releases".)
3. **A borrower gives a link back just as the app connects to that device, or `connectAsPeer` finds that a device the app already holds is not a peer.** The app's link survives, and its `Connection` stays usable. (Task 4, `LiveLinks`: "a give-back after the app took hold leaves the link"; Task 10, `BorrowLink`; Tasks 14 and 15 through the public API.)
4. **A caller waits on another caller's attempt, and that attempt fails or the waiter's own time runs out.** The waiter makes its own attempt after a failure, and on its own timeout fails with a connect timeout while the attempt in flight goes on untouched. (Task 10, `LinkRegistry`: "a waiter makes its own attempt when the attempt it waited on fails", "a waiter's timeout does not cancel the attempt in flight".)
5. **A release that throws, or a platform reports stream that errors.** The remaining releases still run and `disconnect()` still completes; the stream error is logged and read as a drop, never delivered to the app as an error. (Task 9: "a failing release does not stop the others"; Task 8, `PlatformLinks`: "a reports stream the platform fails ends as a drop".)

## Rulings

The design left shapes, signatures and commit order to the builder. These are the choices this plan makes, each checked against the source at `2c75f03`. Rulings 1 to 6 and 19 to 21 differ from a sentence in the design or change something an app can observe, and Joel should read those.

| # | Ruling | Why | What the design said |
| --- | --- | --- | --- |
| 1 | **One assertion pins the `unknown` disconnect reason, not five.** `test/connection/bluey_connection_state_gating_test.dart:214` changes to `requested` | A search of `bluey/test` at `2c75f03` finds that one | Call 4: "Five assertions in two test files pin `unknown` and change" |
| 2 | **A borrow at the edge is a small class, `BorrowedConnection`, with a `BorrowConnection` function type, in `api/connection/borrowed_connection.dart`** | The function Peer is handed needs a declared type that names only the public `Connection`. Neither name is exported from `lib/bluey.dart` | Section 6.9 describes the function; section 6.2 lists no file for it |
| 3 | **`connectAsPeer` gives the link back on every outcome but "it is a peer"**, a failure while checking included | Today a failure before the check leaves the new link open with no owner | Section 6.5 names the peer and not-a-peer outcomes only |
| 4 | **Below the edge, bond and PHY change streams carry no errors.** A platform stream error is logged and dropped, where today it reaches `bondStateChanges` and `phyChanges` raw (pull request 2) | Section 6.7's convention, applied. A raw platform error on a public stream was never a documented behaviour, and no test pins it | Section 6.12: "changes nothing an app or a test can observe" beyond its list |
| 5 | **A failed link read logs the failure's type as its `errorCode`** (`OperationTimedOut`), where today it logs the exception's type (`GattTimeoutException`), on `requestMtu`, `getMaximumWriteLength` and `readRssi` (pull request 2) | The unit that logs is below the edge and never sees the exception. The message, context and other data keys are unchanged. The same holds in pull request 1 for the registry's connect failed line, whose exception and errorCode now name the failure (ConnectFailed) | Silent |
| 6 | **`DisconnectedEvent.reason` reads `requested`, `linkLoss` or `radioOutage`** | The event was declared and never emitted, so its texts are new. The first two match `DisconnectReason`'s names | Section 6.4 says the event is published; it gives no text |
| 7 | `Link`'s inputs and ends live beside it in `link_input.dart` and `link_end.dart` | Three ideas, three files, each short. `link.dart` holds the state machine alone | Section 6.2 draws one file |
| 8 | `BlueyEvent` becomes `abstract class BlueyEvent`, with no per-context family type between it and the events | A family type would be new public API, which section 7 does not list | "The base of every context's events" |
| 9 | `mapLeft` is not added. `flatMapAsync` is added in Task 21, where its first caller is | No unit in this slice calls `mapLeft` | "Added when the first unit needs them" |
| 10 | Each platform package gets a `DeviceStreams` class that owns both per-device controller maps | Both connection managers sit exactly on their size ceilings (428 and 431 lines), so the fix cannot be added inside them, and "who owns a device's streams" is one responsibility | Section 6.10 states the promises, not the shape |
| 11 | The platform log-level mapping moves from `bluey.dart` into `BlueyLogger` | Mapping to the platform interface is infrastructure, and it helps `bluey.dart` end shorter | Silent |
| 12 | `Connections` is handed a `present` function by the composition root | The edge may not name infrastructure, and what a `Connection` is assembled from changes in pull request 2 | "Keeps one public object per session" |
| 13 | A platform adapter-state stream that errors is read as `RadioOutage.unknown` | Today's behaviour (I333), kept | Silent |
| 14 | A close the platform fails on a link that ended anyway answers success | The caller asked for the link to be gone, and it is | Section 6.3 covers a failed close on a live link only |
| 15 | A probe reads the server id with `connection.services(cache: true)` and the characteristic's `read()` | The public path, so a link the app holds is read exactly as the app would read it | "Reads the server id through the `Connection` it borrows" |
| 16 | The edge translator is handed the platform's name; `FeatureUnsupported` and `MtuAboveMaximum` do not carry it | The name is a fact about the platform, which the edge already reads from `Capabilities`. Connection's domain stays free of it | Silent |
| 17 | A test fixture, `ConnectionRig`, assembles the adapter, registry, `Connections` and borrow function over any `BlueyPlatform` | Two test files build `BlueyConnection` directly, `PeerDiscovery` is built 14 times and `createBlueyPeer` 5 times; they need one way to get the real wiring | "Which existing tests move where" is the builder's |
| 18 | The public interfaces move to `api/connection/` in their own task (12), before the switch-over (14) | A pure move is reviewable on its own, and it makes Task 14's diff the behaviour change alone | Commit order is the builder's |
| 19 | **A disconnect() while the radio is already closing the link still asks the platform to close** | There is no close in flight to join in that case: the radio began closing on its own, and the caller must not wait on a report that may never come | Section 6.3's table: in disconnecting, a disconnect request leaves the link unchanged and "the caller joins the close in flight" |
| 20 | **A first read of a link's bond state, PHY or parameters that fails is logged and the default stays, and one that answers after a newer report is ignored** (pull request 2) | Today the failure is an unhandled asynchronous error, and a late first read overwrites a newer report. Both are defects of the code being moved, and a session's tests cannot pin them | Section 6.12: "changes nothing an app or a test can observe" beyond its list |
| 21 | **Pull request 2 builds Connection's units in one edge class, ConnectionAssembly, and its adapters in one infrastructure function, platformConnectionPorts. bluey.dart builds those two and nothing else of Connection** | A size entry can only fall, so five more adapters and four sessions per link cannot be wired inside bluey.dart. It stays the only file at the edge that names infrastructure, and the test rig stops repeating the wiring | Section 6.7: the composition root "builds the adapters, the registry and the units by constructor" |

## File structure

Paths are relative to `bluey/` unless they name another package. Each file has one responsibility, stated once here; the number is the task that creates or moves it. A test file mirrors each source file and is not listed.

**Pull request 1**

```
lib/src/shared/
├── domain/
│   ├── device_address.dart            2  moved from discovery/; a device's address
│   └── bluey_event.dart               2  the base of every event, split out of events.dart
├── application/
│   ├── log.dart                       2  Log: the port every context logs through
│   ├── log_level.dart, log_event.dart 2  moved from log/; what Log speaks
│   └── event_publisher.dart           2  EventPublisher: the port events are published through
└── infrastructure/
    ├── bluey_logger.dart              2  moved from log/; implements Log, bridges native logs
    └── bluey_event_bus.dart           2  moved from event_bus.dart; implements EventPublisher

lib/src/features/connection/
├── domain/
│   ├── connection_state.dart          3  moved from connection/
│   ├── link_id.dart                   3  LinkId
│   ├── link_end.dart                  3  LinkEnd, RadioOutage: why a link ended
│   ├── link_input.dart                3  LinkInput, LinkReport: what can happen to a link
│   ├── link.dart                      3  Link, LinkStep, LinkDuty: the lifecycle state machine
│   ├── live_links.dart                4  LiveLinks: who may open, reuse and close a device's link
│   ├── connection_failure.dart        5  the sealed ConnectionFailure family
│   └── connection_event.dart          5  ConnectingEvent, ConnectedEvent, DisconnectedEvent, out of events.dart
├── application/
│   ├── ports/links.dart               6  Links
│   ├── link_session.dart              9  LinkSession: runs one Link, releases on its end
│   ├── link_registry.dart            10  LinkRegistry: the live sessions, LiveLinks' answers carried out
│   ├── connect_device.dart           10  ConnectDevice: the app's connect
│   └── borrow_link.dart              10  BorrowLink, BorrowedLink: a borrower's use of a link
└── infrastructure/adapters/
    ├── platform_failures.dart         8  everything BlueyPlatform throws, as a ConnectionFailure
    └── platform_links.dart            8  PlatformLinks: Links over BlueyPlatform

lib/src/api/
├── failure_translation.dart          11  ConnectionFailure and LinkEnd to BlueyException
└── connection/
    ├── connection.dart               12  moved from connection/; the public interface
    ├── android_connection_extensions.dart, ios_connection_extensions.dart   12  moved
    ├── bluey_connection.dart         14  BlueyConnection: one session as the public Connection
    ├── connections.dart              12  Connections: one public object per session
    └── borrowed_connection.dart      12  BorrowedConnection, BorrowConnection, borrowingThrough

lib/src/connection/bluey_connection.dart  14  keeps the GATT client, renamed LinkGattClient
lib/src/bluey.dart                    14, 15  wires the adapter, registry, units and Connections
lib/src/peer/peer_discovery.dart, bluey_peer.dart   13, 14  borrow instead of connecting

test/fixtures/
├── features/connection/application/ports/in_memory_links.dart, links_contract.dart   6
└── connection_rig.dart               14  the real wiring over any BlueyPlatform, for tests

bluey_android/lib/src/device_streams.dart, bluey_ios/lib/src/device_streams.dart   7
```

**Pull request 2**

```
lib/src/features/connection/
├── domain/
│   ├── value_objects/                18  bond_state, phy, connection_parameters, connection_interval,
│   │                                     peripheral_latency, supervision_timeout, mtu, write_payload_limit
│   └── link_features.dart            20  LinkFeatures: what links can do on this platform
├── application/
│   ├── ports/                        17, 21-24  connection_ports, mtu_negotiation, signal_strength, bonding, phy_control, parameter_control
│   ├── mtu_session.dart, read_write_payload_limit.dart, read_rssi.dart, link_feature_check.dart, link_operation_log.dart   21
│   ├── bonding_session.dart          22
│   ├── phy_session.dart              23
│   └── parameter_session.dart        24
└── infrastructure/adapters/          17, 20-24  platform_connection_ports, platform_link_features, platform_mtu_negotiation,
                                          platform_signal_strength, platform_bonding, platform_phy_control,
                                          platform_parameter_control (with the parameter mapping)

lib/src/features/platform/
├── domain/capabilities.dart          19  Bluey's own Capabilities and PlatformKind
└── infrastructure/adapters/platform_capabilities.dart   19

lib/src/api/connection/
├── connection_assembly.dart          17  builds Connection's units over its ports and presents each link
└── android_connection.dart, ios_connection.dart   25  the extension implementations

test/fixtures/features/connection/application/ports/   17, 21-24  an in-memory double and a contract per port, and in_memory_connection_ports
```

**Leaves the repository:** `lib/src/discovery/device_address.dart`, `lib/src/event_bus.dart`, `lib/src/log/` (2); `lib/src/connection/connection_state.dart` (3); `lib/src/connection/connection.dart` and the two extension files (12); `lib/src/connection/value_objects/` except `attribute_handle.dart` (18); `lib/src/connection/connection_parameters_mapper.dart` (25). The old `connection/` folder ends the slice holding `bluey_connection.dart`, `lifecycle_client.dart`, `peer_silence_monitor.dart` and `value_objects/attribute_handle.dart`.

## Pull request 1: the lifecycle

### Task 1: Commit the design and this plan, and take the baseline

**Files:**

- Create: `docs/superpowers/specs/2026-11-18-link-lifecycle-design.md`, `docs/superpowers/plans/2026-11-18-link-lifecycle.md` (repository root)

**Interfaces:**

- Produces: the branch `claude/project-thread-gufak0` from `origin/main`, a working Flutter 3.47.2, and the baseline numbers later tasks compare with.

* [ ] **Step 1: Toolchain.** Install Flutter 3.47.2 (the version the root `pubspec.yaml` pins), put it first on `PATH`, and run `flutter pub get` at the repository root. Expected: `flutter --version` prints `3.47.2` and the tree stays clean.
* [ ] **Step 2: Branch.** `git fetch origin main && git checkout -B claude/project-thread-gufak0 origin/main`.
* [ ] **Step 3: Add the two documents.** The design is the approved Claude Doc's markdown, with its status line changed to `Status: approved by Joel on 2026-11-18` and its link to the foundation design pointed at `2026-11-17-architecture-foundation-design.md`. The plan is this document.
* [ ] **Step 4: Baseline.** Run and record:

```bash
flutter analyze                                             # no issues
(cd bluey && flutter test)                                  # all pass
(cd bluey_android && flutter test) && (cd bluey_ios && flutter test) && (cd bluey_platform_interface && flutter test)
(cd bluey && flutter test test/known_defects --run-skipped --tags known-defect)          # 9 fail, as the roster says
(cd bluey_android && flutter test test/known_defects --run-skipped --tags known-defect)  # 2 fail
(cd bluey && flutter test --coverage && dart run bluey_guards:coverage_gate coverage/lcov.info 90 lib \
  && dart run bluey_guards:coverage_gate coverage/lcov.info 95 lib 'lib/src/features/*/domain' lib/src/shared/domain)
```

- [ ] **Step 5: Commit.** `git commit -m "docs: add the link lifecycle design and plan"`

### Task 2: Move the kernel pieces Connection names

Section 6.11. Nothing an app can observe changes except that `BlueyEvent` is no longer sealed.

**Files:**

- Move: `lib/src/discovery/device_address.dart` to `lib/src/shared/domain/device_address.dart`; `lib/src/log/log_level.dart` and `log_event.dart` to `lib/src/shared/application/`; `lib/src/log/bluey_logger.dart` to `lib/src/shared/infrastructure/bluey_logger.dart`
- Create: `lib/src/shared/domain/bluey_event.dart`, `lib/src/shared/application/log.dart`, `lib/src/shared/application/event_publisher.dart`, `lib/src/shared/infrastructure/bluey_event_bus.dart`; `analysis_options.yaml` in `lib/src/shared/application/` and `lib/src/shared/infrastructure/`, each a copy of `lib/src/shared/domain/analysis_options.yaml`
- Delete: `lib/src/event_bus.dart`
- Modify: `lib/src/events.dart` (loses `BlueyEvent`), `lib/bluey.dart` (export paths, plus `src/shared/domain/bluey_event.dart`), `lib/src/bluey.dart` (loses `_mapLogLevelToPlatform`), every importer of the moved files, `test/architecture/known_violations.dart`, `api/bluey.api`
- Test: `test/shared/domain/device_address_test.dart` (moved from `test/discovery/`), `test/shared/domain/bluey_event_test.dart`, `test/shared/application/` and `test/shared/infrastructure/` (the `test/log/` files, moved to match their source; the integration test of Bluey's own log lines stays), `test/fixtures/shared/application/recording_log.dart`, `recording_event_publisher.dart`

**Interfaces:**

- Produces:
  - `class DeviceAddress` unchanged, at its new path.
  - `@immutable abstract class BlueyEvent { BlueyEvent({DateTime? timestamp, String? source}); final DateTime timestamp; final String? source; }` with today's `toString` and its private time formatter.
  - `abstract interface class Log { void log(BlueyLogLevel level, String context, String message, {Map<String, Object?> data = const {}, String? errorCode}); }`
  - `abstract interface class EventPublisher { void emit(BlueyEvent event); }`
  - `class BlueyLogger implements Log`, unchanged apart from `static PlatformLogLevel platformLevelOf(BlueyLogLevel level)`; `class BlueyEventBus implements EventPublisher`, unchanged.
  - Test doubles: `RecordingLog implements Log` with `List<BlueyLogEvent> records`, and `RecordingEventPublisher implements EventPublisher` with `List<BlueyEvent> events`.

* [ ] **Step 1: Move the tests and write the new ones.** Move each test beside its source's new path and point its imports there, so the suite stops compiling. Add:

```dart
// test/shared/domain/bluey_event_test.dart
test('an event outside events.dart can extend BlueyEvent', () {
  final event = _ProbeEvent(timestamp: DateTime.utc(2026, 11, 18, 9, 5, 7, 42));
  expect(event, isA<BlueyEvent>());
  expect(event.toString(), '[_ProbeEvent] 09:05:07.042');
});

// test/shared/infrastructure/bluey_logger_test.dart (added to the moved file)
test('the logger is the Log port', () => expect(BlueyLogger(), isA<Log>()));
test('platformLevelOf maps every level by name', () {
  for (final level in BlueyLogLevel.values) {
    expect(BlueyLogger.platformLevelOf(level).name, level.name);
  }
});
```

- [ ] **Step 2: Run them to see them fail.** `flutter test test/shared` fails to compile: the new paths do not exist.
- [ ] **Step 3: Move and split the sources.** `git mv` each file, split `EventPublisher` and `BlueyEventBus` into their two files, split `BlueyEvent` out of `events.dart` and change `sealed` to `abstract`, move the level mapping into `BlueyLogger` and call it from `Bluey.setLogLevel`, and update every import and the export lines of `lib/bluey.dart`. Unplaced files keep the concrete `BlueyLogger` type; only the import path changes.
- [ ] **Step 4: Bring the lists and the dump up to date.** Delete the five `unplaced` entries (`discovery/device_address.dart`, `event_bus.dart`, the three `log/` files), every `boundaries` entry that ends in `discovery/device_address.dart` (six), and the `frameworkPlacement` entry for `log/bluey_logger.dart`. Lower `oversized` for `lib/src/events.dart` and `lib/src/bluey.dart` to their new counts. Run `dart run bluey_guards:public_api lib/bluey.dart api/bluey.api --write`; the diff is the one line `sealed class BlueyEvent` to `abstract class BlueyEvent`.
- [ ] **Step 5: Run the gates.** `flutter test`, `flutter analyze`, `flutter test test/architecture`, the list-growth command. Expected: all pass, no list grew.
- [ ] **Step 6: Commit.** `refactor(shared): move DeviceAddress, the event base, logging and the event bus into the kernel`

### Task 3: `Link`, the lifecycle state machine

Section 6.3. Pure and synchronous: no stream, timer or clock.

**Files:**

- Move: `lib/src/connection/connection_state.dart` to `lib/src/features/connection/domain/connection_state.dart` (and `test/connection_state_test.dart` to `test/features/connection/domain/`)
- Create: `lib/src/features/analysis_options.yaml` (the same copy), and under `lib/src/features/connection/domain/`: `link_id.dart`, `link_end.dart`, `link_input.dart`, `link.dart`
- Modify: `lib/src/connection/connection.dart` (import and export path), `lib/bluey.dart` if it names the old path, `known_violations.dart` (the `unplaced` entry for `connection_state.dart` leaves)
- Test: `test/features/connection/domain/link_test.dart`, `link_id_test.dart`, `link_end_test.dart`

**Interfaces:**

- Consumes: `DeviceAddress` (Task 2).
- Produces:

```dart
final class LinkId { const LinkId(this.value); final String value; }            // equal by value

enum RadioOutage { off, unauthorized, unsupported, unknown }
sealed class LinkEnd { const LinkEnd(); }                                      // each equal by value
final class EndedOnRequest extends LinkEnd { const EndedOnRequest(); }
final class EndedByDrop extends LinkEnd { const EndedByDrop(); }
final class EndedByRadioOutage extends LinkEnd { const EndedByRadioOutage(this.outage); final RadioOutage outage; }

enum LinkReport { connecting, connected, disconnecting, disconnected }
sealed class LinkInput { const LinkInput(); }
final class ServicesDiscovered extends LinkInput { const ServicesDiscovered(); }
final class RadioReported extends LinkInput { const RadioReported(this.report); final LinkReport report; }
final class ReportsEnded extends LinkInput { const ReportsEnded(); }
final class DisconnectRequested extends LinkInput { const DisconnectRequested(); }
final class CloseConfirmed extends LinkInput { const CloseConfirmed(); }
final class CloseFailed extends LinkInput { const CloseFailed(); }
final class RadioOutageBegan extends LinkInput { const RadioOutageBegan(this.outage); final RadioOutage outage; }

enum LinkDuty { closeTheLink, releaseAndAnnounce }
final class LinkStep { const LinkStep(this.link, [this.duty]); final Link link; final LinkDuty? duty; }

final class Link {
  const Link.opened({required LinkId id, required DeviceAddress device});      // state: linked
  LinkId get id;  DeviceAddress get device;
  ConnectionState get state;
  LinkEnd? get end;          // non-null exactly when state is disconnected or invalidated
  LinkEnd? get endInSight;   // the end reached, or the one a closing link is heading for; null while up
  bool get isUp;             // linked or ready
  bool get isClosing;        // disconnecting
  bool get hasEnded;
  LinkStep on(LinkInput input);
}
```

`Link`'s only public constructor is `Link.opened`, so an ended link without a reason cannot be built. A closing link remembers the state to return to and whether a disconnect was requested.

- [ ] **Step 1: Write the failing table test.** One row per line of section 6.3's table, plus the cases it leaves to the builder:

```dart
const id = LinkId('L1');
const device = DeviceAddress('AA:BB:CC:DD:EE:01');
Link after(List<LinkInput> inputs) =>
    inputs.fold(const Link.opened(id: id, device: device), (link, input) => link.on(input).link);

const discovered = ServicesDiscovered();
const request = DisconnectRequested();
const radioClosing = RadioReported(LinkReport.disconnecting);
const radioGone = RadioReported(LinkReport.disconnected);

// (name, inputs so far, input, state after, duty, end after)
final rows = <(String, List<LinkInput>, LinkInput, ConnectionState, LinkDuty?, LinkEnd?)>[
  ('discovery makes a linked link ready', [], discovered, ConnectionState.ready, null, null),
  ('a repeated connected report never takes ready back to linked',
      [discovered], const RadioReported(LinkReport.connected), ConnectionState.ready, null, null),
  ('a connecting report changes nothing', [], const RadioReported(LinkReport.connecting), ConnectionState.linked, null, null),
  ('the radio closing the link', [discovered], radioClosing, ConnectionState.disconnecting, null, null),
  ('a request asks for the close', [discovered], request, ConnectionState.disconnecting, LinkDuty.closeTheLink, null),
  ('a second request joins the close in flight', [request], request, ConnectionState.disconnecting, null, null),
  ('a request while the radio is closing asks for the close', [radioClosing], request,
      ConnectionState.disconnecting, LinkDuty.closeTheLink, null),
  ('a confirmed close ends on request', [request], const CloseConfirmed(),
      ConnectionState.disconnected, LinkDuty.releaseAndAnnounce, const EndedOnRequest()),
  ('a disconnected report ends a requested close on request', [request], radioGone,
      ConnectionState.disconnected, LinkDuty.releaseAndAnnounce, const EndedOnRequest()),
  ('reports ending ends a requested close on request', [request], const ReportsEnded(),
      ConnectionState.disconnected, LinkDuty.releaseAndAnnounce, const EndedOnRequest()),
  ('the radio finishing its own close is a drop', [radioClosing], radioGone,
      ConnectionState.disconnected, LinkDuty.releaseAndAnnounce, const EndedByDrop()),
  ('a failed close returns to ready', [discovered, request], const CloseFailed(), ConnectionState.ready, null, null),
  ('a failed close returns to linked', [request], const CloseFailed(), ConnectionState.linked, null, null),
  ('a drop ends a linked link', [], radioGone,
      ConnectionState.disconnected, LinkDuty.releaseAndAnnounce, const EndedByDrop()),
  ('reports ending is a drop', [discovered], const ReportsEnded(),
      ConnectionState.disconnected, LinkDuty.releaseAndAnnounce, const EndedByDrop()),
  ('an outage invalidates an up link', [discovered], const RadioOutageBegan(RadioOutage.off),
      ConnectionState.invalidated, LinkDuty.releaseAndAnnounce, const EndedByRadioOutage(RadioOutage.off)),
  ('an outage invalidates a closing link', [request], const RadioOutageBegan(RadioOutage.unknown),
      ConnectionState.invalidated, LinkDuty.releaseAndAnnounce, const EndedByRadioOutage(RadioOutage.unknown)),
  ('a stray close answer changes nothing', [discovered], const CloseConfirmed(), ConnectionState.ready, null, null),
  ('discovery while closing changes nothing', [request], discovered, ConnectionState.disconnecting, null, null),
];

for (final (name, before, input, state, duty, end) in rows) {
  test(name, () {
    final step = after(before).on(input);
    expect(step.link.state, state);
    expect(step.duty, duty);
    expect(step.link.end, end);
  });
}

test('an ended link ignores every input', () {   // L6, and Review Focus 1
  const every = <LinkInput>[discovered, request, radioClosing, radioGone, ReportsEnded(), CloseConfirmed(),
    CloseFailed(), RadioReported(LinkReport.connected), RadioOutageBegan(RadioOutage.off)];
  for (final ended in [after([radioGone]), after([const RadioOutageBegan(RadioOutage.off)])]) {
    for (final input in every) {
      final step = ended.on(input);
      expect(step.link.state, ended.state);
      expect(step.link.end, ended.end);
      expect(step.duty, isNull);
    }
  }
});

test('endInSight names where a closing link is heading', () {
  expect(after([]).endInSight, isNull);
  expect(after([request]).endInSight, const EndedOnRequest());
  expect(after([radioClosing]).endInSight, const EndedByDrop());
  expect(after([radioClosing, request]).endInSight, const EndedOnRequest());
  expect(after([radioGone]).endInSight, const EndedByDrop());
});

test('a link keeps its id and device through every step', () {
  final link = after([discovered, request, const CloseConfirmed()]);
  expect((link.id, link.device), (id, device));
});
```

Plus `isUp`, `isClosing` and `hasEnded` for one link in each of the five states, and value equality for `LinkId` and each `LinkEnd`.

- [ ] **Step 2: Run it to see it fail.** `flutter test test/features/connection/domain` fails to compile: `Link` is not defined.
- [ ] **Step 3: Implement** the four files to the signatures above. `Link.on` is one exhaustive `switch` over the input per kind of state; no `default` branch.
- [ ] **Step 4: Run the gates.** The domain tests pass; `flutter test test/architecture` passes with no new entry.
- [ ] **Step 5: Commit.** `feat(connection): add Link, the link lifecycle state machine`

### Task 4: `LiveLinks`

Section 6.5's two tables. Pure; keyed by `DeviceAddress`; keeps no copy of a link's state.

**Files:**

- Create: `lib/src/features/connection/domain/live_links.dart`
- Test: `test/features/connection/domain/live_links_test.dart`

**Interfaces:**

- Consumes: `Link`, `DeviceAddress`.
- Produces:

```dart
enum LinkUser { app, borrower }
enum Admission { open, wait, reuse }
enum AfterGiveBack { closeTheLink, leaveIt }

final class LiveLinks {
  const LiveLinks.empty();
  /// [link] is the device's link when it has one, and null while none exists or an open is in flight.
  (LiveLinks, Admission) admit(DeviceAddress device, LinkUser user, {required Link? link});
  LiveLinks opened(DeviceAddress device);                    // the attempt in flight came up
  LiveLinks forget(DeviceAddress device);                    // an open failed, or the link ended
  (LiveLinks, AfterGiveBack) giveBack(DeviceAddress device); // one borrower fewer
  LiveLinks keep(DeviceAddress device);                      // one borrower fewer; the app now holds it
  bool appHolds(DeviceAddress device);
  int borrowersOf(DeviceAddress device);
  bool isOpening(DeviceAddress device);
}
```

`admit` answers `open` for a device with no entry and records the user on a new entry that is opening; `wait` while the entry is opening, or when the link it is handed is closing or has ended; `reuse` when the link is up, adding the user. Asking about a device whose link came up without handing that link in is a `StateError`. `giveBack` and `keep` for a device with no entry change nothing and answer `leaveIt`.

- [ ] **Step 1: Write the failing tests**, one per cell of the two tables:

```dart
const device = DeviceAddress('AA:BB:CC:DD:EE:01');
const other = DeviceAddress('AA:BB:CC:DD:EE:02');
const up = Link.opened(id: LinkId('L1'), device: device);
final closing = up.on(const DisconnectRequested()).link;
final ended = up.on(const RadioReported(LinkReport.disconnected)).link;
LiveLinks heldBy(LinkUser user) => const LiveLinks.empty().admit(device, user, link: null).$1.opened(device);

test('the app opens a link to a device that has none', () {
  final (links, admission) = const LiveLinks.empty().admit(device, LinkUser.app, link: null);
  expect(admission, Admission.open);
  expect((links.isOpening(device), links.appHolds(device), links.borrowersOf(device)), (true, true, 0));
});
test('a borrower opens a link with one borrower', () { /* (true, false, 1) */ });
test('a second caller waits while an open is in flight', () {
  final (links, _) = const LiveLinks.empty().admit(device, LinkUser.borrower, link: null);
  final (after, admission) = links.admit(device, LinkUser.app, link: null);
  expect(admission, Admission.wait);
  expect(after.appHolds(device), isFalse);            // a waiter is not recorded
});
test('a caller waits while the link is closing', () =>
    expect(heldBy(LinkUser.app).admit(device, LinkUser.borrower, link: closing).$2, Admission.wait));
test('a caller waits on a link that ended and is not yet forgotten', () =>
    expect(heldBy(LinkUser.app).admit(device, LinkUser.app, link: ended).$2, Admission.wait));
test('the app reuses a link a borrower has, and now holds it', () {
  final (links, admission) = heldBy(LinkUser.borrower).admit(device, LinkUser.app, link: up);
  expect(admission, Admission.reuse);
  expect((links.appHolds(device), links.borrowersOf(device)), (true, 1));
});
test('a borrower reuses the app\'s link as one more borrower', () { /* reuse, (true, 1) */ });
test('a give-back by the only user closes the link', () =>
    expect(heldBy(LinkUser.borrower).giveBack(device).$2, AfterGiveBack.closeTheLink));
test('a give-back leaves a link another borrower still uses', () { /* two borrowers: leaveIt, then closeTheLink */ });
test('a give-back after the app took hold leaves the link', () {   // Review Focus 3
  final (links, _) = heldBy(LinkUser.borrower).admit(device, LinkUser.app, link: up);
  final (after, answer) = links.giveBack(device);
  expect(answer, AfterGiveBack.leaveIt);
  expect((after.appHolds(device), after.borrowersOf(device)), (true, 0));
});
test('keep hands the link to the app', () {
  final links = heldBy(LinkUser.borrower).keep(device);
  expect((links.appHolds(device), links.borrowersOf(device)), (true, 0));
});
test('forget removes the device, so the next caller opens', () =>
    expect(heldBy(LinkUser.app).forget(device).admit(device, LinkUser.app, link: null).$2, Admission.open));
test('devices do not affect each other', () =>
    expect(heldBy(LinkUser.app).admit(other, LinkUser.app, link: null).$2, Admission.open));
test('a device whose link came up must be asked about with its link', () =>
    expect(() => heldBy(LinkUser.app).admit(device, LinkUser.app, link: null), throwsStateError));
test('giving back or keeping an unknown device changes nothing', () {
  expect(const LiveLinks.empty().giveBack(device).$2, AfterGiveBack.leaveIt);
  expect(const LiveLinks.empty().keep(device).appHolds(device), isFalse);
});
```

- [ ] **Step 2: Run to see them fail** (`LiveLinks` is not defined). **Step 3: Implement** `live_links.dart` as an immutable map of private entries (`opening`, `appHolds`, `borrowers`). **Step 4: Run** the domain tests and `flutter test test/architecture`.
- [ ] **Step 5: Commit.** `feat(connection): add LiveLinks, who may open, reuse and close a device's link`

### Task 5: `ConnectionFailure` and Connection's events

**Files:**

- Create: `lib/src/features/connection/domain/connection_failure.dart`, `lib/src/features/connection/domain/connection_event.dart`
- Modify: `lib/src/events.dart` (loses the three events; `oversized` entry lowered), `lib/bluey.dart` (exports `connection_event.dart`)
- Test: `test/features/connection/domain/connection_failure_test.dart`, `connection_event_test.dart`

**Interfaces:**

- Consumes: `Failure` (`shared/domain/failure.dart`), `LinkEnd`, `BlueyEvent`, `DeviceAddress`.
- Produces:

```dart
enum ConnectFailureReason { timeout, deviceNotFound, deviceNotConnectable, pairingFailed, connectionLimitReached, unknown }

sealed class ConnectionFailure implements Failure { const ConnectionFailure(); }   // each equal by value
final class ConnectFailed extends ConnectionFailure { const ConnectFailed(this.reason); final ConnectFailureReason reason; }
final class LinkEnded extends ConnectionFailure { const LinkEnded(this.end); final LinkEnd end; }
final class RadioUnavailable extends ConnectionFailure { const RadioUnavailable(); }
final class PermissionMissing extends ConnectionFailure { const PermissionMissing(this.permission); final String permission; }
final class OperationTimedOut extends ConnectionFailure { const OperationTimedOut(this.operation); final String operation; }
final class OperationRejected extends ConnectionFailure { const OperationRejected(this.operation, this.status); final String operation; final int status; }
final class UnexpectedPlatformFailure extends ConnectionFailure {
  const UnexpectedPlatformFailure(this.detail, {this.code, this.cause});
  final String detail; final String? code; final Object? cause;
}
```

`ConnectingEvent`, `ConnectedEvent` and `DisconnectedEvent` move unchanged: same constructors, fields and `toString`.

- [ ] **Step 1: Write the failing tests:** each failure equals another of the same values and differs from one of other values; each `message` is a non-empty sentence that names its operation, status or reason; a `switch` over `ConnectionFailure` with one case per subtype and no `default` compiles (the test holds the list complete). The three event tests move from wherever `events.dart` is tested and import the new file.
- [ ] **Step 2: Run to see them fail. Step 3: Implement. Step 4: Run** `flutter test`, the architecture tests, and `dart run bluey_guards:public_api lib/bluey.dart api/bluey.api` (expected: no difference).
- [ ] **Step 5: Commit.** `feat(connection): add ConnectionFailure and move the connection events into the domain`

### Task 6: The `Links` port, its double and its contract

Section 6.6.

**Files:**

- Create: `lib/src/features/connection/application/ports/links.dart`
- Create: `test/fixtures/features/connection/application/ports/in_memory_links.dart`, `links_contract.dart`
- Test: `test/features/connection/application/ports/in_memory_links_test.dart`

**Interfaces:**

- Consumes: `Either`, `ConnectionFailure`, `LinkId`, `LinkReport`, `RadioOutage`, `DeviceAddress`.
- Produces:

```dart
abstract interface class Links {
  /// Opens a link. [timeout] bounds the attempt; null leaves the bound to the platform.
  Future<Either<ConnectionFailure, LinkId>> open(DeviceAddress device, {Duration? timeout});
  Future<Either<ConnectionFailure, void>> close(LinkId link);
  /// The radio's reports about one link, for one listener. Reports that arrive before the
  /// listener does are kept. Carries no errors, and ends when the platform has no more to say.
  Stream<LinkReport> reportsOf(LinkId link);
  /// Each time the adapter leaves `on`, for any number of listeners.
  Stream<RadioOutage> get outages;
}

// test/fixtures: the harness both runs of the contract implement
abstract class LinksHarness {
  Links get links;
  void reach(DeviceAddress device);                                   // the device can be connected to
  void failNextOpen(DeviceAddress device, ConnectFailureReason reason);
  void failNextClose(DeviceAddress device);
  void drop(DeviceAddress device);                                    // the peer drops the link
  void outage(RadioOutage outage);
}
void linksContract(String name, LinksHarness Function() create);

// test/fixtures: the double, which is its own harness and adds what application tests need
class InMemoryLinks implements Links, LinksHarness {
  Duration openDelay = Duration.zero;      // how long an open stays in flight
  Duration closeDelay = Duration.zero;
  void report(DeviceAddress device, LinkReport report);
  int opensAsked(DeviceAddress device);
  int closesAsked(DeviceAddress device);
  List<Duration?> get openTimeouts;        // the timeout each open was asked with, in order
}
```

`InMemoryLinks` answers `ConnectFailed(ConnectFailureReason.timeout)` when `openDelay` outlasts the open's timeout, and names a link `link-<n>`, counting from 1.

- [ ] **Step 1: Write the contract and run it against the double.** `linksContract` holds these promises, each a test:

```dart
test('open answers a link id for a reachable device', ...);      // isA<Right<ConnectionFailure, LinkId>>()
test('open answers why an unreachable device could not be linked', () async {
  h.failNextOpen(device, ConnectFailureReason.deviceNotFound);
  expect(await h.links.open(device), const Left<ConnectionFailure, LinkId>(ConnectFailed(ConnectFailureReason.deviceNotFound)));
});
test('a closed link\'s reports end', ...);                          // close answers Right; reportsOf(id) emits done
test('a drop is reported as disconnected, and then the reports end', ...);   // emitsInOrder([LinkReport.disconnected, emitsDone])
test('a report that arrives before the listener is kept', ...);    // open, drop, then listen: the same two events
test('a second open for a linked device answers the same id and leaves the first reports attached', ...);  // M3 at the port
test('a failed close answers a failure and leaves the reports going', ...);  // failNextClose; close is a Left; a later drop still arrives
test('an outage reaches every listener in Connection\'s words', ...);       // two listeners each see RadioOutage.off
```

- [ ] **Step 2: Run it to see it fail** (`InMemoryLinks` is not defined). **Step 3: Implement** the port, the double and its own tests for `openDelay`, `closeDelay`, the counters and the timeout rule. **Step 4: Run** `flutter test test/features/connection` and the architecture tests.
- [ ] **Step 5: Commit.** `feat(connection): add the Links port with its in-memory double and contract`

### Task 7: A device's streams survive a second connect and close on its last event (M3, I369)

Section 6.10. `bluey_android` and `bluey_ios`, Dart only. Commands run in each package.

**Files:**

- Create: `bluey_android/lib/src/device_streams.dart`, `bluey_ios/lib/src/device_streams.dart`
- Modify: `android_connection_manager.dart`, `ios_connection_manager.dart` (both lose their two controller maps), each package's `test/architecture/known_violations.dart` (both `oversized` entries lowered), `bluey_android/test/known_defects/roster.dart` (the M3 name leaves) and `android_adapter_known_defects_test.dart` (the M3 test leaves; M2 stays)
- Test: `test/device_streams_test.dart` in both packages; `bluey_android/test/android_connection_manager_test.dart` (the moved M3 test); `bluey_ios/test/ios_connection_manager_test.dart` (the same test, written for iOS)

**Interfaces:**

- Produces, identically in both packages:

```dart
/// Owns each connected device's state and notification streams, so one place decides when they open and close.
class DeviceStreams {
  void open(String deviceId);                          // creates the pair only when none is live
  Future<void> close(String deviceId);                 // closes and removes the pair; a no-op when there is none
  Stream<PlatformConnectionState> statesOf(String deviceId);        // an error stream when none, as today
  Stream<PlatformNotification> notificationsOf(String deviceId);    // likewise
  void reportState(String deviceId, PlatformConnectionState state); // adds; on `disconnected`, then closes and removes
  void reportNotification(String deviceId, PlatformNotification notification);
}
```

The managers call `open` at the top of `connect`, `close` when `connect` fails and inside `disconnect`, and `reportState` and `reportNotification` from their event handlers.

- [ ] **Step 1: Move the M3 test and write the others.** Move `'M3 (I369): a second connect() to a connected device does not orphan the first connection's state stream'` into `android_connection_manager_test.dart` without its tag, and write the same test over `IosConnectionManager`. In `device_streams_test.dart`:

```dart
test('a second open keeps the first stream attached', () async {
  streams.open('dev');
  final first = streams.statesOf('dev');
  streams.open('dev');
  expectLater(first, emits(PlatformConnectionState.connected));
  streams.reportState('dev', PlatformConnectionState.connected);
});
test('the disconnected report is delivered, and then both streams end', ...);  // emitsInOrder([disconnected, emitsDone]); notifications emitsDone
test('after the last report the device has no streams', ...);                  // statesOf('dev') emits a StateError
test('close ends both streams and is safe to repeat', ...);
test('a report for a device with no streams is dropped', ...);                 // returns normally
```

And in each manager's test: a `connect` the host fails leaves `connectionStateStream(deviceId)` an error stream (the prune on a failed connect).

- [ ] **Step 2: Run to see them fail.** In `bluey_android`, `flutter test test/android_connection_manager_test.dart` fails on the M3 test: the first stream never sees `disconnected`.
- [ ] **Step 3: Implement** `DeviceStreams` and switch both managers to it.
- [ ] **Step 4: Strike the roster name and lower the lists.** Delete the M3 line from `bluey_android`'s roster and lower both managers' `oversized` entries to their new counts. Run each package's `flutter test`, `flutter test test/architecture`, and in `bluey_android` `flutter test test/known_defects --run-skipped --tags known-defect` (expected: the one remaining defect, M2, fails).
- [ ] **Step 5: Commit.** `fix(android,ios): keep a device's streams across a second connect and close them on its last event (M3, I369)`

### Task 8: `PlatformLinks` and the platform-error mapping

**Files:**

- Create: `lib/src/features/connection/infrastructure/adapters/platform_failures.dart`, `platform_links.dart`
- Modify: `test/fakes/fake_platform.dart` (the promises of Task 7, and `FakeOp.disconnect`)
- Test: `test/features/connection/infrastructure/adapters/platform_failures_test.dart`, `platform_links_test.dart`; `test/fakes/` gains tests for the fake's new promises

**Interfaces:**

- Consumes: `Links`, `linksContract`, `LinksHarness`, `Log`, `ConnectionFailure`.
- Produces:

```dart
/// Everything BlueyPlatform can throw at a Connection operation, in Connection's words.
ConnectionFailure connectionFailureFrom(Object error, {required String operation});
/// Runs one platform call and answers what it threw as a failure.
Future<Either<ConnectionFailure, T>> answering<T>(String operation, Future<T> Function() call);

final class PlatformLinks implements Links {
  PlatformLinks(BlueyPlatform platform, {required Log log});
}
```

The mapping, row for row:

| The platform throws | `connectionFailureFrom` answers |
| --- | --- |
| `GattOperationTimeoutException` | `OperationTimedOut(operation)` |
| `GattOperationDisconnectedException` | `LinkEnded(EndedByDrop())` |
| `GattOperationStatusFailedException` | `OperationRejected(operation, status)`, whatever the status |
| `GattOperationUnknownPlatformException` | `UnexpectedPlatformFailure(message ?? 'unknown platform error (<code>)', code: code, cause: error)` |
| `PlatformConnectFailedException` | `ConnectFailed(reason)`, with `notConnectable` read as `deviceNotConnectable` |
| `PlatformPermissionDeniedException` | `PermissionMissing(permission)` |
| `PlatformBluetoothUnavailableException` | `RadioUnavailable()` |
| Flutter's `PlatformException` | `UnexpectedPlatformFailure(message ?? 'platform error (<code>)', code: code, cause: error)` |
| anything else | `UnexpectedPlatformFailure(error.toString(), cause: error)` |

`PlatformLinks.open` calls `platform.connect(device.value, PlatformConnectConfig(timeoutMs: timeout?.inMilliseconds, mtu: null))` and, in the same turn the id arrives, starts carrying that link's `connectionStateStream` into a buffered stream of `LinkReport`, so no report is lost before the session listens. A platform stream error is logged (`warn`, `bluey.connection`, `link reports failed`) and the reports end. `outages` maps every platform state but `on` to its `RadioOutage`, and a platform state-stream error to `RadioOutage.unknown`.

- [ ] **Step 1: Write the failing tests.** One test per row of the mapping table. Then:

```dart
// platform_links_test.dart
linksContract('PlatformLinks over FakeBlueyPlatform', () => _FakePlatformHarness());

test('open passes the caller\'s timeout to the platform', ...);         // 3 s arrives as timeoutMs 3000
test('a reports stream the platform fails ends as a drop', () async {   // Review Focus 5
  final id = (await links.open(device)).fold((_) => fail('open'), (id) => id);
  final reports = links.reportsOf(id);
  fake.simulateConnectionStateError(device.value, StateError('boom'));
  await expectLater(reports, emitsDone);                                 // no error reaches the listener
  expect(log.records.single.message, 'link reports failed');
});
test('a failed adapter-state stream is an unknown outage', ...);        // fake.simulateStateError -> RadioOutage.unknown
test('every adapter state but on is an outage', ...);                   // off, unauthorized, unsupported, unknown; on emits nothing
```

`_FakePlatformHarness` implements `LinksHarness` over `FakeBlueyPlatform`: `reach` simulates a peripheral, `failNextOpen` is `simulateConnectFailure`, `failNextClose` is `enqueueFault(FakeOp.disconnect, ...)`, `drop` is `simulateDisconnection`, `outage` is `setBluetoothState`.

- [ ] **Step 2: Run to see them fail.** The contract fails on "a drop ... then the reports end" and "a second open ... leaves the first reports attached": the fake does not yet keep Task 7's promises.
- [ ] **Step 3: Teach the fake the promises, test first.** `FakeBlueyPlatform.connect` reuses a device's live controllers; `simulateDisconnection` adds `disconnected` and then closes and removes them; a failed `connect` leaves none; `disconnect` honours a fault queued for `FakeOp.disconnect`; `simulateConnectionStateError(deviceId, error)` adds an error to that device's state stream.
- [ ] **Step 4: Implement** the mapping and the adapter.
- [ ] **Step 5: Run** `flutter test` (the whole suite: the fake changed under every test), `flutter analyze`, the architecture tests.
- [ ] **Step 6: Commit.** `feat(connection): add PlatformLinks and Connection's platform-error mapping`

### Task 9: `LinkSession`

Section 6.4. Runs one `Link`; nothing else keeps a copy of its state.

**Files:**

- Create: `lib/src/features/connection/application/link_session.dart`
- Test: `test/features/connection/application/link_session_test.dart`

**Interfaces:**

- Consumes: `Link`, `LinkInput`, `LinkDuty`, `Links`, `EventPublisher`, `Log`, `DisconnectedEvent`, `InMemoryLinks`, `RecordingLog`, `RecordingEventPublisher`.
- Produces:

```dart
final class LinkSession {
  /// Starts listening to the link's reports and to radio outages at once.
  LinkSession({required Link link, required Links links, required EventPublisher events, required Log log});
  Link get link;
  /// Every state the link moves to. Carries no errors, and ends when the link ends.
  Stream<ConnectionState> get states;
  /// Registers something that lives as long as the link. Runs once when the link ends, whatever
  /// ended it; at once if it already has.
  void onEnd(FutureOr<void> Function(LinkEnd end) release);
  void servicesDiscovered();
  /// Runs [operation] if the link is up, and answers [orEnd] instead if the link is closing, has
  /// ended, or ends before the operation answers.
  Future<Either<F, T>> whileUp<F, T>(Future<Either<F, T>> Function() operation,
      {required F Function(LinkEnd end) orEnd});
  Future<Either<ConnectionFailure, void>> disconnect();
}
```

What the session does when the `Link` answers `releaseAndAnnounce`, in this order: emits the end state on `states` and closes it; answers every `whileUp` in flight with `orEnd(end)`; publishes `DisconnectedEvent(deviceAddress: link.device, reason: ...)` with `requested`, `linkLoss` or `radioOutage`; stops listening to the port; runs the releases one after another in the order they were registered, logging one that fails (`warn`, `bluey.connection`, `release failed`) and going on; and only then completes every `disconnect()` waiting on it.

`disconnect()` on an up link logs `disconnect entered`, feeds `DisconnectRequested`, asks `links.close`, and on success feeds `CloseConfirmed` and logs `disconnect resolved`. On a failed close it answers success if the link ended anyway, and otherwise feeds `CloseFailed` and answers the failure. A call while a close is in flight answers with that close. A call on an ended link answers success without asking the platform, after the releases. Every state change is logged as today: `info`, `bluey.connection`, `state transition`, `{'deviceId': '<address>', 'state': '<ConnectionState>'}`.

- [ ] **Step 1: Write the failing tests.** A helper opens a link on `InMemoryLinks` and builds the session; `released` is a list a registered release appends to.

```dart
group('a drop', () {
  test('emits disconnected, closes the states and runs the releases', () async {   // H3
    final states = <ConnectionState>[];
    var closed = false;  session.states.listen(states.add, onDone: () => closed = true);
    links.drop(device);
    await pumpEventQueue();
    expect(session.link.end, const EndedByDrop());
    expect((states, closed), ([ConnectionState.disconnected], true));
    expect(released, [const EndedByDrop()]);
    expect(events.events.whereType<DisconnectedEvent>().single.reason, 'linkLoss');
  });
  test('a second end report publishes nothing and releases nothing', ...);        // Review Focus 1: still one event, one release
  test('a late connected report does not revive the link', ...);                  // L6: state stays disconnected
  test('disconnect() after a drop answers success without asking the platform', ...);  // closesAsked == 0
});
group('disconnect()', () {
  test('closes the link, ends on request and completes after the releases', ...); // release awaits a Completer; disconnect not done until it completes
  test('a second disconnect joins the close in flight', () {                      // Review Focus 2, in fakeAsync with closeDelay 1 s
    final first = session.disconnect(); final second = session.disconnect();
    async.elapse(const Duration(seconds: 1));
    expect(links.closesAsked(device), 1);                                          // and both futures are Right
  });
  test('disconnect during a drop\'s teardown completes after the releases', ...); // Review Focus 2
  test('a failed close leaves the link usable and answers the failure', ...);     // state back to ready; states emitted disconnecting, ready
  test('a failed close on a link that dropped meanwhile answers success', ...);
  test('logs disconnect entered, the transitions and disconnect resolved', ...);
});
group('releases', () {
  test('run in the order they were registered, once', ...);
  test('a failing release does not stop the others', () async {                   // Review Focus 5
    session.onEnd((_) => throw StateError('boom'));
    session.onEnd(released.add);
    expect(await session.disconnect(), const Right<ConnectionFailure, void>(null));
    expect(released, [const EndedOnRequest()]);
    expect(log.records.map((r) => r.message), contains('release failed'));
  });
  test('one registered after the end runs at once', ...);
});
group('whileUp', () {
  test('answers the operation\'s value while the link is up', ...);
  test('answers the end when the link ends first, and ignores the late answer', ...);  // orEnd receives EndedByDrop
  test('does not start the operation on a closing or ended link', ...);          // orEnd receives link.endInSight
});
test('an outage invalidates the link and reports radioOutage', ...);              // end: EndedByRadioOutage(RadioOutage.off)
test('servicesDiscovered makes the link ready, once', ...);                       // one `ready` on states
```

- [ ] **Step 2: Run to see them fail. Step 3: Implement** `link_session.dart`: one private method feeds an input to the `Link` and carries out the duty it answers; no state is kept outside the `Link` except the futures and subscriptions the session owns.
- [ ] **Step 4: Run** `flutter test test/features/connection` and the architecture tests.
- [ ] **Step 5: Commit.** `feat(connection): add LinkSession, which runs one link and releases on its end`

### Task 10: `LinkRegistry`, `ConnectDevice` and `BorrowLink`

Section 6.5.

**Files:**

- Create: `lib/src/features/connection/application/link_registry.dart`, `connect_device.dart`, `borrow_link.dart`
- Test: `test/features/connection/application/link_registry_test.dart`, `connect_device_test.dart`, `borrow_link_test.dart`

**Interfaces:**

- Consumes: `LiveLinks`, `LinkUser`, `Admission`, `AfterGiveBack`, `LinkSession`, `Links`, `ConnectingEvent`, `ConnectedEvent`, `package:clock`.
- Produces:

```dart
final class LinkRegistry {
  LinkRegistry({required Links links, required EventPublisher events, required Log log});
  /// The session of the device's link for [by], opened if there is none. [timeout] is this
  /// caller's whole budget: its wait for another caller's attempt and its own attempt share it.
  Future<Either<ConnectionFailure, LinkSession>> acquire(DeviceAddress device, {required LinkUser by, Duration? timeout});
  Future<Either<ConnectionFailure, void>> giveBack(LinkSession session);
  void keep(LinkSession session);
}

final class ConnectDeviceRequest { const ConnectDeviceRequest({required this.device, this.timeout}); final DeviceAddress device; final Duration? timeout; }
final class ConnectDevice {
  const ConnectDevice(LinkRegistry registry);
  Future<Either<ConnectionFailure, LinkSession>> run(ConnectDeviceRequest request);
}

final class BorrowLinkRequest { const BorrowLinkRequest({required this.device, this.timeout}); final DeviceAddress device; final Duration? timeout; }
final class BorrowLink {
  const BorrowLink(LinkRegistry registry);
  Future<Either<ConnectionFailure, BorrowedLink>> run(BorrowLinkRequest request);
}
/// A borrower's hold on a link. The first of [giveBack] and [keep] takes effect; later calls do nothing.
final class BorrowedLink {
  LinkSession get session;
  Future<Either<ConnectionFailure, void>> giveBack();
  void keep();
}
```

`acquire` asks `LiveLinks` and carries out the answer, in a loop. On `reuse` it answers the live session. On `open` it publishes `ConnectingEvent`, logs `connect started`, and asks `links.open` with the time left in the caller's budget; on success it builds the `LinkSession`, registers a release that forgets the device, publishes `ConnectedEvent` and logs `connect succeeded`; on failure it forgets the device and logs `connect failed` (`error`, with `'exception'` and `errorCode` naming the failure's type). On `wait` it waits for that device's next change (an open settling, or a link forgotten) and asks again; when the caller's budget runs out first it answers `ConnectFailed(ConnectFailureReason.timeout)` and touches nothing. Every log is under `bluey.connection` with `{'address': '<address>'}`, as today. `giveBack` and `keep` for a session that is no longer the device's live session change nothing.

- [ ] **Step 1: Write the failing tests** over `InMemoryLinks`, in `fakeAsync` where a delay is involved:

```dart
// link_registry_test.dart
test('an open is announced: connecting, then connected', ...);            // events in order; logs connect started, connect succeeded
test('a second acquire reuses the session and announces nothing', ...);   // identical(first, second); opensAsked == 1; still two events
test('two acquires at once start one open and answer the same session', ...);   // openDelay 1 s
test('a failed open answers the failure and forgets the device', ...);    // no ConnectedEvent; connect failed logged; the next acquire opens again
test('a waiter makes its own attempt when the attempt it waited on fails', () {   // Review Focus 4
  links.openDelay = const Duration(seconds: 1);
  links.failNextOpen(device, ConnectFailureReason.timeout);
  final borrower = registry.acquire(device, by: LinkUser.borrower, timeout: const Duration(seconds: 3));
  final app = registry.acquire(device, by: LinkUser.app);
  async.elapse(const Duration(seconds: 5));
  expect(resultOf(borrower), const Left<ConnectionFailure, LinkSession>(ConnectFailed(ConnectFailureReason.timeout)));
  expect(resultOf(app).fold((_) => null, (s) => s.link.isUp), isTrue);
  expect(links.opensAsked(device), 2);
});
test('a waiter\'s timeout does not cancel the attempt in flight', () {      // Review Focus 4
  links.openDelay = const Duration(seconds: 10);
  final app = registry.acquire(device, by: LinkUser.app);
  final borrower = registry.acquire(device, by: LinkUser.borrower, timeout: const Duration(seconds: 3));
  async.elapse(const Duration(seconds: 3));
  expect(resultOf(borrower), const Left<ConnectionFailure, LinkSession>(ConnectFailed(ConnectFailureReason.timeout)));
  async.elapse(const Duration(seconds: 7));
  expect(resultOf(app).fold((_) => null, (s) => s.link.isUp), isTrue);
  expect(links.opensAsked(device), 1);
});
test('a waiter\'s own attempt gets only the time it has left', ...);        // waited 1 s of 3 s: openTimeouts.last is 2 s
test('a caller that meets a closing link waits, then opens a new one', ...);   // closeDelay 1 s; a different session; opensAsked == 2
test('a link that ends is forgotten', ...);                               // drop; the next acquire opens a new link
test('a give-back by the only user closes the link', ...);
test('a give-back whose close fails answers the failure, and the next caller reuses the link', ...);

// connect_device_test.dart
test('answers the session of a new link, held by the app', ...);
test('passes the caller\'s timeout to the open', ...);

// borrow_link_test.dart
test('giving back a link only the borrower uses closes it', ...);         // closesAsked == 1; session.link.hasEnded
test('a give-back after the app connected leaves the link', () async {    // Review Focus 3
  final borrowed = rightOf(await borrow.run(BorrowLinkRequest(device: device)));
  final app = rightOf(await connect.run(ConnectDeviceRequest(device: device)));
  await borrowed.giveBack();
  expect(identical(app, borrowed.session), isTrue);
  expect(links.closesAsked(device), 0);
  expect(app.link.isUp, isTrue);
});
test('borrowing the app\'s link and giving it back leaves it', ...);
test('keep hands the link to the app, and a later give-back does nothing', ...);
test('only the first give-back takes effect', ...);                       // closesAsked == 1 after two
test('a borrower\'s open is announced like any other', ...);             // call 5
```

- [ ] **Step 2: Run to see them fail. Step 3: Implement** the three files. The registry holds `LiveLinks`, a map of device to live session, and one change signal per device; it holds no link state of its own.
- [ ] **Step 4: Run** `flutter test test/features/connection`, the architecture tests, and the domain coverage gate from Task 1 (expected: at or above 95%).
- [ ] **Step 5: Commit.** `feat(connection): add LinkRegistry, ConnectDevice and BorrowLink`

### Task 11: The failure translator, held to today's exceptions

Section 6.7.

**Files:**

- Create: `lib/src/api/analysis_options.yaml` (the same copy), `lib/src/api/failure_translation.dart`
- Test: `test/api/failure_translation_test.dart`, `test/api/failure_translation_parity_test.dart`

**Interfaces:**

- Consumes: `ConnectionFailure`, `LinkEnd`, `connectionFailureFrom` (Task 8), the public exceptions in `lib/src/shared/exceptions.dart`, `translatePlatformException`.
- Produces:

```dart
BlueyException connectionFailureAsException(ConnectionFailure failure, {required DeviceAddress device});
BlueyException linkEndAsException(LinkEnd end, {required DeviceAddress device});
/// The value, or the failure thrown as the exception an app gets today.
T valueOrThrow<T>(Either<ConnectionFailure, T> answer, {required DeviceAddress device});
```

| Failure | Exception |
| --- | --- |
| `ConnectFailed(reason)` | `ConnectionException(device, <the ConnectionFailureReason of the same name>)` |
| `LinkEnded(EndedOnRequest())` | `DisconnectedException(device.value, DisconnectReason.requested)` |
| `LinkEnded(EndedByDrop())` | `DisconnectedException(device.value, DisconnectReason.linkLoss)` |
| `LinkEnded(EndedByRadioOutage(outage))` | `StaleHandleException(cause: AdapterTransitionInvalidation(<the BluetoothState of the same name>), instanceType: InvalidatedInstance.connection)` |
| `RadioUnavailable()` | `BluetoothUnavailableException()` |
| `PermissionMissing(permission)` | `PermissionDeniedException([permission])` |
| `OperationTimedOut(operation)` | `GattTimeoutException(operation)` |
| `OperationRejected(operation, status)` | `GattOperationFailedException(operation, status)` |
| `UnexpectedPlatformFailure(detail, code, cause)` | `BlueyPlatformException(detail, code: code, cause: cause)` |

- [ ] **Step 1: Write the failing tests.** One test per row above, comparing type and fields. Then the parity test, which holds the two-step path to today's one-step path for every platform error a Connection operation can meet:

```dart
// failure_translation_parity_test.dart
const device = DeviceAddress('AA:BB:CC:DD:EE:01');
final platformErrors = <Object>[
  const GattOperationTimeoutException('connect'),
  const GattOperationDisconnectedException('readRssi'),
  const GattOperationStatusFailedException('requestMtu', 133),
  const GattOperationUnknownPlatformException('readRssi', code: 'some-code', message: 'detail'),
  const GattOperationUnknownPlatformException('readRssi', code: 'some-code'),
  for (final reason in PlatformConnectFailureReason.values) PlatformConnectFailedException(reason),
  const PlatformPermissionDeniedException('connect', permission: 'BLUETOOTH_CONNECT'),
  const PlatformBluetoothUnavailableException(),
  PlatformException(code: 'x', message: 'y'),
  PlatformException(code: 'x'),
  StateError('anything else'),
];
for (final error in platformErrors) {
  test('${error.runtimeType} translates as it does today', () {
    final today = translatePlatformException(error, operation: 'op', address: device.value);
    final now = connectionFailureAsException(connectionFailureFrom(error, operation: 'op'), device: device);
    expect(now.runtimeType, today.runtimeType);
    expect(now.toString(), today.toString());
  });
}
test('a rejected request reads as rejected whatever its status', () {      // call 10: the one row that differs
  final now = connectionFailureAsException(
      connectionFailureFrom(const GattOperationStatusFailedException('requestMtu', 0x80), operation: 'requestMtu'),
      device: device);
  expect(now, isA<GattOperationFailedException>().having((e) => e.status, 'status', 0x80));
});
```

The constructors above are written from the platform interface's exception classes; where one takes its arguments differently, the test follows the class. The parity list leaves out `gatt-handle-invalidated` and the advertise and respond exceptions: no Connection operation can meet them.

- [ ] **Step 2: Run to see them fail. Step 3: Implement** the three functions; each `switch` is exhaustive with no `default`.
- [ ] **Step 4: Run** `flutter test test/api` and the architecture tests (`api/` may name the unplaced `shared/exceptions.dart`; it names no infrastructure).
- [ ] **Step 5: Commit.** `feat(api): translate Connection's failures into today's exceptions`

### Task 12: The public interfaces move to the edge, with `Connections` and the borrow type

**Files:**

- Move: `lib/src/connection/connection.dart`, `android_connection_extensions.dart`, `ios_connection_extensions.dart` to `lib/src/api/connection/` (their tests to `test/api/connection/`)
- Create: `lib/src/api/connection/connections.dart`, `borrowed_connection.dart`
- Modify: every importer of the three moved files, `lib/bluey.dart` (export paths), `known_violations.dart`
- Test: `test/api/connection/connections_test.dart`, `borrowed_connection_test.dart`

**Interfaces:**

- Consumes: `LinkSession`, `LinkId`, `BorrowLink`, `BorrowedLink`, `valueOrThrow`.
- Produces:

```dart
/// One public Connection per link, so a second connect() returns the object the app already has.
final class Connections {
  Connections({required Connection Function(LinkSession session) present});
  Connection of(LinkSession session);            // the same object every time for one session
  LinkId? linkIdOf(Connection connection);       // for a Connection this made, ended or not; else null
}

/// A link in use for a short task by code that is not the app. The first of giveBack and keep counts.
final class BorrowedConnection {
  BorrowedConnection({required Connection connection, required Future<void> Function() giveBack, required void Function() keep});
  final Connection connection;
  Future<void> giveBack();                       // throws a BlueyException when the close fails
  void keep();
}
typedef BorrowConnection = Future<BorrowedConnection> Function(DeviceAddress device, {Duration? timeout});
/// Throws a BlueyException when the link cannot be had.
BorrowConnection borrowingThrough({required BorrowLink borrowLink, required Connections connections});
```

`Connections` keeps both lookups in `Expando`s, so a Connection the app has dropped is not kept alive. Neither new file is exported from `lib/bluey.dart`.

- [ ] **Step 1: Move the three tests and write the new ones** (over `InMemoryLinks` and a registry, with a stub `Connection` for `present`):

```dart
test('one session is presented once', ...);                      // identical(connections.of(s), connections.of(s)); present called once
test('two sessions are two Connections', ...);
test('answers the link id behind a Connection it made, after the link ended too', ...);
test('answers null for a Connection it did not make', ...);
test('a borrow presents the session\'s Connection', ...);         // identical to connections.of(session)
test('giving a borrowed Connection back closes a link only the borrower used', ...);
test('a borrow that cannot open the link throws the translated exception', ...);   // ConnectionException, deviceNotFound
test('a give-back whose close fails throws', ...);               // GattOperationFailedException
```

- [ ] **Step 2: Run to see them fail. Step 3: Move** the three files with `git mv`, fix every import, and implement the two new files.
- [ ] **Step 4: Bring the lists up to date.** The three `unplaced` entries leave, and so do the `boundaries` entries that start at or point to `connection/connection.dart`: `connection.dart -> gatt_client/gatt.dart`, and the three from `peer/peer_connection.dart`, `peer/peer_discovery.dart` and `peer/peer_remote_service_view.dart`. Run the API dump check (expected: no difference), `flutter test`, the architecture tests.
- [ ] **Step 5: Commit.** `refactor(api): move the public Connection interfaces to the edge and add Connections`

### Task 13: Peer discovery stops when its window closes, and survives a failing `stopScan` (L9, I394)

Section 6.9, third bullet. Probing itself is unchanged until Task 14.

**Files:**

- Modify: `lib/src/peer/peer_discovery.dart`, `test/fakes/fake_platform.dart` (`FakeOp.stopScan`)
- Test: `test/peer/peer_discovery_test.dart`

* [ ] **Step 1: Write the failing tests:**

```dart
test('a candidate seen after the window closes is not probed', () {
  fakeAsync((async) {
    // one candidate inside the 2 s window, a second advertised at 2 s + 1 ms
    ...
    expect(connectsTo(late), 0);
    expect(result, [earlyServerId]);
  });
});
test('discover waits for the probe in flight before it returns', ...);   // a probe begun at 1.9 s with a 1 s connect delay is in the result
test('a failing stopScan is logged and the peers found are still returned', () async {
  fake.enqueueFault(FakeOp.stopScan, StateError('radio busy'));
  expect(await discovery.discover(timeout: const Duration(seconds: 2)), [serverId]);
  // one `warn` record under bluey.peer.discovery: 'discoverPeers stopScan failed'
});
test('connectTo returns the Connection it found when stopScan fails', ...);
```

- [ ] **Step 2: Run to see them fail. Step 3: Implement.** The scan listener ignores a device once the window has closed, and one private method stops the scan and logs a failure instead of raising it; `discover` and `connectTo` both use it.
- [ ] **Step 4: Run** `flutter test test/peer` and the gates. **Step 5: Commit.** `fix(peer): stop probing when the discovery window closes and survive a failing stopScan (L9)`

### Task 14: The switch: every link goes through the registry (H3, L6, H2)

Sections 6.7, 6.8 and 6.9. After this commit nothing but `PlatformLinks` calls `connect`, `disconnect` or `connectionStateStream` on the platform, and nothing but `LinkSession` holds a link's state.

**Files:**

- Create: `lib/src/api/connection/bluey_connection.dart`, `test/fixtures/connection_rig.dart`
- Modify: `lib/src/connection/bluey_connection.dart` (the class becomes `LinkGattClient`), `lib/src/bluey.dart`, `lib/src/peer/peer_discovery.dart`, `lib/src/peer/bluey_peer.dart`, `known_violations.dart`, `test/known_defects/roster.dart`, `test/known_defects/domain_known_defects_test.dart`
- Test: `test/api/connection/bluey_connection_test.dart`; the H3 tests move to `test/features/connection/link_end_through_the_api_test.dart` and the H2 test to `test/peer/peer_discovery_test.dart`; `test/bluey_connection_test.dart`, `test/shared/with_error_translation_test.dart`, `test/peer/peer_discovery_test.dart` and `test/peer/bluey_peer_test.dart` build through `ConnectionRig`; `test/connection/bluey_connection_state_gating_test.dart:214`

**Interfaces:**

- Consumes: everything Tasks 2 to 12 produced.
- Produces:

```dart
// api/connection/bluey_connection.dart
/// One link's session presented as the public Connection.
final class BlueyConnection implements Connection {
  BlueyConnection({required LinkSession session, required LinkGattClient gatt});
}

// lib/src/connection/bluey_connection.dart (unplaced until slice 6)
class LinkGattClient {
  LinkGattClient({required platform.BlueyPlatform platformInstance, required LinkSession session,
      required BlueyLogger logger, EventPublisher? events});
  // keeps: services, service, hasService, servicesChanges, maxWritePayload, readRssi, android, ios
  // loses: state, stateChanges, disconnect, deviceAddress, connectionId, and its connection-state and adapter-state subscriptions
}

// peer
PeerDiscovery({required platform.BlueyPlatform platformApi, required BorrowConnection borrow, required BlueyLogger logger});
BlueyPeer createBlueyPeer({..., required BorrowConnection borrow, required String Function(Connection) connectionIdOf});

// test/fixtures/connection_rig.dart
/// The wiring Bluey does, over any BlueyPlatform, for tests that need a Connection without a Bluey.
class ConnectionRig {
  ConnectionRig(platform.BlueyPlatform platform, {BlueyLogger? logger, BlueyEventBus? events});
  Future<Connection> connect(DeviceAddress device, {Duration? timeout});   // throws as Bluey.connect does
  BorrowConnection get borrow;
  String connectionIdOf(Connection connection);
}
```

**How each piece changes**

- **`BlueyConnection`.** `deviceAddress` and `state` read the session's `Link`. `stateChanges` gives each listener the current state first, then the session's states, and closes with them; on an ended link it gives the end state and closes. `disconnect()` is `valueOrThrow(await session.disconnect(), device: ...)`. Every other member delegates to `gatt`.
- **`LinkGattClient`.** Its two guards read the `Link`: when the link is not up they throw `linkEndAsException(session.link.endInSight!, device: ...)`, which is `StaleHandleException` after an outage and `DisconnectedException` otherwise. `services()` calls `session.servicesDiscovered()` where it set `ready`. It registers one release with `session.onEnd` that cancels its Service Changed, bond and PHY subscriptions, delivers `StaleHandleException` on `servicesChanges`, `bondStateChanges` and `phyChanges` when the end is an outage, closes them and disposes the cached services. Every platform call that needs the link runs through one private helper, inside today's Service Changed abort and error translation:

```dart
/// Runs one throwing platform call so that the link's end answers it at once.
Future<T> _overLink<T>(Future<T> Function() call) async {
  final answer = await _session.whileUp<_Raised, T>(
    () async {
      try {
        return Right(await call());
      } catch (error, stack) {
        return Left(_Raised(error, stack));
      }
    },
    orEnd: (end) => _Raised(linkEndAsException(end, device: _session.link.device), StackTrace.current),
  );
  return answer.fold((raised) => Error.throwWithStackTrace(raised.error, raised.stack), (value) => value);
}
```

- **`Bluey`.** Builds, by constructor, `PlatformLinks`, `LinkRegistry`, `ConnectDevice`, `BorrowLink`, `Connections` (whose `present` builds a `BlueyConnection` over a new `LinkGattClient`) and the borrow function (`borrowingThrough`). `connect()` keeps `_requireAdapterOn()` and the `bluey` log line `connect entered`, runs `ConnectDevice`, and on a failure emits today's `ErrorEvent` with the translated exception and throws it. It no longer emits `ConnectingEvent` or `ConnectedEvent` and no longer logs under `bluey.connection`: the registry does. A private `_connectionIdOf(connection)` answers `_connections.linkIdOf(connection)?.value ?? connection.deviceAddress.toString()`; `_tryBuildPeerConnection` uses it, and `peer()` hands it to `createBlueyPeer`.
- **`PeerDiscovery`.** A probe borrows with `timeout: probeTimeout`, reads the server id through `connection.services(cache: true)` and the server-id characteristic's `read()`, and gives the link back, logging and swallowing a failure of the give-back. `connectTo` keeps the matching link and returns its `Connection`; every other candidate is given back. It no longer calls `connect`, `disconnect`, `discoverServices` or `readCharacteristic` on the platform, and no longer names `BlueyConnection`.
- **`BlueyPeer.connect`** asks `connectionIdOf(connection)` where it cast.

* [ ] **Step 1: Move the three known-defect tests into the mirrored tree, untagged, and write the new tests.**

```dart
// test/features/connection/link_end_through_the_api_test.dart: the two H3 tests, as written, plus
test('a dropped Connection stays disconnected when the device links again', () async {    // L6
  fake.simulateDisconnection(deviceId);
  await pumpEventQueue();
  final again = await bluey.connect(device);   // the platform reports connected for this device again
  await pumpEventQueue();
  expect((connection.state, again.state.isConnected), (ConnectionState.disconnected, true));
});
test('an operation after a drop fails with linkLoss', ...);                         // DisconnectedException, DisconnectReason.linkLoss
test('an operation in flight when the peer drops fails with linkLoss at once', ...);
test('a disconnect the platform fails leaves the Connection usable', ...);          // FakeOp.disconnect fault: throws; state is ready again; a read works

// test/bluey_connect_test.dart
test('a second connect returns the same Connection and announces nothing', () async {
  final first = await bluey.connect(device);
  final second = await bluey.connect(device);
  expect(identical(first, second), isTrue);
  expect(events.whereType<ConnectedEvent>(), hasLength(1));
});
test('two connects at once start one platform connect', ...);
test('connect after a drop opens a new Connection', ...);                           // not identical; the old one stays disconnected
test('a drop publishes DisconnectedEvent with linkLoss', ...);

// test/peer/peer_discovery_test.dart: the H2 test, as written, plus
test('a probe of a device the app holds reads over the app\'s link and leaves it', ...);   // no second platform connect; state ready
test('a probe gives back the link it opened', ...);                                 // the fake shows the device disconnected afterwards
test('BlueyPeer.connect keeps the link of the peer it found', ...);
```

Change `bluey_connection_state_gating_test.dart:214` to expect `DisconnectReason.requested`, and rename that test to say so.

- [ ] **Step 2: Run to see them fail.** `flutter test test/features/connection/link_end_through_the_api_test.dart` fails on both H3 tests as the known-defect run did; the H2 test fails in `test/peer`.
- [ ] **Step 3: Implement**, in this order so the suite compiles once at the end: `LinkGattClient`; `BlueyConnection`; `Bluey`; `PeerDiscovery` and `BlueyPeer`; `ConnectionRig`; then the tests that built the old classes directly.
- [ ] **Step 4: Strike the roster and lower the lists.** Delete the two H3 names and the H2 name from `test/known_defects/roster.dart` and their tests from `domain_known_defects_test.dart`. In `known_violations.dart`: the `boundaries` entries `connection/bluey_connection.dart -> platform/bluetooth_state.dart`, `peer/bluey_peer.dart -> connection/bluey_connection.dart` and `peer/peer_discovery.dart -> connection/bluey_connection.dart` leave; `oversized` is lowered for `connection/bluey_connection.dart` and `bluey.dart`.
- [ ] **Step 5: Run every gate:** `flutter test`, `flutter analyze`, the architecture tests, the list-growth command, `flutter test test/known_defects --run-skipped --tags known-defect` (expected: the six remaining defects fail), the API dump check (expected: no difference), both coverage gates.
- [ ] **Step 6: Commit.** `fix(connection): give every link one owner, so a dropped link ends like a requested one and discovery leaves the app's links alone (H3, L6, H2)`

### Task 15: `connectAsPeer` is a borrow

Section 6.5, last paragraph; ruling 3.

**Files:**

- Modify: `lib/src/bluey.dart`
- Test: `test/bluey/connect_as_peer_test.dart` (or the file that tests `connectAsPeer` today)

* [ ] **Step 1: Write the failing tests:**

```dart
test('a device the app holds that is not a peer keeps its link', () async {       // Review Focus 3
  final connection = await bluey.connect(plainDevice);
  await expectLater(bluey.connectAsPeer(plainDevice), throwsA(isA<NotABlueyPeerException>()));
  expect(connection.state.isConnected, isTrue);
  expect(await connection.readRssi(), isA<int>());
});
test('a device nobody holds that is not a peer is disconnected', ...);              // as today
test('a peer\'s link is kept, and is the Connection connect() returns', ...);     // identical(peer.connection, await bluey.connect(device))
test('a failure while checking gives the link back', ...);                          // no local identity: LocalIdentityRequiredException; the device is disconnected
```

- [ ] **Step 2: Run to see them fail** (the first: the app's Connection is disconnected). **Step 3: Implement.** `connectAsPeer` keeps `_requireAdapterOn()`, its two `bluey` log lines and the `ErrorEvent` on a failed connect, borrows the device's link, calls `keep()` when `_tryBuildPeerConnection` answers a peer, and gives the link back on every other outcome before throwing; a failing give-back propagates, as a failing disconnect does today.
- [ ] **Step 4: Run** `flutter test` and the gates; lower `bluey.dart`'s `oversized` entry if it changed. **Step 5: Commit.** `fix(peer): connectAsPeer borrows the link, so a non-peer the app holds keeps it`

### Task 16: Documents, every gate, and pull request 1

**Files (repository root):**

- Modify: `docs/ARCHITECTURE.md`, `CLAUDE.md`, `docs/roadmap.md`, `docs/backlog/` (the entries for I381, I380, I391, I394, I369 and I374), `bluey/docs/cross-platform-quirks.md` if it describes probing

* [ ] **Step 1: `docs/ARCHITECTURE.md`.** Section 2's layout comments name what now lives in `api/connection/`, `features/connection/` and `shared/{application,infrastructure}`. Section 5's list counts match the lists. Section 6's sample uses `ConnectionFailure` and the real translator, and its sentence about `shared/exceptions.dart` moving to `api/` in this slice is corrected (call 1). Section 11's table sends `Capabilities` to `features/platform` (decision 2) and gives `BlueyLogLevel` and `BlueyLogEvent` their home in `shared/application`.
* [ ] **Step 2: `CLAUDE.md`.** MTU moves from GATT Client's line to Connection's (call 2); the peer-composition and logging sections say that probes borrow links and that `bluey.connection` lines now come from Connection's application layer; a second `connect()` returning the same `Connection` is stated under Key Design Decisions.
* [ ] **Step 3: Backlog and roadmap.** Set `status: fixed`, `fixed_in` and `last_verified: 2026-11-18` on I381, I380, I391, I394 and I369, and flip their roadmap lines to `☑`. Give I374's roadmap line the tag "Slice 5 (server and peer)" and its backlog entry a note saying why (section 6.9). The health-check note names the one open High that remains, I063. The Unreleased section of bluey/CHANGELOG.md gains an entry for each app-visible change of section 7 that this pull request makes: the H3, H2 and L9 fixes, the second connect() returning the same Connection, the disconnect reasons, DisconnectedEvent, and BlueyEvent no longer sealed.
* [ ] **Step 4: Run every gate CI runs**, in every package: analyze, the format check, all four Dart suites, `bluey/example` and `bluey_ios/example` tests, architecture, list growth in every package, public API, both coverage gates, known defects in `bluey` (six) and `bluey_android` (one). Kotlin and XCTest are not run: no native file changed.
* [ ] **Step 5: Commit, push, open the pull request.** `docs: record the link lifecycle in the architecture guide, the backlog and the roadmap`. The description lists the findings closed, the app-visible changes of section 7 that belong to this pull request, rulings 1 to 3, 5, 6 and 19, and section 6.13's account of the entries that left the lists without their dependency changing.

## Pull request 2: the rest of Connection

Section 6.12. This pull request starts from `main` once pull request 1 has merged, on the same branch name. An app can observe it in four places: `Mtu(value)`, `PlatformKind` exported, a Service Changed event no longer failing an MTU request or a reading in flight, and status `0x80` on a request about a link reading as a rejection. Rulings 4, 5 and 20 name three smaller ones. `lib/src/bluey.dart` may not exceed the entry pull request 1 left it with at any commit, which is why Task 17 comes first: it takes Connection's wiring out of that file (ruling 21).

### Task 17: One assembly builds Connection for the edge

Ruling 21. Nothing an app can observe changes.

**Files:**

- Create: `lib/src/features/connection/application/ports/connection_ports.dart`, `lib/src/features/connection/infrastructure/adapters/platform_connection_ports.dart`, `lib/src/api/connection/connection_assembly.dart`, `test/fixtures/features/connection/application/ports/in_memory_connection_ports.dart`
- Modify: `lib/src/bluey.dart`, `test/fixtures/connection_rig.dart`, `known_violations.dart`
- Test: `test/api/connection/connection_assembly_test.dart`, `test/features/connection/infrastructure/adapters/platform_connection_ports_test.dart`

**Interfaces:**

- Consumes: `Links`, `PlatformLinks`, `LinkRegistry`, `ConnectDevice`, `BorrowLink`, `Connections`, `borrowingThrough`, `BlueyConnection`, `LinkGattClient`, `valueOrThrow`, `InMemoryLinks`.
- Produces:

```dart
// application/ports/connection_ports.dart
/// Everything Connection asks of the radio, handed over as one, so a host wires Connection in one
/// line and a new port reaches every host through this type. Tasks 21 to 24 add a field each.
final class ConnectionPorts {
  const ConnectionPorts({required this.links});
  final Links links;
}

// infrastructure/adapters/platform_connection_ports.dart
ConnectionPorts platformConnectionPorts(BlueyPlatform platform, {required Log log});

// api/connection/connection_assembly.dart
/// Connection as the edge uses it: its units built over its ports, and each link presented as one
/// public Connection.
final class ConnectionAssembly {
  ConnectionAssembly({required ConnectionPorts ports, required EventPublisher events, required Log log,
      required LinkGattClient Function(LinkSession session) gattFor});
  /// Throws the BlueyException Bluey.connect always has.
  Future<Connection> connect(DeviceAddress device, {Duration? timeout});
  BorrowConnection get borrow;
  LinkId? linkIdOf(Connection connection);
}

// test/fixtures/features/connection/application/ports/in_memory_connection_ports.dart
/// Every port as its in-memory double, for tests of the edge that need no platform.
ConnectionPorts inMemoryConnectionPorts({InMemoryLinks? links});
```

- [ ] **Step 1: Write the failing tests:**

```dart
// connection_assembly_test.dart, over inMemoryConnectionPorts()
test('connect presents one Connection per link', ...);          // identical for two connects; a different object once the link ended
test('connect throws what the failure translates to', ...);     // failNextOpen(device, ConnectFailureReason.deviceNotFound): ConnectionException
test('a borrow presents the Connection connect returns', ...);
test('answers the link id behind a Connection it presented, and null for any other', ...);
// platform_connection_ports_test.dart
test('its links are PlatformLinks over the platform it was given', ...);   // an open reaches the fake
```

- [ ] **Step 2: Run to see them fail. Step 3: Implement.** The assembly builds `LinkRegistry`, `ConnectDevice`, `BorrowLink`, `Connections` (presenting a `BlueyConnection` over `gattFor(session)`) and the borrow function in its constructor. `Bluey` builds one `ConnectionAssembly` over `platformConnectionPorts(_platform, log: _logger)` in place of the objects it built in Task 14, and keeps `_requireAdapterOn()`, its `bluey` log lines and the `ErrorEvent` on a failed connect. `ConnectionRig` builds the same assembly and keeps its three members.
- [ ] **Step 4: Run** `flutter test`, the gates, and the API dump check (expected: no difference). Lower `bluey.dart`'s `oversized` entry to its new count (expected: below what pull request 1 left).
- [ ] **Step 5: Commit.** `refactor(api): build Connection through one assembly, so its wiring leaves bluey.dart`

### Task 18: The value objects move into Connection's domain, and `Mtu` checks the specification's range

Section 6.12, fourth and fifth bullets; decision 2.

**Files:**

- Move: `connection_interval.dart`, `connection_parameters.dart`, `peripheral_latency.dart`, `supervision_timeout.dart`, `mtu.dart` and `write_payload_limit.dart` from `lib/src/connection/value_objects/` to `lib/src/features/connection/domain/value_objects/`, and their tests to `test/features/connection/domain/value_objects/`
- Create: `bond_state.dart` and `phy.dart` beside them (the two enums, out of `lib/src/api/connection/connection.dart`, which goes on exporting them)
- Modify: `lib/src/api/connection/connection.dart`, `lib/bluey.dart` (export paths), `lib/src/connection/bluey_connection.dart`, `lib/src/connection/connection_parameters_mapper.dart`, the 31 `Mtu(value, capabilities: ...)` call sites in 12 test files, `api/bluey.api`, `known_violations.dart`
- Test: `mtu_test.dart` (moved), `test/connection/capability_gating_test.dart`

**Interfaces:**

- Produces:

```dart
// domain/value_objects/mtu.dart: no import of the platform interface
class Mtu {
  /// Throws ArgumentError outside 23 to 517, the range the Bluetooth specification allows. Whether
  /// this platform can ask for the value is answered when the request is made.
  factory Mtu(int value);
  factory Mtu.fromPlatform(int value);   // unchanged: what the platform reported, unchecked
  static const Mtu minimum;              // unchanged: 23
}
// domain/value_objects/phy.dart
enum Phy { le1m, le2m, leCoded }
typedef PhyPair = ({Phy tx, Phy rx});    // not exported from lib/bluey.dart
// domain/value_objects/bond_state.dart
enum BondState { none, bonding, bonded }
```

- [ ] **Step 1: Move the tests and write the failing ones:**

```dart
// mtu_test.dart
test('accepts the range the specification allows', () {
  expect((Mtu(23).value, Mtu(517).value), (23, 517));
});
test('refuses a value outside it', () {
  expect(() => Mtu(22), throwsArgumentError);
  expect(() => Mtu(518), throwsArgumentError);
});
test('fromPlatform keeps what the platform reported', ...);     // Mtu.fromPlatform(600).value == 600

// test/connection/capability_gating_test.dart
test('an MTU above the maximum of the platform is refused when it is requested', () async {
  // a fake with Capabilities(platformKind: PlatformKind.android, canRequestMtu: true, maxMtu: 247)
  await expectLater(
    connection.android!.requestMtu(Mtu(248)),
    throwsA(isA<UnsupportedOperationException>()
        .having((e) => e.operation, 'operation', 'requestMtu above 247')
        .having((e) => e.platform, 'platform', 'android')),
  );
  expect(await connection.android!.requestMtu(Mtu(247)), Mtu(247));
});
```

- [ ] **Step 2: Run to see them fail** (`Mtu(23)` does not compile without `capabilities`). **Step 3: Implement.** Move the files with `git mv`; `Mtu` loses its import and its `capabilities` parameter and gains the upper bound, with the message `MTU must be <= 517 (BLE spec maximum): <value>`; the legacy extension's `requestMtu` refuses a value above `capabilities.maxMtu` after its capability check, until Task 25 hands that rule to `LinkFeatures`; every call site drops the argument.
- [ ] **Step 4: Bring the lists and the dump up to date.** The six `unplaced` entries under `connection/value_objects/` (all but `attribute_handle.dart`) and the `frameworkPlacement` entry for `value_objects/mtu.dart` leave. `dart run bluey_guards:public_api lib/bluey.dart api/bluey.api --write`: the one changed line is `factory Mtu(int value, {required Capabilities capabilities})` becoming `factory Mtu(int value)`. Run `flutter test`, the gates and the domain coverage gate.
- [ ] **Step 5: Commit.** `feat(connection)!: move the value objects into the domain; Mtu checks the specification's range`

### Task 19: Platform gets its own `Capabilities`

Section 6.12, third bullet; decision 2; call 6.

**Files:**

- Create: `lib/src/features/platform/domain/capabilities.dart`, `lib/src/features/platform/infrastructure/adapters/platform_capabilities.dart`
- Modify: `lib/bluey.dart`, `lib/src/bluey.dart` (`capabilities`), `api/bluey.api`, `known_violations.dart`, and the tests that compare `bluey.capabilities` with the platform interface's constants
- Test: `test/features/platform/domain/capabilities_test.dart`, `test/features/platform/infrastructure/adapters/platform_capabilities_test.dart`

**Interfaces:**

- Produces:

```dart
// features/platform/domain/capabilities.dart: the platform interface's class, member for member
enum PlatformKind { android, ios, fake, other }
@immutable
class Capabilities {
  const Capabilities({required this.platformKind, this.canScan = true, this.canConnect = true, ...});   // the same thirteen flags and defaults
  static const Capabilities android, iOS, macOS, windows, linux, fake;                                   // the same values
  // equal by value; the same toString
}
// features/platform/infrastructure/adapters/platform_capabilities.dart
Capabilities capabilitiesFrom(platform.Capabilities source);
```

- [ ] **Step 1: Write the failing tests:**

```dart
// platform_capabilities_test.dart: holds Bluey's constants in step with the platform interface's
final pairs = {
  'android': (platform.Capabilities.android, Capabilities.android),
  'iOS': (platform.Capabilities.iOS, Capabilities.iOS),
  'macOS': (platform.Capabilities.macOS, Capabilities.macOS),
  'windows': (platform.Capabilities.windows, Capabilities.windows),
  'linux': (platform.Capabilities.linux, Capabilities.linux),
  'fake': (platform.Capabilities.fake, Capabilities.fake),
};
for (final MapEntry(key: name, value: (theirs, ours)) in pairs.entries) {
  test('$name maps to the constant of the same name', () => expect(capabilitiesFrom(theirs), ours));
}
test('every flag is carried', ...);   // a matrix with each flag flipped from its default and maxMtu 185, field for field
// capabilities_test.dart: equal by value; differs when any one flag differs
// the test of Bluey's getter
test('bluey.capabilities answers Bluey\'s own Capabilities', () => expect(bluey.capabilities, Capabilities.fake));
```

- [ ] **Step 2: Run to see them fail. Step 3: Implement.** `Bluey.capabilities` answers `capabilitiesFrom(_platform.capabilities)`. `lib/bluey.dart` exports `Capabilities` and `PlatformKind` from the new file and drops its export of `bluey_platform_interface`. Code of other contexts still in the old folders goes on reading the platform's own flags until its slice.
- [ ] **Step 4: Bring the lists and the dump up to date.** The `publicExports` list is now empty. The API dump, written with `--write`, gains `enum PlatformKind` with its four values, and its `Capabilities` lines do not change. A test file that imports both libraries unprefixed and names `Capabilities` hides one of the two (one file today). Run `flutter test`, `bluey/example`'s tests, the gates and the domain coverage gate.
- [ ] **Step 5: Commit.** `feat(platform): give Bluey its own Capabilities and export PlatformKind`

### Task 20: `LinkFeatures`, and the two failures a platform's limits cause

Section 6.12, second and fourth bullets; ruling 16 and call 11.

**Files:**

- Create: `lib/src/features/connection/domain/link_features.dart`, `lib/src/features/connection/infrastructure/adapters/platform_link_features.dart`
- Modify: `lib/src/features/connection/domain/connection_failure.dart`, `lib/src/api/failure_translation.dart`, `lib/src/api/connection/connection_assembly.dart`, `bluey_connection.dart` and `borrowed_connection.dart`, `lib/src/bluey.dart`, `test/fixtures/connection_rig.dart`
- Test: `test/features/connection/domain/link_features_test.dart`, `connection_failure_test.dart`, `test/features/connection/infrastructure/adapters/platform_link_features_test.dart`, `test/api/failure_translation_test.dart`

**Interfaces:**

- Consumes: `Mtu`, `ConnectionFailure`, Platform's `Capabilities` (at the edge only).
- Produces:

```dart
// domain/link_features.dart
/// What links can do on this platform. It never changes while the app runs, so it is handed in at
/// construction and never asked for.
@immutable
final class LinkFeatures {
  const LinkFeatures({required this.canBond, required this.canRequestPhy, required this.canRequestParameters,
      required this.canRequestMtu, required this.maxMtu});
  final bool canBond, canRequestPhy, canRequestParameters, canRequestMtu;
  final int maxMtu;
  /// [desired] if this platform can ask for it, or why it cannot.
  Either<ConnectionFailure, Mtu> admit(Mtu desired);
}

// domain/connection_failure.dart
final class FeatureUnsupported extends ConnectionFailure { const FeatureUnsupported(this.operation); final String operation; }
final class MtuAboveMaximum extends ConnectionFailure {
  const MtuAboveMaximum({required this.requested, required this.maximum});
  final Mtu requested; final int maximum;
}

// infrastructure/adapters/platform_link_features.dart
LinkFeatures linkFeaturesFrom(platform.Capabilities source);

// api/failure_translation.dart: two rows need the platform's name (ruling 16)
BlueyException connectionFailureAsException(ConnectionFailure failure, {required DeviceAddress device, required String platform});
T valueOrThrow<T>(Either<ConnectionFailure, T> answer, {required DeviceAddress device, required String platform});

// api/connection: the name is read once, from Platform's Capabilities
ConnectionAssembly({..., required Capabilities capabilities});      // hands on capabilities.platformKind.name
BlueyConnection({..., required String platform});
BorrowConnection borrowingThrough({..., required String platform});
```

| Failure | Exception |
| --- | --- |
| `FeatureUnsupported(operation)` | `UnsupportedOperationException(operation, platform)` |
| `MtuAboveMaximum(requested, maximum)` | `UnsupportedOperationException('requestMtu above <maximum>', platform)` |

- [ ] **Step 1: Write the failing tests:**

```dart
// link_features_test.dart
const features = LinkFeatures(canBond: true, canRequestPhy: true, canRequestParameters: true, canRequestMtu: true, maxMtu: 247);
test('admits an MTU up to the maximum', () => expect(features.admit(Mtu(247)), Right<ConnectionFailure, Mtu>(Mtu(247))));
test('refuses an MTU above it', () => expect(features.admit(Mtu(248)),
    Left<ConnectionFailure, Mtu>(MtuAboveMaximum(requested: Mtu(248), maximum: 247))));
test('refuses every MTU on a platform that cannot ask for one', ...);   // canRequestMtu false: const FeatureUnsupported('requestMtu')
test('is equal by value', ...);
// platform_link_features_test.dart
test('carries the five facts from the flags of the platform', ...);    // canRequestParameters from canRequestConnectionParameters
// failure_translation_test.dart: one test per new row, type and fields; the parity test passes platform: 'fake'
```

- [ ] **Step 2: Run to see them fail** (the translator's `switch` no longer compiles: two cases are missing). **Step 3: Implement.** The two failures' messages are `<operation> is not supported on this platform` and `An MTU of <requested> is above this platform's maximum of <maximum>`. `Bluey` hands the assembly its `capabilities`.
- [ ] **Step 4: Run** `flutter test`, the gates, the domain coverage gate and the API dump check (expected: no difference).
- [ ] **Step 5: Commit.** `feat(connection): add LinkFeatures and the failures a platform's limits cause`

### Task 21: The MTU and the two readings

Section 6.12, first and sixth bullets; rulings 5 and 9.

**Files:**

- Create, under `lib/src/features/connection/`: `application/ports/mtu_negotiation.dart`, `application/ports/signal_strength.dart`, `application/mtu_session.dart`, `application/read_write_payload_limit.dart`, `application/read_rssi.dart`, `application/link_feature_check.dart`, `application/link_operation_log.dart`, `infrastructure/adapters/platform_mtu_negotiation.dart`, `infrastructure/adapters/platform_signal_strength.dart`
- Create, under `test/fixtures/features/connection/application/ports/`: `in_memory_mtu_negotiation.dart`, `mtu_negotiation_contract.dart`, `in_memory_signal_strength.dart`, `signal_strength_contract.dart`
- Modify: `lib/src/shared/domain/either.dart`, `connection_ports.dart`, `platform_connection_ports.dart`, `in_memory_connection_ports.dart`, `test/fakes/fake_platform.dart` (`FakeOp.getMaximumWriteLength`)
- Test: one per new source file, mirrored; `test/shared/domain/either_test.dart`

**Interfaces:**

- Consumes: `LinkSession.whileUp`, `LinkFeatures.admit`, `LinkEnded`, `EndedByRadioOutage`, `answering` (Task 8), `Log`, `package:clock`.
- Produces:

```dart
// shared/domain/either.dart
extension EitherFlatMapAsync<L, R> on Either<L, R> {
  /// Chains a step that answers later and can itself fail; stops at the first failure.
  Future<Either<L, T>> flatMapAsync<T>(Future<Either<L, T>> Function(R right) next);
}

// application/ports
abstract interface class MtuNegotiation {
  /// Asks the peer for [desired] and answers what the two sides settled on, which may be lower.
  Future<Either<ConnectionFailure, Mtu>> request(LinkId link, Mtu desired);
  /// The most one write on the link can carry.
  Future<Either<ConnectionFailure, WritePayloadLimit>> writePayloadLimit(LinkId link, {required bool withResponse});
}
abstract interface class SignalStrength {
  /// The link's RSSI in dBm, read now.
  Future<Either<ConnectionFailure, int>> read(LinkId link);
}

// application/link_feature_check.dart
/// Why [operation] cannot be asked of [link] before the radio is involved, in the order an app has
/// always seen: the end a radio outage brought, then a feature this platform lacks.
Either<ConnectionFailure, void> checkLinkFeature(Link link, {required String operation, bool supported = true});

// application/link_operation_log.dart
/// Runs one operation on a link and logs its start and its answer, as the GATT log always has.
Future<Either<ConnectionFailure, T>> loggedLinkOperation<T>(Log log, {required DeviceAddress device, required String op,
    String startDetail = '', required String Function(T value) completeDetail,
    required Future<Either<ConnectionFailure, T>> Function() run});

// application
final class MtuSession {
  MtuSession({required LinkSession session, required MtuNegotiation negotiation, required LinkFeatures features, required Log log});
  /// What the two sides last settled on: 23 until a request answers, since the radio reports no MTU by itself.
  Either<ConnectionFailure, Mtu> get mtu;
  Future<Either<ConnectionFailure, Mtu>> request(Mtu desired);
}
final class ReadWritePayloadLimit {
  const ReadWritePayloadLimit({required MtuNegotiation negotiation, required Log log});
  Future<Either<ConnectionFailure, WritePayloadLimit>> run(LinkSession session, {required bool withResponse});
}
final class ReadRssi {
  const ReadRssi({required SignalStrength strength, required Log log});
  Future<Either<ConnectionFailure, int>> run(LinkSession session);
}

// infrastructure/adapters
final class PlatformMtuNegotiation implements MtuNegotiation { const PlatformMtuNegotiation(BlueyPlatform platform); }
final class PlatformSignalStrength implements SignalStrength { const PlatformSignalStrength(BlueyPlatform platform); }

// ConnectionPorts gains: required MtuNegotiation mtu, required SignalStrength signal
```

`MtuSession.request` answers, in this order: the outage, for a link a radio outage ended (`checkLinkFeature`); what `features.admit(desired)` refuses; then the port's answer through `session.whileUp`, with `LinkEnded.new` for the link's end. A success is held, and a failure leaves the MTU it had. `mtu` answers the outage for a link an outage ended and the held value otherwise, a plain disconnect included, as today. The two reads run the port through `whileUp` and check nothing else.

All three log under `bluey.gatt`, the context these lines have always had, through `loggedLinkOperation` wrapped around the port call inside `whileUp`, so nothing is logged for a link that is not up: `debug` `<op> start` with `{'deviceId', 'op', 'detail'}`; `debug` `<op> complete` with `durationMs` and the detail; `error` `<op> failed` with `durationMs`, the start detail, `'exception'` and `errorCode` naming the failure's type, and `'status'` for an `OperationRejected` (ruling 5). Durations come from `clock.stopwatch()`.

| Unit | `op` | Start detail | Complete detail |
| --- | --- | --- | --- |
| `MtuSession.request` | `requestMtu` | `requested=<n>` | `requested=<n>, negotiated=<m>` |
| `ReadWritePayloadLimit` | `getMaximumWriteLength` | `withResponse=<bool>` | `withResponse=<bool>, limit=<n>` |
| `ReadRssi` | `readRssi` | none | `rssi=<n>dBm` |

- [ ] **Step 1: Write the failing tests** (the units over `InMemoryLinks`, the port's double and `RecordingLog`):

```dart
// mtu_session_test.dart
test('holds 23 until a request answers', ...);
test('a request holds what the two sides settled on', () async {
  negotiation.peerSettlesAt = 185;
  expect(await mtu.request(Mtu(247)), Right<ConnectionFailure, Mtu>(Mtu.fromPlatform(185)));
  expect(mtu.mtu, Right<ConnectionFailure, Mtu>(Mtu.fromPlatform(185)));
});
test('a platform that cannot ask for an MTU answers FeatureUnsupported and asks nothing', ...);   // negotiation.requests is empty
test('a request above the maximum answers MtuAboveMaximum and asks nothing', ...);
test('a request on a dropped link answers its end and asks nothing', ...);     // const LinkEnded(EndedByDrop())
test('after a radio outage the outage is answered before a missing feature', ...);   // request and mtu both answer LinkEnded(EndedByRadioOutage(RadioOutage.off))
test('a link that ends during a request answers the end', ...);                // the double answers after 1 s; the drop comes at 0.5 s
test('a failed request keeps the MTU it had', ...);
test('logs start and complete with what was requested and negotiated', ...);
test('a failed request logs the type of the failure, and its status', ...);    // OperationRejected('requestMtu', 133): errorCode 'OperationRejected', data['status'] == 133

// read_rssi_test.dart and read_write_payload_limit_test.dart, each
test('answers the reading', ...);
test('answers the end of a link that is not up, and asks nothing', ...);
test('logs start, complete and failed as the GATT log does', ...);

// link_feature_check_test.dart: nothing for an up link with the feature; FeatureUnsupported without it; the outage before either
// either_test.dart
test('flatMapAsync runs the next step on a success', ...);
test('flatMapAsync stops at a failure and does not run the step', ...);

// mtu_negotiation_contract.dart, run over InMemoryMtuNegotiation and over PlatformMtuNegotiation on FakeBlueyPlatform
//   answers the MTU that was asked for
//   answers the lower MTU the peer settles on
//   a rejected request answers OperationRejected with its status
//   a request that times out answers OperationTimedOut
//   answers the write payload limit for each kind of write
// signal_strength_contract.dart, likewise
//   answers the RSSI
//   a failed read answers the failure
// platform_mtu_negotiation_test.dart
test('a platform limit above 512 is answered as 512', ...);                    // I343, through WritePayloadLimit.fromPlatform
```

- [ ] **Step 2: Run to see them fail. Step 3: Implement.** Each contract takes a `create` function that answers a small harness (the port, the id of a link that is up, and the ways to make the peer settle lower, reject or time out), as `linksContract` does. `platformConnectionPorts` and `inMemoryConnectionPorts` fill the two new fields.
- [ ] **Step 4: Run** `flutter test test/features/connection test/shared`, the gates and the domain coverage gate.
- [ ] **Step 5: Commit.** `feat(connection): add the MTU session and the two link readings over their ports`

### What the sessions of Tasks 22 to 24 share

Each holds the last value its port reported for one link, and takes the requests that change it. The rules below are today's behaviour, read from `BlueyConnection`'s constructor and `_AndroidConnectionExtensionsImpl` at `2c75f03`, except where ruling 4 or 20 is named.

- **The feature decides whether the port is touched.** On a platform without the feature (`LinkFeatures`) the session never calls its port and holds the default: `BondState.none`; `Phy.le1m` both ways; an interval of 30 ms, a latency of 0 and a timeout of 4,000 ms.
- **Reading the value** answers `checkLinkFeature(link, operation: <the member's name>, supported: ...)` and then the held value. After a plain disconnect the last value is still answered; after a radio outage the outage is.
- **The changes** answer `FeatureUnsupported` on a platform without the feature, and otherwise a stream that gives each listener the held value, then every report, and ends when the link ends. It carries no errors (ruling 4): the adapter logs a platform stream error (`warn`, `bluey.connection`, `bond state reports failed` or `phy reports failed`) and goes on listening.
- **A request** answers `checkLinkFeature`, then the port's answer through `session.whileUp` with `LinkEnded.new`. Nothing is logged, as today.
- **The first read** is asked once, at construction. It is ignored when a report or a successful request has already set the value, or when the link has ended; a failed one is logged (`warn`, `bluey.connection`, `bond state read failed`, `phy read failed` or `connection parameters read failed`, with `deviceId` and the failure's type) and the default stays (ruling 20).
- **One release**, registered with `session.onEnd`, cancels the subscription and closes the changes.

The member names an app sees in `UnsupportedOperationException.operation` do not change: `bondState`, `bondStateChanges`, `bond`, `removeBond`; `txPhy`, `rxPhy`, `phyChanges`, `requestPhy`; `connectionParameters`, `requestConnectionParameters`.

### Task 22: Bonding

**Files:**

- Create: `application/ports/bonding.dart`, `application/bonding_session.dart`, `infrastructure/adapters/platform_bonding.dart` under `lib/src/features/connection/`; `in_memory_bonding.dart` and `bonding_contract.dart` under `test/fixtures/features/connection/application/ports/`
- Modify: `connection_ports.dart`, `platform_connection_ports.dart`, `in_memory_connection_ports.dart`, `test/fakes/fake_platform.dart` (`simulateBondState(String deviceId, PlatformBondState state)`, `simulateBondStateError(String deviceId, Object error)`, `FakeOp.getBondState`, `FakeOp.bond`, `FakeOp.removeBond`)
- Test: one per new source file, mirrored; `test/fakes/` gains tests for the fake's new seams

**Interfaces:**

```dart
abstract interface class Bonding {
  Future<Either<ConnectionFailure, BondState>> stateOf(LinkId link);
  /// Every bond state the radio reports for the link, to one listener. Carries no errors.
  Stream<BondState> changesOf(LinkId link);
  Future<Either<ConnectionFailure, void>> bond(LinkId link);
  Future<Either<ConnectionFailure, void>> removeBond(LinkId link);
}
/// One link's bond state, and the requests that change it.
final class BondingSession {
  BondingSession({required LinkSession session, required Bonding bonding, required LinkFeatures features, required Log log});
  Either<ConnectionFailure, BondState> get state;              // 'bondState'
  Either<ConnectionFailure, Stream<BondState>> get changes;    // 'bondStateChanges'
  Future<Either<ConnectionFailure, void>> bond();              // 'bond'
  Future<Either<ConnectionFailure, void>> removeBond();        // 'removeBond'
}
final class PlatformBonding implements Bonding { PlatformBonding(BlueyPlatform platform, {required Log log}); }
// ConnectionPorts gains: required Bonding bonding
```

- [ ] **Step 1: Write the failing tests:**

```dart
// bonding_session_test.dart
test('holds none until the radio says otherwise', ...);
test('the first read sets the state', ...);                                    // the double answers bonded
test('a report replaces the state and reaches each listener after the state it had', () async {
  final seen = <BondState>[];
  rightOf(bonding.changes).listen(seen.add);
  port.report(link, BondState.bonding);
  port.report(link, BondState.bonded);
  await pumpEventQueue();
  expect(seen, [BondState.none, BondState.bonding, BondState.bonded]);
  expect(bonding.state, const Right<ConnectionFailure, BondState>(BondState.bonded));
});
test('a first read that answers after a report does not replace it', ...);     // ruling 20
test('a failed first read is logged and the default stays', ...);              // ruling 20
test('a platform that cannot bond is never asked', ...);                       // port.asked is empty; each member answers FeatureUnsupported with its own name
test('after a plain disconnect the last state is still answered, and a request answers the end', ...);
test('after a radio outage the state and the requests answer the outage', ...);
test('the changes end when the link ends, and a later listener gets the last state and then the end', ...);
test('bond and removeBond ask the port while the link is up', ...);
test('a report after the link ended changes nothing', ...);                    // the release cancelled the subscription

// bonding_contract.dart, over InMemoryBonding and over PlatformBonding on FakeBlueyPlatform
//   answers the bond state
//   reports each change in order
//   a failed read answers the failure
//   bond and removeBond answer success
//   a rejected bond answers OperationRejected with its status
// platform_bonding_test.dart
test('a platform stream error is logged and the reports go on', ...);          // ruling 4: simulateBondStateError, then a report still arrives
```

- [ ] **Step 2: Run to see them fail. Step 3: Implement. Step 4: Run** `flutter test test/features/connection test/fakes` and the gates.
- [ ] **Step 5: Commit.** `feat(connection): add the bonding session over its port`

### Task 23: PHY

**Files:** as Task 22, with `phy_control.dart`, `phy_session.dart`, `platform_phy_control.dart`, `in_memory_phy_control.dart` and `phy_control_contract.dart`; the fake gains `simulatePhy(String deviceId, {required PlatformPhy tx, required PlatformPhy rx})`, `simulatePhyError(String deviceId, Object error)`, `FakeOp.getPhy` and `FakeOp.requestPhy`.

**Interfaces:**

```dart
abstract interface class PhyControl {
  Future<Either<ConnectionFailure, PhyPair>> pairOf(LinkId link);
  /// Every PHY pair the radio reports for the link, to one listener. Carries no errors.
  Stream<PhyPair> changesOf(LinkId link);
  /// Asks for a PHY in either direction; a direction left out keeps what it has.
  Future<Either<ConnectionFailure, void>> request(LinkId link, {Phy? tx, Phy? rx});
}
/// One link's PHY pair, and the request that changes it.
final class PhySession {
  PhySession({required LinkSession session, required PhyControl phy, required LinkFeatures features, required Log log});
  Either<ConnectionFailure, Phy> get tx;                           // 'txPhy'
  Either<ConnectionFailure, Phy> get rx;                           // 'rxPhy'
  Either<ConnectionFailure, Stream<PhyPair>> get changes;          // 'phyChanges'
  Future<Either<ConnectionFailure, void>> request({Phy? tx, Phy? rx});   // 'requestPhy'
}
final class PlatformPhyControl implements PhyControl { PlatformPhyControl(BlueyPlatform platform, {required Log log}); }
// ConnectionPorts gains: required PhyControl phy
```

A request that succeeds holds nothing itself: the radio's report is what changes the pair, as today.

- [ ] **Step 1: Write the failing tests:** the tests of Task 22, for the pair (`le1m` both ways until the radio says otherwise; a report of `(tx: Phy.le2m, rx: Phy.leCoded)` is answered by `tx`, `rx` and the changes), plus:

```dart
test('a request asks the port for the directions it was given', ...);          // request(tx: Phy.le2m): the double saw (tx: le2m, rx: null)
test('a request that succeeds leaves the pair until the radio reports', ...);
// phy_control_contract.dart: answers the pair; reports each change in order; a failed read answers the failure;
//   a request answers success; a rejected request answers OperationRejected with its status
// platform_phy_control_test.dart: each Phy maps to the PlatformPhy of the same name and back; a stream error is logged and the reports go on
```

- [ ] **Step 2: Run to see them fail. Step 3: Implement. Step 4: Run** the same commands as Task 22.
- [ ] **Step 5: Commit.** `feat(connection): add the PHY session over its port`

### Task 24: Connection parameters

**Files:** as Task 22, with `parameter_control.dart`, `parameter_session.dart`, `platform_parameter_control.dart`, `in_memory_parameter_control.dart` and `parameter_control_contract.dart`; the fake gains `simulateConnectionParameters(String deviceId, PlatformConnectionParameters parameters)`, `FakeOp.getConnectionParameters` and `FakeOp.requestConnectionParameters`.

**Interfaces:**

```dart
abstract interface class ParameterControl {
  Future<Either<ConnectionFailure, ConnectionParameters>> parametersOf(LinkId link);
  Future<Either<ConnectionFailure, void>> request(LinkId link, ConnectionParameters parameters);
}
/// One link's timing, and the request that changes it.
final class ParameterSession {
  ParameterSession({required LinkSession session, required ParameterControl parameters, required LinkFeatures features, required Log log});
  Either<ConnectionFailure, ConnectionParameters> get parameters;                     // 'connectionParameters'
  Future<Either<ConnectionFailure, void>> request(ConnectionParameters parameters);   // 'requestConnectionParameters'
}
final class PlatformParameterControl implements ParameterControl { const PlatformParameterControl(BlueyPlatform platform); }
// ConnectionPorts gains: required ParameterControl parameters
```

The radio reports no changes of its parameters, so there is no stream and no release: a request that succeeds holds what was asked for, as today. The adapter owns the mapping to and from `PlatformConnectionParameters`. A platform answer outside the specification's ranges is answered as `UnexpectedPlatformFailure`, never thrown. `connection_parameters_mapper.dart` stays until Task 25 removes its last caller.

- [ ] **Step 1: Write the failing tests:**

```dart
// parameter_session_test.dart
test('holds 30 ms, 0 and 4,000 ms until the first read answers', ...);
test('the first read sets the parameters', ...);
test('a request that succeeds holds what was asked for', ...);
test('a failed request keeps the parameters it had', ...);
test('a first read that answers after a successful request does not replace it', ...);   // ruling 20
test('a failed first read is logged and the default stays', ...);                        // ruling 20
test('a platform that cannot request parameters is never asked', ...);                   // both members answer FeatureUnsupported with their names
test('after a plain disconnect the parameters are still answered, and a request answers the end', ...);
test('after a radio outage both answer the outage', ...);
// parameter_control_contract.dart: answers the parameters; a failed read answers the failure; a request answers success;
//   a rejected request answers OperationRejected with its status
// platform_parameter_control_test.dart
test('maps interval, latency and timeout both ways', ...);                               // 30.0 ms, 0, 4000 ms
test('an answer outside the specification is a failure, not a throw', ...);              // intervalMs 1.0: UnexpectedPlatformFailure
```

- [ ] **Step 2: Run to see them fail. Step 3: Implement. Step 4: Run** the same commands as Task 22, and the domain coverage gate.
- [ ] **Step 5: Commit.** `feat(connection): add the parameter session over its port`

### Task 25: The edge takes over the link's facts

Section 6.12, fifth to seventh bullets; calls 2 and 10; rulings 4, 5 and 20. After this commit `LinkGattClient` is the GATT client and nothing else: it reads no bond state, PHY, parameters, MTU, RSSI or write limit, and Connection's sessions answer every one of them.

**Files:**

- Create: `lib/src/api/connection/android_connection.dart`, `ios_connection.dart`
- Modify: `lib/src/api/connection/connection_assembly.dart` and `bluey_connection.dart`, `lib/src/connection/bluey_connection.dart`, `lib/src/bluey.dart`, `test/fixtures/connection_rig.dart`, `test/fakes/fake_platform.dart` (`getMaximumWriteLength` honours `operationLatency`), `known_violations.dart`
- Delete: `lib/src/connection/connection_parameters_mapper.dart`, `test/connection/connection_parameters_mapper_test.dart` (the adapter's test of Task 24 holds the mapping now)
- Move, unchanged: `test/connection/android_extensions_test.dart` to `test/api/connection/android_connection_test.dart`; `bluey_connection_capabilities_test.dart`, `max_write_payload_test.dart` and `state_stream_conventions_test.dart` to `test/api/connection/`. `capability_gating_test.dart` stays where it is: it also holds `Bluey.bondedDevices` and the server's advertising gate
- Test: `test/api/connection/android_connection_test.dart` (added to), `test/features/connection/link_facts_through_the_api_test.dart`

**Interfaces:**

- Consumes: `MtuSession`, `BondingSession`, `PhySession`, `ParameterSession`, `ReadRssi`, `ReadWritePayloadLimit`, `LinkFeatures`, `linkFeaturesFrom`, `ConnectionPorts` with its six fields, `valueOrThrow`, `linkEndAsException`, Platform's `Capabilities`.
- Produces:

```dart
// api/connection/connection_assembly.dart
ConnectionAssembly({required ConnectionPorts ports, required LinkFeatures features, required Capabilities capabilities,
    required EventPublisher events, required Log log, required LinkGattClient Function(LinkSession session) gattFor});

// api/connection/bluey_connection.dart
BlueyConnection({required LinkSession session, required LinkGattClient gatt, required ReadRssi readRssi,
    required ReadWritePayloadLimit readWritePayloadLimit, required AndroidConnectionExtensions? android,
    required IosConnectionExtensions? ios, required String platform});

// api/connection/android_connection.dart
/// One link's bond, PHY, timing and MTU as the Android extension an app reads.
final class AndroidConnection implements AndroidConnectionExtensions {
  AndroidConnection({required LinkSession session, required BondingSession bonding, required PhySession phy,
      required ParameterSession parameters, required MtuSession mtu, required String platform});
}

// api/connection/ios_connection.dart
final class IosConnection implements IosConnectionExtensions { const IosConnection(); }

// lib/src/connection/bluey_connection.dart (unplaced until slice 6)
class LinkGattClient {
  // keeps: services, service, hasService, servicesChanges
  // loses: maxWritePayload, readRssi, android, ios, the two extension classes, the bond and PHY subscriptions and
  //        controllers, the three first reads, the held MTU and the _map* functions
}
```

**How each piece changes**

- **`ConnectionAssembly`** builds `ReadRssi` and `ReadWritePayloadLimit` once. When it presents a link on a platform whose `capabilities.platformKind` is `android`, it builds that link's four sessions at once, so each listens from the link's first moment, and presents an `AndroidConnection` over them. On `ios` it presents the one `const IosConnection()`. On every other kind both extensions are null, as today, and no session is built, since nothing could read one.
- **`AndroidConnection`.** Each member is one session member through `valueOrThrow`, with the link's device and the platform's name bound once in a private helper:

| Member | Session member |
| --- | --- |
| `bondState`, `bondStateChanges`, `bond()`, `removeBond()` | `bonding.state`, `bonding.changes`, `bonding.bond()`, `bonding.removeBond()` |
| `txPhy`, `rxPhy`, `phyChanges`, `requestPhy(txPhy:, rxPhy:)` | `phy.tx`, `phy.rx`, `phy.changes`, `phy.request(tx:, rx:)` |
| `connectionParameters`, `requestConnectionParameters(params)` | `parameters.parameters`, `parameters.request(params)` |
| `mtu`, `requestMtu(desired)` | `mtu.mtu`, `mtu.request(desired)` |

The two change streams keep section 6.7's convention through one more private helper. A platform without the feature throws from the getter, as today. Otherwise the getter answers a broadcast stream: a listener that arrives after a radio outage ended the link gets `StaleHandleException` and then the end, with no value; any other listener gets the session's stream, and when that stream ends because of a radio outage, `StaleHandleException` before the end.

- **`BlueyConnection`.** `readRssi()` and `maxWritePayload()` run the two reads over the session through `valueOrThrow`; `android` and `ios` answer what it was handed. Every remaining member that is not the link's state still delegates to `gatt`.
- **`LinkGattClient`** loses what the comment above lists. The release it registered in Task 14 now cancels the Service Changed subscription, ends `servicesChanges` and disposes the cached services, and nothing else.
- **`Bluey` and `ConnectionRig`** hand the assembly `features: linkFeaturesFrom(platform.capabilities)`.

The order an app meets refusals in does not change: the radio outage first, then the missing feature (or the MTU above the maximum), then the link's end. Today's `_ensureValid()`, `_requireCapability(...)` and `_ensureConnected()` run in that order, and `checkLinkFeature` followed by `whileUp` keeps it.

- [ ] **Step 1: Move the four test files and write the failing tests.** The moved files are the regression net and are not edited. New, over a `Bluey` on a fake whose capabilities are Android's kind with every flag on and `maxMtu: 517`:

```dart
// test/features/connection/link_facts_through_the_api_test.dart
test('a Service Changed event does not fail a reading or an MTU request in flight', () {   // call 2
  fakeAsync((async) {
    fake.operationLatency = const Duration(seconds: 1);
    final rssi = connection.readRssi();
    final mtu = connection.android!.requestMtu(Mtu(247));
    final limit = connection.maxWritePayload(withResponse: true);
    async.elapse(const Duration(milliseconds: 500));
    fake.simulateServiceChange(deviceId);
    async.elapse(const Duration(seconds: 1));
    expect(resultOf(rssi), isA<int>());
    expect(resultOf(mtu), Mtu(247));
    expect(resultOf(limit), isA<WritePayloadLimit>());
  });
});
test('a drop fails a reading in flight at once, with linkLoss', ...);   // 1 s latency, the drop at 0.5 s: DisconnectedException(linkLoss) before the second is up

for (final (name, op, ask) in <(String, FakeOp, Future<Object?> Function(Connection))>[        // call 10
  ('requestMtu', FakeOp.requestMtu, (c) => c.android!.requestMtu(Mtu(247))),
  ('readRssi', FakeOp.readRssi, (c) => c.readRssi()),
  ('bond', FakeOp.bond, (c) => c.android!.bond()),
  ('requestPhy', FakeOp.requestPhy, (c) => c.android!.requestPhy(txPhy: Phy.le2m)),
  ('requestConnectionParameters', FakeOp.requestConnectionParameters,
      (c) => c.android!.requestConnectionParameters(parameters)),
]) {
  test('$name rejected with status 0x80 reads as rejected, and the Connection stays connected', () async {
    fake.enqueueFault(op, GattOperationStatusFailedException(name, 0x80));
    await expectLater(ask(connection),
        throwsA(isA<GattOperationFailedException>().having((e) => e.status, 'status', 0x80)));
    expect(connection.state.isConnected, isTrue);
  });
}

test('a platform bond stream error never reaches bondStateChanges', () async {             // ruling 4
  final seen = <BondState>[];  final errors = <Object>[];
  connection.android!.bondStateChanges.listen(seen.add, onError: errors.add);
  fake.simulateBondStateError(deviceId, StateError('boom'));
  fake.simulateBondState(deviceId, PlatformBondState.bonded);
  await pumpEventQueue();
  expect((seen, errors), ([BondState.none, BondState.bonded], isEmpty));
});
test('a failed readRssi logs the type of the failure', ...);     // ruling 5: a timeout fault; the 'readRssi failed' record has errorCode 'OperationTimedOut'
test('a failed first bond read leaves bondState at none and connect() succeeds', ...);   // ruling 20: FakeOp.getBondState fault; one warn record
test('connecting on a kind that is neither Android nor iOS asks the platform for no bond state, PHY or parameters', ...);

// test/api/connection/android_connection_test.dart, over inMemoryConnectionPorts()
test('each member answers what its session holds', ...);         // a report on each double is read back through the extension
test('bondStateChanges and phyChanges end without an error on a disconnect', ...);
test('a listener after a radio outage gets StaleHandleException and no value', ...);
test('a listener before a radio outage gets its values, then StaleHandleException, then the end', ...);
test('requestPhy passes each direction to the session under its own name', ...);          // requestPhy(txPhy: Phy.le2m): the double saw (tx: le2m, rx: null)
```

- [ ] **Step 2: Run to see them fail.** `flutter test test/features/connection/link_facts_through_the_api_test.dart`: the Service Changed test fails with the `AttributeHandleInvalidatedException` a Service Changed event raises on every operation in flight today; the five `0x80` tests fail with `DisconnectedException`; the bond-error test collects one error.
- [ ] **Step 3: Implement**, in this order so the suite compiles once at the end: `AndroidConnection` and `IosConnection`; `BlueyConnection`; `ConnectionAssembly`; `LinkGattClient` (delete what it loses, with the mapper file and its test); `Bluey` and `ConnectionRig`. Remove the request-time maximum check Task 18 put in the legacy extension: `LinkFeatures.admit` holds that rule now, and Task 18's test of it passes unchanged.
- [ ] **Step 4: Lower the lists.** In `known_violations.dart`: the `unplaced` and `frameworkPlacement` entries for `connection/connection_parameters_mapper.dart` leave; `oversized` is lowered for `connection/bluey_connection.dart`, and `bluey.dart`'s entry is set to its count if that changed (never above the base's).
- [ ] **Step 5: Run every gate:** `flutter test`, `flutter analyze`, the architecture tests, the list-growth command, the known-defect run (expected: the six remaining defects fail), the API dump check (expected: no difference), both coverage gates.
- [ ] **Step 6: Commit.** `feat(connection): the edge reads a link's facts from Connection's sessions, bounded by the link's end`

### Task 26: Documents, every gate, and pull request 2

**Files (repository root):**

- Modify: `docs/ARCHITECTURE.md`, `CLAUDE.md`, `bluey/CHANGELOG.md`, `docs/roadmap.md`, `docs/backlog/I325-expose-platform-max-write-payload.md` (its sample still writes `Mtu(caps.maxMtu, capabilities: caps)`). No README and nothing under `bluey/example/lib` builds an `Mtu` with `capabilities` or names `Capabilities`, so neither changes

* [ ] **Step 1: `docs/ARCHITECTURE.md`.** Section 2's layout names `features/platform`, Connection's six ports, its sessions and reads, `LinkFeatures`, and `ConnectionAssembly` with the two extension classes at the edge. Section 5's list counts match the lists, and `public exports` is shown empty. Section 11's table marks Connection's value objects, the parameter mapping and `Capabilities` as moved.
* [ ] **Step 2: `CLAUDE.md`.** The architecture section says `Capabilities` and `PlatformKind` are Bluey's own, in the Platform context; the platform-tagged extensions section names `AndroidConnection` and `IosConnection` at the edge over Connection's sessions; `Mtu(value)` is shown where a sample builds one; the Key Files line for `known_violations.dart` is unchanged.
* [ ] **Step 3: Changelog and roadmap.** The Unreleased section of `bluey/CHANGELOG.md` gains: **Breaking**, `Mtu(value)` takes no `capabilities` and checks 23 to 517, and a request above the platform's maximum throws `UnsupportedOperationException` when it is made; **Added**, `PlatformKind` is exported; **Changed**, a Service Changed event no longer fails `requestMtu`, `maxWritePayload` or `readRssi` in flight, and status `0x80` on a request about a link throws `GattOperationFailedException`. `docs/roadmap.md` marks slice 1 complete and names slice 2 as next.
* [ ] **Step 4: Run every gate CI runs**, in every package, as Task 16 lists them. Known defects: `bluey` six, `bluey_android` one. Kotlin and XCTest are not run: no native file changed.
* [ ] **Step 5: Commit, push, open the pull request.** `docs: record the rest of Connection in the architecture guide and the changelog`. The description lists section 7's rows that belong to this pull request (`Mtu(value)`, `PlatformKind`, Service Changed, `0x80`), rulings 4, 5, 20 and 21, and section 6.13's table of what still reaches across contexts and the slice that ends each.

## Self-review

Run against the design once the last task was written.

**1. Spec coverage.** Every section of the design has a task.

| The design | Tasks |
| --- | --- |
| 6.1 language | Global Constraints, held in every task |
| 6.2 layout | File structure; rulings 2, 7 and 21 say where it differs |
| 6.3 the link lifecycle | 3 (ruling 19 changes one row) |
| 6.4 the session and teardown | 9 |
| 6.5 live links, connecting, borrowing, `connectAsPeer` | 4, 10, 15 |
| 6.6 ports, adapters, the failure family, the parity test | 5, 6, 8, 11, 20 to 24 |
| 6.7 the edge | 11, 12, 14, 17, 25 |
| 6.8 what stays behind | 14, 25 |
| 6.9 peer discovery, and I374 to slice 5 | 13, 14, 16 |
| 6.10 the platform packages | 7, and the fake in 8 |
| 6.11 the kernel moves | 2 |
| 6.12 the rest of Connection | 17 to 25 |
| 6.13 where contexts still meet | the two pull request descriptions (16, 26), and the design review below |
| 7 what an app can see | each row: 2, 9, 10, 11, 14, 18, 19, 25; the changelog in 16 and 26 |
| 8 findings | H3: 14. L6: 3, 9, 14. H2: 14. M3 and I369: 7. L9: 13. I374: roadmap row in 16 |
| 10 testing | a table test per domain unit (3, 4), a contract per port (6, 21 to 24), the moved tests (12, 14, 25) |
| 11 calls 1 to 12 | 1: 16. 2: 16, 25. 3: 10, 14. 4: 14 (ruling 1). 5: 10. 6: 19. 7: 6, 21 to 24. 8: 8. 9: 10. 10: 11, 25. 11: 20. 12: 14 |

One place where the plan does less than a row of the design: section 6.6 lists "a link's negotiated MTU" under `MtuNegotiation`, and the port in Task 21 has no such read. `BlueyPlatform` has none to ask (it offers `requestMtu` and `getMaximumWriteLength` only), so the session holds 23 until a request answers, as the code does today.

**2. Step scan.** Every step names its files, its signatures and the command that proves it. Tests are given by name with their assertion, in code where the values matter and as a trailing comment where the name and one value decide the test. One function body is written out, `_overLink` in Task 14, because where a throwing platform call crosses into `whileUp` is the one thing its signature and tests do not decide. Found and fixed in this pass: the `rightOf` and `resultOf` helpers were used by tests and defined nowhere (now in Global Constraints); Task 25's step 2 named the wrong exception for today's Service Changed abort.

**3. Type consistency.** The names that change between tasks were followed through every task that touches them:

| Name | Where it changes |
| --- | --- |
| `valueOrThrow`, `connectionFailureAsException` | 11 defines them; 20 adds `platform`, and names every caller in its file list |
| `BlueyConnection`'s constructor | 14 (`session`, `gatt`); 20 adds `platform`; 25 adds the two reads and the two extensions |
| `ConnectionAssembly`'s constructor | 17; 20 adds `capabilities`; 25 adds `features` |
| `ConnectionPorts` | 17 (`links`); 21 (`mtu`, `signal`); 22 (`bonding`); 23 (`phy`); 24 (`parameters`) |
| `LinkGattClient`'s members | 14 lists what it keeps; 25 lists what it keeps after losing the link's facts |
| `borrowingThrough` | 12; 20 adds `platform` |
| `PhySession.request(tx:, rx:)` against the public `requestPhy(txPhy:, rxPhy:)` | 23 and 25; a test in 25 holds the mapping |

**4. Review Focus.** Each of the five has its test in the task that owns the code: 3 and 9; 9; 4, 10, 14 and 15; 10; 8 and 9.

**5. Proportion.** The plan is about four times the design's length. The design is one context described in prose; the plan is 26 commits, each with its file list, its signatures and its tests. Its code blocks are signatures, test tables and test names; the one body is named above. Where a task repeated a neighbour, it now refers to it (Tasks 23 and 24 to Task 22, and the three sessions to one shared section).

## Design review (cohesion, coupling, DDD, Clean Architecture)

The design's own review (its section 12) judged the units the design names, and it holds. This review judges what the plan adds to it: the units, files and signatures the design left to the builder, the order of the commits, and every claim about today's code that a ruling or a task rests on.

**Bounded context and language.** Every placed file in this plan is Connection's, the kernel's or Platform's, and the edge is where they meet GATT Client and Peer. Connection's new names stay in its language: link, link end, radio outage, borrower, session, link features. Nothing placed under `features/connection` says probe, peer, server, GATT or `Capabilities`; the platform's name, which only a public exception needs, stays at the edge (ruling 16). Platform gets its first placed file, its own `Capabilities`, and Connection is never handed it. The public vocabulary does not change.

**Single responsibility of each unit the plan adds.**

| Unit | Layer | Its one responsibility |
| --- | --- | --- |
| `LinkInput`, `LinkEnd` in their own files | Connection, domain | What can happen to a link; why one ended (ruling 7) |
| `connectionFailureFrom`, `answering` | Connection, infrastructure | Everything the platform throws, as a `ConnectionFailure`, for every adapter |
| `DeviceStreams` | each platform package | Own a device's two stream controllers and decide when they open and close (ruling 10) |
| `BorrowedConnection`, `borrowingThrough` | edge | A borrow in the public `Connection`'s terms, so Peer names nothing of Connection's application (ruling 2) |
| `ConnectionPorts` | Connection, application ports | Hand Connection's ports to a host as one. It has no behaviour |
| `platformConnectionPorts` | Connection, infrastructure | Build every adapter over one platform |
| `ConnectionAssembly` | edge | Build Connection's units over its ports and present each link as one public `Connection`. It decides nothing: every rule it carries out is a unit's |
| `LinkFeatures.admit` | Connection, domain | The one rule about a platform's limits: whether an MTU may be asked for |
| `checkLinkFeature` | Connection, application | The order of refusals the four sessions share, stated once |
| `loggedLinkOperation` | Connection, application | The start, complete and failed lines of an operation on a link, stated once |
| `AndroidConnection`, `IosConnection` | edge | Present one link's sessions as the platform-tagged extension |
| `capabilitiesFrom`, `linkFeaturesFrom` | Platform and Connection, infrastructure | Map the platform interface's capabilities, deciding nothing |
| `ConnectionRig` | test fixture | The wiring `Bluey` does, for tests that need a `Connection` without a `Bluey` |

**Dependencies and their direction.** Checked against `LayerRule` and `BoundaryRule` as `bluey_architecture.dart` configures them.

- Domain: `LinkFeatures` names `Mtu` and `ConnectionFailure`, both Connection's domain, and `Either` from `shared/domain`. `Mtu` loses its import of the platform interface in Task 18, which is the last framework import in Connection's domain.
- Application: the sessions and reads name `LinkSession`, their one port, `LinkFeatures` and the `Log` port. `ConnectionPorts` names the six port interfaces and nothing else. No session names another session.
- Infrastructure: each adapter names its port, the domain and `bluey_platform_interface`. `platformConnectionPorts` names the adapters. `linkFeaturesFrom` takes the platform interface's capabilities, never Platform's.
- Edge: `ConnectionAssembly`, `BlueyConnection`, `AndroidConnection` and `Connections` name Connection's application and domain, Platform's domain (`Capabilities`, for `android`, `ios` and the platform's name), the kernel's two ports, and the unplaced `LinkGattClient`. None names infrastructure, which `LayerRule` would refuse for any file under `api/`; `lib/src/bluey.dart` builds the adapters and hands them in.
- Unplaced code: `LinkGattClient` names Connection's application (inward). Peer names `BorrowConnection` and the public `Connection`, both at the edge.
- Nothing placed points outward, and the plan adds no entry to any list.

**Layer of each file.** As the File structure section lists them. The three placements a reader might question: `ConnectionPorts` sits with the ports because it is their type and nothing more; `checkLinkFeature` and `loggedLinkOperation` are application because they order and log work and decide no rule; `ConnectionAssembly` is edge because it builds edge objects, and it may be so because it is handed its ports.

**Cohesion and coupling.** Each fact about a link has one owner after Task 25: its session. The GATT client no longer holds a second copy of the MTU, the bond state or the PHY. The four sessions share two small functions and the `LinkSession`'s release, and no state. The assembly is the one place that knows which units Connection has, so a new port reaches `Bluey` and the test rig through one type instead of two constructors.

**What still crosses a boundary after this plan, and what ends it.** The design's section 6.13 stands. The plan adds three, none on any list:

| What crosses | Why it stays | Ended by |
| --- | --- | --- |
| Between the two pull requests, `LinkGattClient` still answers the bond state, PHY, parameters, MTU and the two readings | Pull request 1 is the lifecycle alone | Task 25 |
| `ConnectionAssembly` is handed a function that builds the unplaced `LinkGattClient` | The GATT client's port is GATT Client's to declare | Slice 6 |
| Connection's application logs the MTU request and the two readings under the context `bluey.gatt` | The context is what a log consumer filters on today, so renaming it is an app-visible change and not this slice's to make | Whenever Joel wants the log contexts revised |

**Claims checked against the source at `2c75f03`.**

- One assertion pins the `unknown` disconnect reason, `test/connection/bluey_connection_state_gating_test.dart:214` (ruling 1).
- Both connection managers sit exactly on their size entries: 428 lines (`bluey_android`) and 431 (`bluey_ios`) (ruling 10).
- `SizeRule` holds an entry equal to the file's count, and the list-growth gate compares with the pull request's base, so `bluey.dart` may never exceed what pull request 1 leaves it with (ruling 21, and the order of Task 17).
- `LayerRule` refuses infrastructure to every file under `api/` and to the public libraries except the composition roots, and leaves the edge free to name unplaced code (`bluey_guards/lib/src/architecture/rules/layer_rule.dart`). `lib/bluey.dart` exports `BlueyLogLevel` and `BlueyLogEvent` and not `BlueyLogger`, so Task 2 gives the public library no infrastructure to name.
- The legacy extension checks in the order outage, capability, link (`connection/bluey_connection.dart:1541-1564`, `:853-856`); a change stream's getter throws for a missing capability only, and its stream gives a late listener after an outage the error and the end with no value, and any other listener the held value first (`:827-851`, `:1548-1559`).
- `requestMtu`, `maxWritePayload` and `readRssi` log under `bluey.gatt` with the details Task 21's table copies, emit no event, and are the only users of the held MTU, which starts at 23 (`:141`, `:709-767`). A Service Changed event fails every operation in flight with `AttributeHandleInvalidatedException` (`:478-500`).
- The first bond, PHY and parameter reads have no error handler and can overwrite a newer report (`:245-287`) (ruling 20). The bond and PHY requests are not logged.
- `BlueyPlatform` offers no read of the negotiated MTU (`platform_interface.dart:472-485`).
- `Mtu`'s factory is called with `capabilities` at 31 places in 12 test files. Only `connection.dart`, `lib/bluey.dart`, the mapper and `bluey_connection.dart` import the six value objects that move, so Task 18 adds no boundary.
- `lib/bluey.dart` exports `Capabilities` alone from the platform interface; the API dump has `Capabilities` and no `PlatformKind`; `Bluey.capabilities` hands out the platform's object (`bluey.dart:172`).
- `FakeBlueyPlatform` throws `UnimplementedError` from its bond, PHY and parameter methods when the capability is off, and `test/connection/bluey_connection_capabilities_test.dart` connects on such a platform, which pins "the feature decides whether the port is touched". Its `operationLatency` covers `requestMtu` and `readRssi` and not `getMaximumWriteLength`, which Task 25 adds.
- `test/connection/capability_gating_test.dart` also tests `Bluey.bondedDevices` and the server's advertising gate (`:239`, `:277`), so it does not move to the edge's folder.
- `Either` has `fold`, `map` and `flatMap` and no asynchronous form (`shared/domain/either.dart`); `test/fixtures/` does not exist yet; `bluey/CHANGELOG.md` has an Unreleased section.

**Findings, fixed in this document before the verdict.**

1. Pull request 2 would have wired five more adapters and four sessions inside `bluey.dart`, which its size entry forbids. Ruling 21 and Task 17 take Connection's wiring out of that file first.
2. Between Tasks 18 and 25 nothing would have checked an MTU against the platform's maximum. Task 18 keeps the check in the legacy extension, under a public-API test that Task 25 must still pass.
3. A `disconnect()` during a close the radio began had no close in flight to join. Ruling 19 has it ask for the close.
4. The sessions would have inherited two defects of the first reads. Ruling 20 fixes both and says so.
5. `flatMapAsync` was scheduled a task before its first caller, against the design's "when the first unit needs them". It is added in Task 21.
6. The first draft built the four sessions for every link. On a platform with neither extension nothing can read them, so Task 25 builds them only where it presents the Android extension, and a test holds that such a platform is asked nothing.
7. Pull request 1 changed what an app sees and wrote no changelog entry. Task 16 writes it.
8. The composition-root sentence of Global Constraints placed `lib/src/bluey.dart` under `api/`. It is unplaced, and the sentence now says what the rule is.

Not fixed, and recorded above: Connection's application logs three operations under a context named for GATT.

Verdict: ready.

## Execution

Nothing runs until Joel approves this plan. On approval the thread switches to Opus for the whole build, as agreed, and starts at Task 1. A design question that comes up during the build stops the slice and goes to Joel.

Each pull request is opened when its last task's gates are green, assigned to Joel for review, and watched until it merges. Pull request 2 starts only after pull request 1 has merged.

Two ways to run the tasks:

- **Subagent-driven.** A fresh subagent implements each task and a fresh reviewer checks it before the next one starts, then a whole-branch review at the end. Most thorough; costs a fresh context per task and per review.
- **Native.** One session implements every task, then one fresh reviewer on the most capable model checks the whole branch. Cheapest and fastest; no independent review until the end.

**Recommended: subagent-driven.** Tasks 14 and 25 each switch every app's connect path over in one commit, where a mistake found only at the end is expensive to unpick, and each task's Interfaces block was written so that an implementer who sees only that task has what it needs. The foundation slice ran this way.
