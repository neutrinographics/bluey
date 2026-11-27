# Scanning and Advertising Sessions (slice 2): Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give scanning and advertising one owner each: one radio scan shared by a scan per caller in Discovery, and one advertising session in GATT Server, closing M2/I013, M4/I336, M5/I382, L1/I386, the Dart half of M8/I385 and I320.

**Architecture:** The shape slice 1 gave `Link`. A pure, immutable aggregate per radio activity (`RadioScan`, `Advertising`) takes an input and answers the next aggregate, the events raised and at most one duty. One application session per `Bluey` feeds it, runs the duties over a port, and holds timers and streams. One adapter answers each port over `BlueyPlatform`. `api/<context>/` translates phases, events and failures into the public ones. The composition root (`lib/src/bluey.dart`) builds the adapters and hands the ports to an assembly.

**Tech Stack:** Dart 3 (sealed classes, records, switch expressions), Flutter 3.47.x, `fake_async`, the `bluey_guards` package, Pigeon (Android only, one callback), Kotlin (one call site).

**Spec:** `docs/superpowers/specs/2026-11-27-scanning-and-advertising-sessions-design.md` ("the design"), approved by Joel on 2026-11-27. An implementer reads the design section each task names before the task; where this plan refines a name, this plan wins and "Names refined" below lists every such name.

## Global Constraints

- TDD: no production line without a failing test first (Red, Green, Refactor). A task's first commit may hold the failing test alone.
- A list in any `known_violations.dart` or `roster.dart` only shrinks. An entry whose path moved is rewritten to the new path with the same count; nothing is added.
- `bluey/lib/src/bluey.dart` stays at or under 974 lines. `bluey/lib/src/shared/exceptions.dart` stays at or under 578 lines. `bluey/lib/src/events.dart` (477) and `bluey/lib/src/gatt_server/bluey_server.dart` (1180) only shrink, and their `oversized` entries are lowered in the commit that shrinks them. No new file exceeds 300 lines.
- `bluey/api/bluey.api` changes only by: `ScanFailedException` and `ScanFailureReason` (new), an optional `timestamp` parameter on the five scan events (Part A) and the four advertising events (Part B), and the import paths the dump records for moved declarations. Any other difference fails the task.
- No bounded context imports another. `features/discovery`, `features/gatt_server` and `features/connection` share only `shared/`. An `api/<context>/` file names only its own context's `features/<context>/`. Nothing under `features/` or `shared/` names `api/`.
- Domain files import only `dart:core`, `dart:async`, `dart:collection`, `dart:typed_data`, `package:meta`, their own context's domain and `shared/domain`. Aggregates hold no timer, no stream and no `await`.
- Below `api/` a failure is a value (`Either<Failure, T>`). The only raises allowed in placed code are `StateError`, `ArgumentError` and `UnimplementedError`, for programming errors.
- Only the composition root (`lib/src/bluey.dart`) names infrastructure. Assemblies are handed ports.
- Log lines keep today's contexts and wording (`bluey`, `bluey.server`, `bluey.peer.discovery`); new lines follow the same style. No log rewording (I399 is out of scope).
- No `!` on a nullable in new or touched code. Comments say why, never how; no journal comments, no finding or ruling numbers in code.
- Coverage: 90% of `bluey`'s lines, 95% under `lib/src/features/*/domain` and `lib/src/shared/domain`, no file with code that no test loads.
- Tests use `FakeBlueyPlatform` and in-memory doubles, never mocks, and follow `docs/testing-conventions.md` (simulated time, the fakeAsync broadcast-cancel trap). Each test is laid out `// arrange`, `// act`, `// assert`.
- Commits are Conventional Commits, scoped (`feat(discovery): …`, `refactor(shared): …`, `feat(gatt-server): …`), and name no model.
- Two pull requests. Part A on `claude/project-thread-30zhyu` as it stands. Part B on the same branch name, restarted from `main` after Part A merges.
- Gates that run in the cloud session, all green before each pull request: every Dart suite of the five packages, `flutter analyze`, the format check, the guards' tests, the architecture tests, list growth, the public API dump, known defects, both coverage floors (commands in `CLAUDE.md`). The Kotlin Gradle tests and XCTest run on Joel's Mac; Task A8 is the only task that changes native code.

## Review Focus

The conditions most likely to bite an app that no task's happy path exercises. Each has its test in the task named.

1. **`stop()` then `scan()` in the same turn, a thousand times.** The radio is asked to stop once per stop and to scan once per restart, never left scanning with every scanner stopped, and no scan is left `Waiting` for ever. Test in A4 (the table) and A7 (a loop over `InMemoryScanning` asserting `scansAsked`, `stopsAsked` and the final radio phase).
2. **A subscription cancelled while its scan is still `Waiting`, and a scan whose timeout fires while the radio is stopping.** Both leave cleanly: the stream closes, the timer is cancelled, and the radio is not started for a scan nobody holds. Test in A7.
3. **A platform result that does not parse** (a malformed service UUID, manufacturer data without a company id). It is logged and dropped; the scan keeps delivering, and no error reaches the app's stream. Test in A9.
4. **A scan refusal that arrives late**, after the app stopped or after a newer scan replaced the refused one. It ends no scan it does not describe and never becomes an unhandled async error. Tests in A4 (`RadioRefused` in `RadioQuiet`, `RadioUnsure` and `RadioStopping` does nothing) and A8 (a superseded rejection is dropped in both Dart adapters).
5. **`startAdvertising` twice without awaiting, `stopAdvertising` during a replace, and `dispose()` of a server while a start is in flight.** Asks are served in order, each caller gets its own answer, the state ends where the radio is, and no timer survives. Test in B4.

## Names refined

The design's §11 leaves names to the plan "where the code reads better". These differ from the design because two of its names would collide in one Dart library, or to match what the public events need:

| Design | Plan | Why |
|---|---|---|
| Radio phases `Quiet`, `Scanning`, `Stopping`, `Unsure` | `RadioQuiet`, `RadioScanning(coverage)`, `RadioStopping`, `RadioUnsure` (sealed `RadioPhase`) | `Scanning` is the port's name |
| Scan phases `Waiting`, `Scanning`, `Leaving`, `Ended` | `Waiting`, `Served`, `Leaving(end)`, `Ended(end)` (sealed `ScanPhase`) | the same collision; the design already says a waiting scan is "not yet served" |
| `ScannerPhase` values | `ScannerIdle`, `ScannerStarting`, `ScannerScanning`, `ScannerStopping`, `ScannerLost(outage)`, `ScannerClosed` | sealed, since `lost` carries the outage |
| Input `ScannerClosed(scanner)` | `ScannerDisposed(scanner)` | `ScannerClosed` is the phase |
| Duty `Scan(coverage)` | `ScanFor(coverage)` | reads as a duty |
| `ScanAsk` = filter and mode | `ScanAsk` = filter, mode and optional `timeLimit` | the public `ScanStartingEvent` and `ScanStartedEvent` carry the timeout, so the ask the events name must hold it. The aggregate never acts on it; `OpenScan` holds the timer |
| Advertising phases `Idle`, `Starting`, `On`, `Stopping`, `Replacing` | `AdvertisingIdle`, `AdvertisingStarting(ask)`, `AdvertisingOn(ask)`, `AdvertisingStopping(ask, by)`, `AdvertisingReplacing(old, next)` | `Starting` and `Stopping` would otherwise be ambiguous beside the scanner's in tests and docs; `by` records whether a request or the time limit asked, which decides the end |
| Advertising duties `Start(ask)`, `Stop` | `StartAdvertising(ask)`, `StopAdvertising` | the same |

## File Structure

The design's §6.2 is the file map; this plan adds only:

| File | Responsibility | Task |
|---|---|---|
| `bluey/lib/src/shared/domain/uuid_parsing.dart` | `uuidFrom(String)`: a UUID from text the radio or platform sent, as an `Either` | A1 |
| `bluey/lib/src/features/discovery/domain/radio_phase.dart` | `RadioPhase`, split from `radio_scan.dart` to keep it under 300 lines | A4 |
| `bluey/lib/src/api/gatt_server/advertising.dart` | the edge library `lib/bluey.dart` exports for advertising (`AdvertiseMode`, the four events) | B1, B6 |
| `bluey/test/fixtures/features/discovery/application/ports/{in_memory_scanning,scanning_contract,recording_scan_events}.dart` | the double, the contract suite and the event recorder | A6 |
| `bluey/test/fixtures/features/gatt_server/application/ports/{in_memory_advertiser,advertiser_contract,recording_advertising_events}.dart` | the same for advertising | B3 |

Tests mirror each production path under `bluey/test/` (`test/features/discovery/domain/radio_scan_test.dart`, `test/api/discovery/…`), as slice 1's do.

---

# Part A: Scanning (pull request 1)

## Task A0: Pre-flight

- [ ] On `claude/project-thread-30zhyu` (the two design commits and this plan on top of `main` at `48cf097` or later): install Flutter 3.47.x, `dart pub get` at the root.
- [ ] Start the build ledger at `.superpowers/sdd/2026-11-27-scanning-advertising/` (git-ignored) with `progress.md` and `parked-minors.md`, as in slice 1.
- [ ] Run every cloud gate once on the untouched branch and record the baseline: test counts, both coverage figures, each list's length, `wc -l` of `bluey.dart`, `events.dart`, `bluey_server.dart`, `exceptions.dart`.
- [ ] Re-read `bluey_android/android/src/main/kotlin/**/Scanner.kt` and `Advertiser.kt` and confirm the three claims the design's §12 leaves for the plan: `onScanFailed` calls `onScanComplete`; `startScan` stops a running scan first; `startAdvertising` answers success while already advertising. If any is false, stop and record it in the ledger: the design's replace rule (§6.7) or the "scan replaces" rule (§6.3) rests on it and the question goes back to Joel.

## Task A1: The kernel gains `UUID`, `ManufacturerData` and `RadioOutage`

Design §6.2. Mechanical: no behaviour changes.

**Files:**
- Move: `bluey/lib/src/shared/uuid.dart` to `shared/domain/uuid.dart`; `shared/manufacturer_data.dart` to `shared/domain/manufacturer_data.dart`; their tests to `test/shared/domain/`
- Create: `shared/domain/radio_outage.dart` (the enum `RadioOutage`, cut out of `features/connection/domain/link_end.dart`), `shared/domain/uuid_parsing.dart`
- Modify: every importer; `lib/bluey.dart` (two export paths); `test/architecture/known_violations.dart` (the two `unplaced` entries leave; any entry naming an old path is rewritten)
- Test: `test/shared/domain/uuid_parsing_test.dart`

**Interfaces:**
- Produces:
  - `enum RadioOutage { off, unauthorized, unsupported, unknown }` at `shared/domain/radio_outage.dart`, unchanged.
  - `Either<MalformedUuid, UUID> uuidFrom(String raw)` and `final class MalformedUuid implements Failure { const MalformedUuid(this.raw); final String raw; }`. It is a top-level function, not a static on `UUID`, because `UUID` is public and `Either` is not.

- [ ] **Step 1:** `git mv` the two files and their tests, cut `RadioOutage` into its own file, fix every import (`link_end.dart` imports it; it does not re-export it). Run `flutter analyze` and the `bluey` suite: green with no test edited beyond imports.
- [ ] **Step 2: Failing test** for `uuidFrom`: `'180d'`, `'0000180d-0000-1000-8000-00805f9b34fb'` and an upper-case form answer `Right(UUID(...))` equal to the throwing constructor's value; `''`, `'xyz'`, `'180'` and a 33-character hex string answer `Left(MalformedUuid(raw))`.
- [ ] **Step 3:** Implement `uuidFrom` by validating with the same rules `UUID._normalize` applies, without catching an `ArgumentError` to do it (extract the check both share).
- [ ] **Step 4:** Remove the two `unplaced` entries. Run the architecture test, list growth, the API dump check (paths only) and the format check. Commit `refactor(shared): move UUID, ManufacturerData and RadioOutage into the kernel`.

## Task A2: One classification of what a platform call throws

Design §6.9.

**Files:**
- Create: `bluey/lib/src/shared/infrastructure/platform_errors.dart`, `shared/infrastructure/radio_outages.dart`
- Modify: `features/connection/infrastructure/adapters/platform_failures.dart`, `platform_links.dart`
- Test: `test/shared/infrastructure/platform_errors_test.dart`, `radio_outages_test.dart`; `test/features/connection/infrastructure/adapters/platform_failures_test.dart` and `platform_links_test.dart` pass unedited

**Interfaces:**
- Produces:

```dart
/// What any platform call can throw that belongs to no single context.
sealed class PlatformError {}
final class PermissionDenied extends PlatformError { final String permission; }
final class RadioUnavailable extends PlatformError {}
final class Unexpected extends PlatformError { final String detail; final String? code; final Object cause; }

PlatformError platformErrorOf(Object error);

/// The platform's adapter state as outages: every state that is not `on`,
/// and `unknown` for an error on the state stream.
Stream<RadioOutage> radioOutagesOf(BlueyPlatform platform);
```

  `platformErrorOf` maps `PlatformPermissionDeniedException` to `PermissionDenied`, `PlatformBluetoothUnavailableException` to `RadioUnavailable`, a Flutter `PlatformException` to `Unexpected(message ?? 'platform error ($code)', code)`, and anything else to `Unexpected(error.toString())`, which are `connectionFailureFrom`'s last four arms today, word for word.

- [ ] **Step 1: Failing tests** for `platformErrorOf` (one per arm, asserting the detail text above) and `radioOutagesOf` (`off`, `unauthorized`, `unsupported`, `unknown` pass through as outages; `on` emits nothing; a stream error emits `RadioOutage.unknown`).
- [ ] **Step 2:** Implement both. `Unexpected` in `shared/infrastructure` and Connection's `RadioUnavailable` failure share a simple name; `platform_failures.dart` imports `platform_errors.dart` with a prefix.
- [ ] **Step 3:** Rewrite `connectionFailureFrom`: its own arms first (the GATT ones and `PlatformConnectFailedException`), then `switch (platformErrorOf(error))` with no default. Replace the body of `PlatformLinks.outages` with `radioOutagesOf(_platform)` and delete `_outageOf`.
- [ ] **Step 4:** Run Connection's adapter tests unedited, the `bluey` suite and the architecture test. Commit `refactor(shared): classify platform errors and radio outages once`.

## Task A3: Discovery's values and what a scan asks

Design §6.1, §6.3 (coverage rules), §6.4 (failures).

**Files:**
- Move: `lib/src/discovery/{device,advertisement,scan_result}.dart` to `features/discovery/domain/`; `discovery/scan.dart` to `features/discovery/domain/scan_mode.dart`; their tests to `test/features/discovery/domain/`
- Create in `features/discovery/domain/`: `scan_filter.dart`, `scan_ask.dart`, `scan_id.dart`, `scan_phase.dart`, `scanner_phase.dart`, `scan_failure.dart`
- Modify: `lib/src/discovery/{scanner,bluey_scanner}.dart` and `lib/src/bluey.dart` (imports); `lib/bluey.dart` (the four export lines become exports through `lib/src/discovery/scanner.dart` for now, which re-exports the four domain files; Task A10 moves that file to the edge); `known_violations.dart` (four `unplaced` entries leave)
- Test: one `_test.dart` per created file

**Interfaces:**
- Produces:

```dart
sealed class ScanFilter {
  /// Everything when [services] is null or empty.
  factory ScanFilter.of(Iterable<UUID>? services);
  ScanFilter union(ScanFilter other);
  bool covers(ScanFilter other);
  bool shows(Advertisement advertisement);
}
final class Everything extends ScanFilter {}
final class ServicesOnly extends ScanFilter { final Set<UUID> services; }

final class ScanAsk {
  const ScanAsk({required this.filter, this.mode, this.timeLimit});
  final ScanFilter filter;
  final ScanMode? mode;        // absent states no preference
  final Duration? timeLimit;   // carried for the events; never read by the aggregate
}

final class ScanCoverage {
  const ScanCoverage({required this.filter, this.mode});
  /// A [StateError] for no asks: coverage exists only while a scan is open.
  factory ScanCoverage.of(Iterable<ScanAsk> asks);
  bool covers(ScanAsk ask);
  ScanCoverage widenedBy(ScanAsk ask);
}

final class ScanId { const ScanId(this.value); final int value; }
final class ScannerId { const ScannerId(this.value); final int value; }

sealed class ScanPhase {}      // Waiting, Served, Leaving(ScanEnd end), Ended(ScanEnd end)
sealed class ScanEnd {}        // EndedOnRequest, EndedByTimeout, EndedByFailure(ScanFailure failure), EndedByRadioOutage(RadioOutage outage)

sealed class ScannerPhase {
  /// The standing of a scanner that is neither lost nor closed, from its scans.
  static ScannerPhase of(Iterable<ScanPhase> scans);
}                              // ScannerIdle, ScannerStarting, ScannerScanning, ScannerStopping, ScannerLost(RadioOutage outage), ScannerClosed

sealed class ScanFailure implements Failure {}
// ScanRefused(ScanRefusalReason reason), ScanPermissionMissing(String permission),
// ScanRadioUnavailable(), UnexpectedScanFailure(String detail, {String? code, required Object cause})
enum ScanRefusalReason { alreadyStarted, registrationFailed, internalError, unsupported, outOfHardwareResources, startedTooOften, unknown }
```

  All are immutable with equality by value. Modes rank `lowPower < balanced < lowLatency` (the enum's declared order is not the rank).

- [ ] **Step 1:** `git mv` the four files and their tests; fix imports; remove the four `unplaced` entries. Suite, architecture test and API dump (paths only) green. Commit `refactor(discovery): place Discovery's values in its domain`.
- [ ] **Step 2: Failing tests, as values.**
  - `ScanFilter`: `of(null)` and `of([])` are `Everything`; `of([a, a])` equals `of([a])`; `Everything ∪ x` is `Everything` either way round; `{a} ∪ {b}` is `{a, b}`; `Everything` covers anything; `{a, b}` covers `{a}` and not `{c}` and not `Everything`; `{a}.shows` an advertisement listing `a` and `b`, not one listing only `c`, not one listing nothing; `Everything.shows` anything.
  - `ScanCoverage`: `of([{a}, {b, lowPower}])` is `({a, b}, lowPower)`; `of([lowPower, lowLatency, balanced asks])` has `lowLatency`; `of` asks that state no mode has `mode == null`; `covers` is false for a filter not covered and false for a stated mode busier than the coverage's (including a stated mode against an absent one), true for an ask with no mode; `widenedBy` an ask already covered answers an equal coverage; `timeLimit` never changes equality of coverage.
  - `ScannerPhase.of`: any `Served` gives `ScannerScanning`; else any `Waiting` gives `ScannerStarting`; else any `Leaving` gives `ScannerStopping`; else (none, or all `Ended`) `ScannerIdle`.
  - `ScanFailure.message` is a sentence for each member.
- [ ] **Step 3:** Implement to green. Commit `feat(discovery): say what a scan asks and what the radio must cover`.

## Task A4: `RadioScan` decides what the radio does

Design §6.3: the table of seven inputs and the rules behind it. This task covers the radio and the scans; Task A5 adds scanners, events and result routing.

**Files:**
- Create: `features/discovery/domain/radio_phase.dart`, `radio_scan_input.dart`, `radio_scan.dart`, `scanner_scans.dart`
- Test: `test/features/discovery/domain/radio_scan_test.dart`

**Interfaces:**
- Consumes: Task A3's types.
- Produces:

```dart
sealed class RadioPhase {}     // RadioQuiet, RadioScanning(ScanCoverage coverage), RadioStopping, RadioUnsure

sealed class RadioScanInput {}
// ScannerOpened(ScannerId scanner), ScannerDisposed(ScannerId scanner),
// ScanAsked(ScannerId scanner, ScanId id, ScanAsk ask), ScanLeft(ScanId id, ScanEnd end),
// RadioStopped(), RadioStopFailed(ScanFailure failure), RadioRefused(ScanFailure failure),
// RadioWentAway(RadioOutage outage), ResultHeard(ScanResult result), ShutDown()

sealed class RadioDuty {}      // ScanFor(ScanCoverage coverage), StopTheRadio  (value equality)

final class RadioScanStep {
  RadioScanStep(this.scan, {this.events = const [], this.duty});
  final RadioScan scan;
  final List<ScanEvent> events;   // ScanEvent arrives in A5; until then an empty list of Never
  final RadioDuty? duty;
}

final class RadioScan {
  /// No scanner, no scan, the radio quiet.
  const RadioScan.quiet();
  RadioPhase get radio;
  ScanPhase? phaseOf(ScanId scan);          // null for a scan never asked
  ScannerPhase? standingOf(ScannerId scanner);
  RadioScanStep on(RadioScanInput input, {required DateTime at});
}
```

  `RadioScan` is immutable: `on` answers the next one, as `Link.on` does. `ScannerScans` (in `scanner_scans.dart`) is the entity it holds per `ScannerId`: the scanner's scans in the order asked, each with its ask and phase.

- [ ] **Step 1: Failing tests, as the design's table.** One `group` per input, one test per radio phase, each asserting the next radio phase, each named scan's phase and the duty. Every cell of the table in §6.3 is a test, including the cells that do nothing and these the prose adds:
  - `ScanAsked` in `RadioQuiet` and in `RadioUnsure`: the scan is `Served`, radio `RadioScanning(coverage of the ask)`, duty `ScanFor` of the same.
  - `ScanAsked` in `RadioScanning(c)`: covered gives no duty and the same coverage; not covered (a new service, a busier mode) gives `ScanFor(c.widenedBy(ask))`.
  - `ScanAsked` in `RadioStopping`: `Waiting`, no duty.
  - `ScanLeft` of one of two scans: `Ended(end)`, no duty, coverage unchanged (not narrowed). Of the last: `Leaving(end)`, `RadioStopping`, `StopTheRadio`. Of a `Waiting` scan in `RadioStopping`: `Ended(end)`, no duty. Of a scan already `Leaving` or `Ended`, or unknown: nothing.
  - `RadioStopped` in `RadioStopping`: `Leaving` scans are `Ended` with their own end; with scans `Waiting` they become `Served`, radio `RadioScanning(their union)`, duty `ScanFor`; with none, `RadioQuiet`. In any other phase: a `StateError`.
  - `RadioStopFailed` in `RadioStopping`: as `RadioStopped` when scans wait; otherwise `RadioUnsure`, and the leaver's end is still the one it left with. In any other phase: a `StateError`.
  - `RadioRefused(f)` in `RadioScanning`: every open scan `Ended(EndedByFailure(f))`, `RadioQuiet`, no duty. In `RadioQuiet`, `RadioUnsure`, `RadioStopping`: nothing.
  - `RadioWentAway(o)`: in `RadioScanning`, every scan `Ended(EndedByRadioOutage(o))` and `RadioQuiet`; in `RadioStopping`, `Waiting` and `Leaving` scans alike are `Ended(EndedByRadioOutage(o))` and the radio stays `RadioStopping`, then `RadioStopped` (or `RadioStopFailed`) gives `RadioQuiet`; in `RadioUnsure`, `RadioQuiet`.
  - `ShutDown`: from `RadioScanning`, every scan `Ended(EndedOnRequest)`, `RadioStopping`, `StopTheRadio`; from `RadioUnsure`, `RadioStopping` and `StopTheRadio`; from `RadioStopping`, waiting scans `Ended(EndedOnRequest)` and no duty; from `RadioQuiet`, nothing.
  - Review focus 1: a sequence test, `ScanAsked, ScanLeft, ScanAsked, RadioStopped` repeated 1000 times, counts exactly one `StopTheRadio` and one `ScanFor` per round after the first and ends in `RadioScanning` with one `Served` scan.
- [ ] **Step 2:** Run `cd bluey && flutter test test/features/discovery/domain/radio_scan_test.dart`: fails to compile, then fails.
- [ ] **Step 3:** Implement `RadioScan.on` as one `switch` over `(radio, input)` with no default, each arm a small named private function, so a missing cell does not compile. Keep `radio_scan.dart` under 300 lines by holding the per-scanner bookkeeping in `ScannerScans`.
- [ ] **Step 4:** Green; run the domain coverage gate. Commit `feat(discovery): one radio scan decides what the radio does for every scan`.

## Task A5: Scanners, their events, and which scans a result goes to

Design §6.3: the three inputs after the table, the routing rules, `ScannerPhase`'s terminal values.

**Files:**
- Create: `features/discovery/domain/scan_event.dart`
- Modify: `radio_scan.dart`, `scanner_scans.dart`, `radio_scan_input.dart`
- Test: `test/features/discovery/domain/radio_scan_scanners_test.dart`, `radio_scan_routing_test.dart`

**Interfaces:**
- Produces:

```dart
sealed class ScanEvent { DateTime get at; }
// ScannerBeganStarting(ScannerId scanner, ScanAsk ask, DateTime at)
// ScannerStarted(ScannerId scanner, ScanAsk ask, DateTime at)
// ScannerBeganStopping(ScannerId scanner, DateTime at)
// ScannerStopped(ScannerId scanner, ScanEnd end, DateTime at)
// ScanEnded(ScanId scan, ScanEnd end, DateTime at)
// ResultDelivered(ScanResult result, Set<ScanId> scans, DateTime at)
```

  `ScanEnded` is added to the design's list: it is how a handle learns that its one scan ended and why, when the scanner as a whole has not changed standing (one of two scans of a scanner timing out). The edge publishes nothing for it.
  The `ask` a scanner event names is the ask of that scanner's most recently asked scan that is not ended.

- [ ] **Step 1: Failing tests for scanners.**
  - `ScannerOpened` adds a scanner standing `ScannerIdle`; opening it twice is a `StateError`.
  - `ScanAsked` from a scanner never opened, from a `ScannerLost` one and from a `ScannerClosed` one is a `StateError` (the handle refuses first; this is the invariant behind it).
  - A first ask on a quiet radio raises `ScannerBeganStarting` then `ScannerStarted` in one step, both carrying the ask and `at`.
  - An ask in `RadioStopping` raises `ScannerBeganStarting` only; the later `RadioStopped` raises `ScannerStarted`.
  - The last scan leaving raises `ScannerBeganStopping` and `ScanEnded` is not raised until `RadioStopped`, which raises `ScanEnded(end)` then `ScannerStopped(end)`.
  - One of two scans of one scanner leaving raises `ScanEnded` and no scanner event; one of two scanners' only scan leaving while the other stays raises `ScanEnded` and `ScannerStopped(end)` for the leaver with no `ScannerBeganStopping` (the radio does not stop for it).
  - `RadioRefused(f)` raises, for each scanner with an open scan, `ScanEnded` per scan then `ScannerStopped(EndedByFailure(f))`.
  - `RadioWentAway(o)` leaves every scanner, with or without scans, `ScannerLost(o)`; scanners that had scans raise `ScanEnded` per scan then `ScannerStopped(EndedByRadioOutage(o))`; an idle one raises nothing.
  - `ScannerDisposed` makes each of the scanner's scans leave with `EndedOnRequest` exactly as `ScanLeft` would (the last leaver stops the radio: M5), and leaves it `ScannerClosed`; a later `RadioStopped` still ends its leaving scan.
  - Events within one scanner come in the order began starting, started, began stopping, stopped; across scanners in the order the scanners were opened.
- [ ] **Step 2: Failing tests for routing** (`ResultHeard` answers `ResultDelivered(result, scans)` or no event, never a duty, never a phase change):
  - Rule 1: an `Everything` scan gets every result.
  - Rule 2: a `{a}` scan gets a result showing `a`, and with coverage `Everything` (an unfiltered scan is also open) does not get one showing only `b` or nothing.
  - Rule 3: with coverage `{a, b}` (two filtered scans, no unfiltered one) a result showing neither `a` nor `b` goes to both; a result showing `a` goes only to the `{a}` scan.
  - `Waiting`, `Leaving` and `Ended` scans get nothing; with no `Served` scan there is no event.
- [ ] **Step 3:** Implement: after computing the next state, compare each scanner's `ScannerPhase` before and after and raise the scanner events for the difference; raise `ScanEnded` for each scan that became `Ended` in the step.
- [ ] **Step 4:** Green; domain coverage gate. Commit `feat(discovery): the radio scan raises its scanners' events and routes results`.

## Task A6: The `Scanning` port, its double and its contract

Design §6.4.

**Files:**
- Create: `features/discovery/application/ports/scanning.dart`, `ports/scan_events.dart`
- Create: `test/fixtures/features/discovery/application/ports/in_memory_scanning.dart`, `scanning_contract.dart`, `recording_scan_events.dart`
- Test: `test/fixtures/features/discovery/application/ports/in_memory_scanning_test.dart` (runs the contract over the double)

**Interfaces:**
- Produces:

```dart
abstract interface class Scanning {
  void scan(ScanCoverage coverage);
  Future<Either<ScanFailure, void>> stop();
  Stream<ScanReport> get reports;        // single listener, no errors
  Stream<RadioOutage> get outages;
}
sealed class ScanReport {}               // Heard(ScanResult result), Refused(ScanFailure failure)

abstract interface class ScanEvents { void raise(ScanEvent event); }

abstract class ScanningHarness {
  Scanning get scanning;
  void hear(ScanResult result);                 // the radio hears a device
  void refuse(ScanRefusalReason reason);        // the radio refuses the running scan
  void failNextStop();
  void holdNextStop();  void releaseStop();     // a stop that settles when told
  void outage(RadioOutage outage);
  ScanCoverage? get scanningFor;                // null when the radio is not scanning
}
void scanningContract(String name, ScanningHarness Function() create);

class InMemoryScanning implements Scanning, ScanningHarness {
  int get scansAsked;  int get stopsAsked;  List<ScanCoverage> get coverages;
}
class RecordingScanEvents implements ScanEvents { List<ScanEvent> get raised; }
```

- [ ] **Step 1: Write the contract** (it is the failing test): a result heard after `scan` arrives as `Heard`; nothing is heard before a `scan` or after a `stop`; a second `scan` replaces the first (`scanningFor` is the second coverage, and results keep arriving on the same `reports` stream); `stop` answers `Right` and leaves `scanningFor` null; a failed stop answers `Left` and a held stop does not answer until released; `refuse` arrives as `Refused(ScanRefused(reason))` and leaves the radio not scanning; `reports` never carries an error; `outage` arrives on `outages`; `stop` with nothing scanning answers `Right`.
- [ ] **Step 2:** Implement `InMemoryScanning` to pass it. Commit `feat(discovery): the Scanning port, its double and its contract`.

## Task A7: The session and its two handles

Design §6.4.

**Files:**
- Create: `features/discovery/application/radio_scan_session.dart`, `open_scanner.dart`, `open_scan.dart`
- Test: `test/features/discovery/application/radio_scan_session_test.dart`, `open_scanner_test.dart`, `open_scan_test.dart`

**Interfaces:**
- Consumes: `Scanning`, `ScanEvents`, `RadioScan`, `Now` (`shared/application/now.dart`), `Log` (`shared/application/log.dart`).
- Produces:

```dart
final class RadioScanSession {
  RadioScanSession({required Scanning scanning, required ScanEvents events, required Log log, required Now now});
  OpenScanner openScanner();
  Future<void> dispose();     // feeds ShutDown, awaits the stop it caused, cancels its listeners
}

final class OpenScanner {
  ScannerPhase get phase;
  Stream<ScannerPhase> get phases;          // broadcast, distinct values, closed on close()
  /// Left(ScannerUnusable(phase)) from a lost or closed scanner.
  Either<ScannerUnusable, OpenScan> scan(ScanAsk ask);
  /// Every scan of this scanner leaves; answers when the radio stop that caused, if any, settled.
  Future<Either<ScanFailure, void>> stop();
  Future<void> close();
}
final class ScannerUnusable implements Failure { final ScannerPhase phase; }

final class OpenScan {
  Stream<ScanResult> get results;           // single listener, no errors, closes when the scan ends
  Future<ScanEnd> get ended;
  void leave();                             // EndedOnRequest; idempotent
}
```

  The session mints `ScannerId` and `ScanId` from counters, reads `now()` once per input, feeds one input at a time (an input raised while a step's duty is being started is queued, never fed re-entrantly), runs `ScanFor` by calling `scanning.scan` and `StopTheRadio` by calling `scanning.stop()` and feeding `RadioStopped` or `RadioStopFailed`, hands each `ResultDelivered` to the `OpenScan`s it names, passes every event to `ScanEvents`, and logs a failed stop at warn under context `bluey`. `OpenScan` starts its timer from `ask.timeLimit` when it is asked and leaves with `EndedByTimeout` when it fires; the timer is cancelled when the scan ends for any reason.

- [ ] **Step 1: Failing tests** over `InMemoryScanning` and `RecordingScanEvents`, in `fakeAsync`:
  - One scanner, one scan: `scansAsked == 1`, results flow, `leave()` stops the radio, `ended` completes with `EndedOnRequest`, the events are began starting, started, began stopping, stopped, each stamped with the injected instant.
  - Two scanners with `{a}` and `{b}`: the radio is asked for `{a}` then `{a, b}`; each gets only its own results; stopping one leaves `stopsAsked == 0` and the other still delivering.
  - M4: `stop()` not awaited then `scan()`: with the stop held, the second scan's `phase` is `ScannerStarting`; releasing the stop gives `ScannerScanning`, `scansAsked == 2`, and a heard result arrives on the second scan.
  - M5: `close()` of the only scanner while scanning asks the radio to stop once.
  - Timeout: a scan with `timeLimit` 5 s ends with `EndedByTimeout` at exactly 5 s of simulated time; a second scan of another scanner with no limit keeps delivering and the radio is not stopped.
  - A refusal: both open scans end with `EndedByFailure(ScanRefused(reason))`, their `results` close without an error event, and a new `scan()` afterwards asks the radio again.
  - A failed stop: `stop()` answers `Left(failure)`, the scan's `ended` is still `EndedOnRequest`, a warn line is logged, and the next ask calls `scanning.scan` again.
  - An outage: every `OpenScanner`, idle ones included, shows `ScannerLost(outage)`, `scan()` answers `Left(ScannerUnusable)`, and `scanning.stop` is not called.
  - `dispose()` while scanning stops the radio once and ends every scan with `EndedOnRequest`; `dispose()` when quiet calls nothing; `dispose()` after a failed stop asks the radio to stop again.
  - Review focus 1: `stop()`/`scan()` in the same turn 1000 times with stops answered in order ends with one `Served` scan, `stopsAsked == 1000`, `scansAsked == 1001`.
  - Review focus 2: cancelling the listener of a `Waiting` scan (radio stopping) ends it, and the settling stop then leaves the radio quiet with `scansAsked` unchanged; a `timeLimit` firing while the radio is stopping for that same scan changes nothing and leaks no timer (`fakeAsync`'s `pendingTimers` is empty at the end).
- [ ] **Step 2:** Implement the three units. `OpenScanner` and `OpenScan` hold streams and a timer only; every decision is a `RadioScan` step.
- [ ] **Step 3:** Green; `flutter analyze`; architecture test (no `package:clock`, no platform import). Commit `feat(discovery): a session runs the radio scan for every scanner`.

## Task A8: A refused scan reaches Dart (I013, the platform seam)

Design §6.4, "The platform seam for I013". Closes M2.

**Files:**
- Modify: `bluey_platform_interface/lib/src/…` (the file that declares the platform exceptions), its test
- Modify: `bluey_android/pigeons/messages.dart`, the regenerated `lib/src/messages.g.dart` and `Messages.g.kt`, `bluey_android/lib/src/android_scanner.dart`, the file that implements `BlueyFlutterApi` and forwards `onScanComplete`, `android/src/main/kotlin/**/Scanner.kt` and its JVM test
- Modify: `bluey_ios/lib/src/ios_scanner.dart`
- Modify: `bluey/test/fakes/fake_platform.dart`
- Modify: `bluey_android/test/known_defects/roster.dart` and `android_adapter_known_defects_test.dart` (the M2 test moves to `android_scanner_test.dart`)
- Test: `bluey_android/test/android_scanner_test.dart`, `bluey_ios/test/ios_scanner_test.dart`, `bluey/test/fakes/fake_platform_test.dart`

**Interfaces:**
- Produces:

```dart
// bluey_platform_interface
enum PlatformScanFailureReason { alreadyStarted, registrationFailed, internalError, unsupported, outOfHardwareResources, startedTooOften, unknown }
class PlatformScanFailedException implements Exception {
  const PlatformScanFailedException(this.reason, {this.code});
  final PlatformScanFailureReason reason;
  final int? code;
}
```

  Pigeon (Android `BlueyFlutterApi`): `void onScanFailed(int errorCode);`. Android codes 1 to 6 map, in order, to `alreadyStarted`, `registrationFailed`, `internalError`, `unsupported`, `outOfHardwareResources`, `startedTooOften`; any other code to `unknown` with the code kept.
  `FakeBlueyPlatform.simulateScanRefusal(PlatformScanFailureReason reason)`: the running scan's stream carries `PlatformScanFailedException(reason)` and the fake stops scanning. The existing `simulateScanFailure(Object)` stays.
  `BlueyPlatform.scan(config)` keeps its signature.

- [ ] **Step 1: Failing tests (Android Dart).** Move the M2 roster test into `android_scanner_test.dart` as a regular test: a `startScan` whose future rejects with a `PlatformException` puts that error on the stream `scan` returned and raises no unhandled async error. Add: `onScanFailed(2)` puts `PlatformScanFailedException(registrationFailed, code: 2)` on the stream; `onScanFailed(99)` gives `unknown` with `code: 99`; a rejection of a `startScan` that a later `scan` superseded is dropped; one that a later `stopScan` superseded is dropped (review focus 4).
- [ ] **Step 2:** Add the exception to the platform interface (test first there: equality-free, `toString` names the reason). Add the Pigeon callback and regenerate (`cd bluey_android && dart run pigeon --input pigeons/messages.dart`). In `AndroidScanner.scan`, keep a generation counter: handle `startScan`'s future, and add its error to the stream only if no later `scan` or `stopScan` raised the counter. Implement `onScanFailed`. Strike the M2 entry from `bluey_android/test/known_defects/roster.dart`.
- [ ] **Step 3: Kotlin.** In `Scanner.kt`'s `onScanFailed(errorCode)`, call the new `flutterApi.onScanFailed(errorCode.toLong())` where it called `onScanComplete`. Update the JVM test that pinned the old call, or add one, asserting the code is forwarded. It cannot run in the cloud: mark the task's ledger row "Kotlin: awaiting Joel's Gradle run" and list the command (`cd bluey_android/android && FLUTTER_ROOT=… ./gradlew test`) in the pull request description.
- [ ] **Step 4: iOS Dart, test first.** A rejected `startScan` (Swift's `notReady` arrives as the error `translatePlatformException`-style mapping already turns into `PlatformBluetoothUnavailableException` for other calls; re-read `ios_scanner.dart` and the iOS adapter's error mapping and use the same function) puts `PlatformBluetoothUnavailableException` on the stream; a superseded rejection is dropped. Implement with the same generation counter.
- [ ] **Step 5: The fake, test first.** `simulateScanRefusal` as specified. Run all three packages' suites and architecture tests. Commit `fix(android,ios): a refused scan is an error on the scan stream`.

## Task A9: `PlatformScanning` answers the port

Design §6.4.

**Files:**
- Create: `features/discovery/infrastructure/adapters/platform_scanning.dart`, `platform_scan_failures.dart`
- Test: `test/features/discovery/infrastructure/adapters/platform_scanning_test.dart` (runs `scanningContract` with a harness over `FakeBlueyPlatform`, plus the mapping tests), `platform_scan_failures_test.dart`

**Interfaces:**
- Consumes: `Scanning`, `platformErrorOf`, `radioOutagesOf`, `uuidFrom`, `PlatformScanFailedException`.
- Produces:

```dart
final class PlatformScanning implements Scanning {
  PlatformScanning(BlueyPlatform platform, {required Log log});
}
ScanFailure scanFailureFrom(Object error);
```

  `scanFailureFrom`: `PlatformScanFailedException(reason)` to `ScanRefused` (reasons map one to one by name), then `switch (platformErrorOf(error))` with no default: `PermissionDenied` to `ScanPermissionMissing`, `RadioUnavailable` to `ScanRadioUnavailable`, `Unexpected` to `UnexpectedScanFailure`.
  `scan(coverage)` calls `platform.scan(PlatformScanConfig(serviceUuids: …, scanMode: …))` with `timeoutMs` always null, cancels its listener on the previous platform stream, and forwards the new one into `reports`: a device as `Heard`, a stream error as `Refused(scanFailureFrom(error))`. `stop()` awaits `platform.stopScan()` and answers what it threw as `Left(scanFailureFrom(error))`. Service UUIDs go to the platform as `toString()`; `Everything` is an empty list.

- [ ] **Step 1: Failing tests.** The contract over the fake (the harness uses `simulatePeripheral`-style seams the fake already has for `hear`, `simulateScanRefusal` for `refuse`, the fake's fault rules for `failNextStop` and `holdNextStop`, and the state seam for `outage`). Mapping: `lastScanConfig.timeoutMs` is null for every coverage; each `ScanMode` maps to its `PlatformScanMode` and an absent one to null; a `PlatformDevice` becomes a `ScanResult` with the same address, name, RSSI, services and manufacturer data as `BlueyScanner._mapScanResult` produces today. Review focus 3: a device with a malformed service UUID, and one with manufacturer bytes but no company id, are dropped with one warn line each and the next device is still `Heard`; `reports` carries no error.
- [ ] **Step 2:** Implement. Parsing goes through `uuidFrom`; the mapping function answers `Either` and the adapter logs the `Left`.
- [ ] **Step 3:** Green, including `in_memory_scanning_test.dart` unchanged. Commit `feat(discovery): PlatformScanning answers the Scanning port`.

## Task A10: Discovery's edge, and `Bluey` hands out scanners from it

Design §6.5. Closes M4 (both entries) and M5, and makes a refused scan a `ScanFailedException`.

**Files:**
- Move: `lib/src/discovery/scanner.dart` to `api/discovery/scanner.dart`; `discovery/scan_state.dart` to `api/discovery/scan_state.dart`; the five scan events out of `lib/src/events.dart` into `api/discovery/scan_events.dart`
- Create in `api/discovery/`: `scan_state_translation.dart`, `scan_event_translation.dart`, `scan_failure_translation.dart`, `scan_failed_exception.dart`, `published_scanner.dart` (the implementation of `Scanner`), `discovery_assembly.dart`
- Delete: `lib/src/discovery/bluey_scanner.dart` and the folder
- Modify: `lib/src/bluey.dart`, `lib/bluey.dart`, `known_violations.dart` (`unplaced`, `boundaries`, `frameworkPlacement` and `oversized` entries of `discovery/` leave; `events.dart`'s `oversized` entry is lowered), `test/known_defects/roster.dart` and `domain_known_defects_test.dart` (the M4 and M5 tests move), `bluey/api/bluey.api`
- Test: `test/api/discovery/` (one per file), the existing `test/discovery/*`, `test/scanner_test.dart`, `test/scan_test.dart` moved under `test/api/discovery/` and passing through the edge

**Interfaces:**
- Consumes: `RadioScanSession`, `OpenScanner`, `OpenScan`, `Scanning`, `EventPublisher`, `Log`, `Now`.
- Produces:

```dart
// scan_failed_exception.dart  (public, exported from lib/bluey.dart)
enum ScanFailureReason { alreadyStarted, registrationFailed, internalError, unsupported, outOfHardwareResources, startedTooOften, unknown }
final class ScanFailedException extends BlueyPlatformException {
  ScanFailedException(this.reason);          // message: 'The scan was refused: <reason name>'
  final ScanFailureReason reason;
}

ScanState scanStateOf(ScannerPhase phase);                    // scan_state_translation.dart
BlueyException scanFailureAsException(ScanFailure failure);   // scan_failure_translation.dart
final class PublishedScanEvents implements ScanEvents { PublishedScanEvents(EventPublisher publisher); }

final class DiscoveryAssembly {
  DiscoveryAssembly({required Scanning scanning, required EventPublisher publisher, required Log log, required Now now});
  Scanner scanner();
  Stream<DeviceAddress> devicesAdvertising(UUID service);    // Task A11 fills this in; declared here
  Future<void> dispose();
}
```

  Translations, each a `switch` with no default:
  - `scanStateOf`: `ScannerIdle` and `ScannerClosed` to `stopped`; `ScannerStarting` to `starting`; `ScannerScanning` to `scanning`; `ScannerStopping` to `stopping`; `ScannerLost` to `invalidated`.
  - `scanFailureAsException`: `ScanRefused(reason)` to `ScanFailedException` (reasons map by name); `ScanPermissionMissing(p)` to `PermissionDeniedException`; `ScanRadioUnavailable` to `BluetoothUnavailableException`; `UnexpectedScanFailure` to `BlueyPlatformException` with the detail, code and cause. Check each constructor's shape against `shared/exceptions.dart` before writing the test.
  - `PublishedScanEvents`: `ScannerBeganStarting` to `ScanStartingEvent(serviceFilter, timeout, source: 'BlueyScanner', timestamp: at)`; `ScannerStarted` to `ScanStartedEvent` likewise; `ScannerBeganStopping` to `ScanStoppingEvent`; `ScannerStopped` to `ScanStoppedEvent(source: 'BlueyScanner', timestamp: at)` with `reason` left null as today, except that a stop whose end is `EndedByRadioOutage` publishes nothing, as today's invalidation publishes nothing; `ResultDelivered` to one `DeviceDiscoveredEvent(deviceAddress, name, rssi, timestamp: at)` with no source, as today; `ScanEnded` publishes nothing. `serviceFilter` is null for `Everything` and the services as a list for `ServicesOnly`.
  - The five event classes gain `super.timestamp` in their constructors.
  - `published_scanner.dart`: `scan({services, timeout, mode})` builds `ScanAsk(filter: ScanFilter.of(services), mode: mode, timeLimit: timeout)`; a `Left(ScannerUnusable)` throws the `StaleHandleException` `BlueyScanner._ensureValid` throws today, with the same fields; the returned stream is single-subscription, carries the scan's results, and when the scan ends with `EndedByFailure(f)` carries `scanFailureAsException(f)` as its one error before closing; cancelling the subscription calls `leave()`. `stop()` awaits `OpenScanner.stop()` and throws a `Left` translated. `state`, `stateChanges` (replaying the current state to a new listener if it does today; read `BlueyScanner` and the state-machine test first) and `isScanning` read the `OpenScanner`. `dispose()` closes it.

- [ ] **Step 1: Failing tests for the translations and the exception** (one test per arm; `ScanFailedException` is a `BlueyPlatformException` and a `BlueyException`, and an exhaustive `switch` over `BlueyException` written before this change still compiles).
- [ ] **Step 2:** Move the public files and the five events; implement the translations. Lower `events.dart`'s `oversized` entry.
- [ ] **Step 3: Failing edge tests** through `DiscoveryAssembly` over `PlatformScanning` on `FakeBlueyPlatform`: move the three roster tests (two M4, one M5) into `test/api/discovery/published_scanner_test.dart` as regular tests and strike their entries; add two scanners with different filters each getting its own results; a refused scan (`simulateScanRefusal(registrationFailed)`) delivering `ScanFailedException(registrationFailed)` then done, the state back at `stopped`, and a second `scan()` working; a timeout ending the stream at the exact instant; the event order of a single caller unchanged from today; each event's `timestamp` equal to the injected clock's instant.
- [ ] **Step 4:** Implement `PublishedScanner` and `DiscoveryAssembly`. In `lib/src/bluey.dart`: add `late final DiscoveryAssembly _discovery = DiscoveryAssembly(scanning: PlatformScanning(_platform, log: _logger), publisher: _eventBus, log: _logger, now: clock.now)` beside `_connection`, make `scanner()` answer `_discovery.scanner()`, and dispose it in `dispose()` before the event bus closes. Delete `lib/src/discovery/`. `wc -l lib/src/bluey.dart` is at most 974; if it is over, move wiring into the assembly, never raise the entry.
- [ ] **Step 5:** Run the moved legacy scanner tests. A test that asserted `lastScanConfig.timeoutMs` now asserts null and that the stream ended at the timeout; a test that asserted an old defect's behaviour is rewritten to the design's §7 item it corresponds to, and the ledger names each rewritten test with its item. No other expectation changes.
- [ ] **Step 6:** `dart run bluey_guards:public_api lib/bluey.dart api/bluey.api --write`; the diff holds only `ScanFailedException`, `ScanFailureReason`, five `timestamp` parameters and moved paths. Run every `bluey` gate. Commit `feat(discovery): scanners share one radio scan through Discovery's edge`.

## Task A11: Peer discovery scans through Discovery

Design §6.6.

**Files:**
- Modify: `lib/src/peer/peer_discovery.dart`, `lib/src/bluey.dart`, `api/discovery/discovery_assembly.dart`, `known_violations.dart` (the `frameworkPlacement` entry of `peer_discovery.dart` leaves; its `oversized` entry, if any, is lowered)
- Test: `test/api/discovery/discovery_assembly_test.dart`, the existing `test/peer/` discovery tests, `test/integration/` (one new scenario)

**Interfaces:**
- Produces, declared in `peer_discovery.dart`:

```dart
/// Devices heard advertising [service], until the listener cancels.
typedef DevicesAdvertising = Stream<DeviceAddress> Function(UUID service);
```

  `PeerDiscovery`'s constructor takes `required DevicesAdvertising devicesAdvertising` in place of its use of the platform for scanning; it keeps whatever else it is handed today. `DiscoveryAssembly.devicesAdvertising(service)`: on listen, opens a scanner and one scan with `ScanAsk(filter: ScanFilter.of([service]))` (no mode, no time limit) and emits each result's `device.address`; on cancel, leaves the scan and closes the scanner; a scan that ends by failure adds the translated exception and closes; one that ends by outage closes.

- [ ] **Step 1: Failing tests.** Assembly: listening opens one scanner and asks the radio for `{service}` with a null mode; cancelling stops the radio when no other scan is open; two listens are two scanners; after an outage a new listen works. Integration, over the fake: `discoverPeers()` while the app scans unfiltered leaves the app's scan delivering during and after, the app's `ScanState` never leaving `scanning`, and `stopScan` not called by peer discovery; an app scan filtered to another service still lets `discoverPeers()` find a peer advertising the control service.
- [ ] **Step 2:** Replace the two `_platform.scan` sites (lines 102 and 183) with listens to `_devicesAdvertising(controlService)` keyed on `DeviceAddress`, and delete `_stopScan` (line 222) and its calls: cancelling the subscription is the stop. The window timers stay as they are. Remove the platform-interface import if scanning was its last use, and the `frameworkPlacement` entry with it.
- [ ] **Step 3:** In `bluey.dart`, pass `devicesAdvertising: _discovery.devicesAdvertising`. Line count at most 974.
- [ ] **Step 4:** Existing peer tests green; any that asserted `lastScanConfig` of the probe's scan asserts the coverage instead, named in the ledger. Commit `feat(peer): peer discovery scans through Discovery`.

## Task A12: Documents and pull request 1

**Files:** `docs/ARCHITECTURE.md` (the list counts of §5, Discovery in §3's layout, the translator paragraph of §6 naming Discovery's), `CLAUDE.md` (Architecture section: Discovery's edge; the glossary rows Radio scan, Scan, Ask, Coverage, Scanner (inner)), `bluey/docs/cross-platform-quirks.md` (the two limits of the design's §7 item 12), `bluey/CHANGELOG.md` (the design's §7 items 1 to 6, 11 and 12), `docs/backlog/` entries I013, I336, I382 and `docs/roadmap.md` (through the repository's `roadmap` skill conventions), `bluey/example` only if an import broke.

- [ ] Write the documents; every claim that names a class is checked against its source.
- [ ] Run every cloud gate; record the numbers against the A0 baseline (no list longer, coverage at or above both floors).
- [ ] Open the pull request from `claude/project-thread-30zhyu`, mirroring the repository's template. Its description lists: what an app sees (the design's §7), the findings closed, the Kotlin Gradle run and the device checks that need Joel (two scanners at once; `discoverPeers()` during a scan; a refused scan if one can be provoked), and the calls of the design's §11 that land here.

---

# Part B: Advertising (pull request 2)

## Task B0: Pre-flight

- [ ] After pull request 1 merges, restart `claude/project-thread-30zhyu` from `origin/main`; record the baseline as in A0 in the same ledger.

## Task B1: What a server asks to advertise

Design §6.1, §6.7, §6.8.

**Files:**
- Create in `features/gatt_server/domain/`: `advertised_content.dart`, `advertising_ask.dart`, `advertise_mode.dart` (the enum cut out of `lib/src/gatt_server/server.dart`), `advertising_phase.dart`, `advertising_event.dart`, `advertising_failure.dart`
- Create: `api/gatt_server/advertising.dart` exporting `advertise_mode.dart`
- Modify: `gatt_server/server.dart` (imports the enum), `lib/bluey.dart` (exports `src/api/gatt_server/advertising.dart`)
- Test: one per created domain file

**Interfaces:**
- Produces:

```dart
final class AdvertisedContent {
  /// [supplementaryServices] never repeats a listed service: a repeated one is dropped here.
  factory AdvertisedContent({String? name, Iterable<UUID> services, Iterable<UUID> supplementaryServices, ManufacturerData? manufacturerData});
  final String? name;
  final List<UUID> services;                // in the order given, duplicates dropped
  final Set<UUID> supplementaryServices;
  final ManufacturerData? manufacturerData;
}
final class AdvertisingAsk {
  const AdvertisingAsk({required this.content, this.mode, this.timeLimit});
  /// Same content and mode; the time limit is not part of what is advertised.
  bool advertisesTheSameAs(AdvertisingAsk other);
}
sealed class AdvertisingPhase {}
// AdvertisingIdle, AdvertisingStarting(ask), AdvertisingOn(ask), AdvertisingStopping(ask, StopCause by), AdvertisingReplacing(old, next)
enum StopCause { request, timeLimit }
sealed class AdvertisingEnd {}    // EndedOnRequest, EndedByTimeout, EndedByFailure(AdvertisingFailure), EndedByRadioOutage(RadioOutage)
sealed class AdvertisingEvent { DateTime get at; }
// AdvertisingBeganStarting(at), AdvertisingStarted(AdvertisedContent content, at), AdvertisingBeganStopping(at), AdvertisingStopped(AdvertisingEnd end, at)
sealed class AdvertisingFailure implements Failure {}
// AdvertisingRefused(AdvertisingRefusalReason reason), AdvertisingPermissionMissing(String permission),
// AdvertisingRadioUnavailable(), UnexpectedAdvertisingFailure(String detail, {String? code, required Object cause})
enum AdvertisingRefusalReason { dataTooLarge, notSupported, unknown }
```

- [ ] **Step 1: Failing tests, as values:** a supplementary service that is also listed is dropped, in any letter case of the UUID's text; equality by value; `advertisesTheSameAs` is true across different time limits and false across a different name, service order, supplementary set, manufacturer data or mode.
- [ ] **Step 2:** Move the enum, implement, export. API dump shows a moved path only. Commit `feat(gatt-server): say what a server asks to advertise`.

## Task B2: `Advertising` decides what is advertised and when its time runs

Design §6.7.

**Files:**
- Create: `features/gatt_server/domain/advertising.dart`
- Test: `test/features/gatt_server/domain/advertising_test.dart`

**Interfaces:**
- Produces:

```dart
sealed class AdvertisingInput {}
// StartAsked(AdvertisingAsk ask), StopAsked(), TimeLimitReached(), RadioStarted(), RadioStartFailed(AdvertisingFailure failure),
// RadioStopped(), RadioStopFailed(AdvertisingFailure failure), RadioWentAway(RadioOutage outage)
sealed class AdvertisingDuty {}        // StartAdvertising(ask), StopAdvertising
sealed class TimeLimit {}              // KeepFor(Duration duration), KeepUnlimited  ("start or restart the limit" / "end any limit")
/// How the ask in flight ended, when a step ends one.
sealed class AskOutcome {}             // AskMet, AskFailed(AdvertisingFailure failure)

final class AdvertisingStep {
  final Advertising advertising;
  final List<AdvertisingEvent> events;
  final AdvertisingDuty? duty;
  final TimeLimit? timeLimit;           // null leaves the timer as it is
  final AskOutcome? outcome;            // null while an ask is still in flight, or when none is
}
final class Advertising {
  const Advertising.idle();
  AdvertisingPhase get phase;
  AdvertisingStep on(AdvertisingInput input, {required DateTime at});
}
```

- [ ] **Step 1: Failing tests, as the design's table**, one per row, asserting phase, duty, events, `timeLimit` and `outcome`:
  - `StartAsked(a)` in `AdvertisingIdle`: `AdvertisingStarting(a)`, `StartAdvertising(a)`, event began starting.
  - `RadioStarted` in `AdvertisingStarting(a)`: `AdvertisingOn(a)`, event started with `a.content`, `KeepFor(limit)` when `a` has one and `KeepUnlimited` when not, `AskMet`.
  - `RadioStartFailed(f)` in `AdvertisingStarting`: `AdvertisingIdle`, event stopped with `EndedByFailure(f)`, `KeepUnlimited`, `AskFailed(f)`.
  - `StartAsked(b)` in `AdvertisingOn(a)` where `b.advertisesTheSameAs(a)`: phase `AdvertisingOn(b)`, no duty, no event, `KeepFor`/`KeepUnlimited` from `b`, `AskMet`.
  - `StartAsked(b)` in `AdvertisingOn(a)`, different: `AdvertisingReplacing(a, b)`, `StopAdvertising`, event began stopping, `timeLimit` null (the old limit runs on until the radio stops).
  - `RadioStopped` in `AdvertisingReplacing(a, b)`: `AdvertisingStarting(b)`, `StartAdvertising(b)`, events stopped (`EndedOnRequest`) then began starting, `KeepUnlimited`, no outcome yet.
  - `RadioStopFailed(f)` in `AdvertisingReplacing(a, b)`: `AdvertisingOn(a)`, no duty, `timeLimit` null, `AskFailed(f)`, and the events that return the public state to advertising (started with `a.content`).
  - `StopAsked` in `AdvertisingOn(a)`: `AdvertisingStopping(a, request)`, `StopAdvertising`, began stopping. `TimeLimitReached` in `AdvertisingOn(a)`: `AdvertisingStopping(a, timeLimit)`, the same duty and event.
  - `RadioStopped` in `AdvertisingStopping(a, request)`: `AdvertisingIdle`, stopped (`EndedOnRequest`), `KeepUnlimited`, `AskMet`. In `AdvertisingStopping(a, timeLimit)`: stopped (`EndedByTimeout`), `KeepUnlimited`, no outcome.
  - `RadioStopFailed(f)` in `AdvertisingStopping(a, request)`: `AdvertisingOn(a)`, started event, `AskFailed(f)`, `timeLimit` null. In `AdvertisingStopping(a, timeLimit)`: `AdvertisingOn(a)`, started event, `KeepUnlimited` (the limit is not tried again), no outcome.
  - `StopAsked` in `AdvertisingIdle`: nothing, `AskMet`. `TimeLimitReached` in any phase but `AdvertisingOn`: nothing.
  - `RadioWentAway(o)`: in `AdvertisingIdle` nothing; in every other phase `AdvertisingIdle`, stopped (`EndedByRadioOutage(o)`), `KeepUnlimited`, and `AskFailed(AdvertisingRadioUnavailable())` when an ask was in flight (`Starting`, `Replacing`, `Stopping` by request).
  - `StartAsked` or `StopAsked` in `AdvertisingStarting`, `AdvertisingStopping` or `AdvertisingReplacing`, and a radio answer in a phase that asked for none: a `StateError`.
- [ ] **Step 2:** Implement as one `switch` over `(phase, input)` with no default.
- [ ] **Step 3:** Green; domain coverage gate. Commit `feat(gatt-server): one advertising aggregate decides what is advertised`.

## Task B3: The `Advertiser` port, its double and its contract

Design §6.8.

**Files:**
- Create: `features/gatt_server/application/ports/advertiser.dart`, `ports/advertising_events.dart`; `test/fixtures/features/gatt_server/application/ports/{in_memory_advertiser,advertiser_contract,recording_advertising_events}.dart`
- Test: `in_memory_advertiser_test.dart`

**Interfaces:**
- Produces:

```dart
abstract interface class Advertiser {
  Future<Either<AdvertisingFailure, void>> start(AdvertisingAsk ask);
  Future<Either<AdvertisingFailure, void>> stop();
  Stream<RadioOutage> get outages;
}
abstract interface class AdvertisingEvents { void raise(AdvertisingEvent event); }

abstract class AdvertiserHarness {
  Advertiser get advertiser;
  void failNextStart(AdvertisingRefusalReason reason);
  void failNextStop();
  void holdNextStart();  void releaseStart();
  void outage(RadioOutage outage);
  AdvertisedContent? get advertising;       // what the radio advertises, null when nothing
}
void advertiserContract(String name, AdvertiserHarness Function() create);
class InMemoryAdvertiser implements Advertiser, AdvertiserHarness { int get startsAsked; int get stopsAsked; }
```

- [ ] **Step 1: The contract:** `start` answers `Right` and `advertising` is the ask's content; a failed start answers `Left(AdvertisingRefused(reason))` and nothing is advertised; `stop` answers `Right` and nothing is advertised; a failed stop answers `Left` and the content is still advertised; `stop` while nothing is advertised answers `Right`; a held start does not answer until released; an outage arrives on `outages` and nothing is advertised after it. The contract does not call `start` while advertising: the session never does (replace is stop then start).
- [ ] **Step 2:** Implement the double. Commit `feat(gatt-server): the Advertiser port, its double and its contract`.

## Task B4: The advertising session

Design §6.8.

**Files:**
- Create: `features/gatt_server/application/advertising_session.dart`
- Test: `test/features/gatt_server/application/advertising_session_test.dart`

**Interfaces:**
- Produces:

```dart
final class AdvertisingSession {
  AdvertisingSession({required Advertiser advertiser, required AdvertisingEvents events, required Log log, required Now now});
  AdvertisingPhase get phase;
  Stream<AdvertisingPhase> get phases;                       // broadcast, distinct
  Future<Either<AdvertisingFailure, void>> start(AdvertisingAsk ask);
  Future<Either<AdvertisingFailure, void>> stop();
  Future<void> dispose();                                    // after queued asks, stops if advertising; cancels the timer and listeners
}
```

  Asks are served one at a time in the order made; each returned future completes with the `AskOutcome` of its own ask. The session holds one timer and does only what a step's `timeLimit` says. A time limit's failed stop is logged at error under `bluey.server`.

- [ ] **Step 1: Failing tests** over `InMemoryAdvertiser`, in `fakeAsync`:
  - Start then stop: `startsAsked == 1`, `stopsAsked == 1`, phases idle, starting, on, stopping, idle, the four events stamped with the injected instant.
  - L1: start `a`, then start `b` with the next start failing: `stopsAsked == 1`, the second `start` answers `Left`, the phase is `AdvertisingIdle` and `advertiser.advertising` is null; a later `stop()` answers `Right` and calls nothing.
  - Replace: start `a`, start `b`: the radio is stopped then started with `b`; phases pass replacing then starting then on.
  - The same ask again: no radio call; a 10 s limit asked at 0 s and again at 6 s stops at 16 s.
  - Time limit: `timeLimit` 5 s stops the radio at exactly 5 s, ends by `EndedByTimeout`, and no start call ever carried a timeout (the port has none to carry).
  - A failed stop: answers `Left`, phase `AdvertisingOn`; a time limit's failed stop logs one error line and a later `stop()` still works.
  - An outage while on: phase idle, the timer cancelled (`pendingTimers` empty); an outage while a start is held: that `start` answers `Left(AdvertisingRadioUnavailable)` and the released platform answer is ignored without a `StateError`.
  - Review focus 5: `start(a)` and `start(b)` in the same turn: both answer `Right`, the radio ends advertising `b`, in order start a, stop, start b. `stop()` made while a replace is in flight is served after it and leaves idle. `dispose()` while a start is held: after release the radio is stopped once and no timer is pending.
- [ ] **Step 2:** Implement with a simple queue of pending asks; a platform answer that arrives after an outage reset the aggregate is dropped by an ask generation counter, not fed.
- [ ] **Step 3:** Green. Commit `feat(gatt-server): one session serves every advertising ask in order`.

## Task B5: `PlatformAdvertiser` answers the port

Design §6.8, I320.

**Files:**
- Create: `features/gatt_server/infrastructure/adapters/platform_advertiser.dart`, `platform_advertising_failures.dart`
- Test: `test/features/gatt_server/infrastructure/adapters/platform_advertiser_test.dart` (the contract over `FakeBlueyPlatform`, and the mapping), `platform_advertising_failures_test.dart`

**Interfaces:**
- Produces: `final class PlatformAdvertiser implements Advertiser { PlatformAdvertiser(BlueyPlatform platform); }` and `AdvertisingFailure advertisingFailureFrom(Object error)`.
  Mapping to `PlatformAdvertiseConfig`: `name`; `serviceUuids` as lower-case text in order; `scanResponseServiceUuids` from `supplementaryServices`; `manufacturerDataCompanyId` and `manufacturerData`; `mode` by name; `timeoutMs` always null. `advertisingFailureFrom`: the platform's advertising exceptions first (re-read `bluey_platform_interface` for the exact set: `PlatformAdvertiseDataTooLargeException` to `dataTooLarge`, its not-supported one to `notSupported`), then `switch (platformErrorOf(error))` with no default.

- [ ] **Step 1: Failing tests:** the contract over the fake; `advertiseConfig` equals, field for field, the config `BlueyServer.startAdvertising` builds today for the same arguments, except `timeoutMs` is null; a peer-discoverable ask puts the control service in `scanResponseServiceUuids`; each failure arm.
- [ ] **Step 2:** Implement. Commit `feat(gatt-server): PlatformAdvertiser answers the Advertiser port`.

## Task B6: Advertising's edge, and `BlueyServer` asks the session

Design §6.8. Closes L1, the Dart half of M8, and I320.

**Files:**
- Move: the four advertising events out of `lib/src/events.dart` into `api/gatt_server/advertising_events.dart` (exported by `api/gatt_server/advertising.dart`)
- Create in `api/gatt_server/`: `advertising_event_translation.dart`, `advertising_state_translation.dart`, `advertising_failure_translation.dart`, `advertising_assembly.dart`
- Modify: `lib/src/gatt_server/bluey_server.dart`, `lib/src/bluey.dart`, `known_violations.dart` (lower `bluey_server.dart`'s and `events.dart`'s `oversized` entries), `test/known_defects/roster.dart` and `domain_known_defects_test.dart` (L1 moves), `bluey/api/bluey.api`
- Test: `test/api/gatt_server/` (one per file), the existing `test/gatt_server/advertising_*`, `bluey_server_advertising_order_test.dart`, `bluey_server_dispose_test.dart`, `test/bluey_server_test.dart`

**Interfaces:**
- Produces:

```dart
AdvertisingState advertisingStateOf(AdvertisingPhase phase);
BlueyException advertisingFailureAsException(AdvertisingFailure failure);
final class PublishedAdvertisingEvents implements AdvertisingEvents { PublishedAdvertisingEvents(EventPublisher publisher); }

final class AdvertisingAssembly {
  AdvertisingAssembly({required Advertiser advertiser, required EventPublisher publisher, required Log log, required Now now});
  AdvertisingSession get session;
  AdvertisingState Function(AdvertisingPhase) get stateOf;
  BlueyException Function(AdvertisingFailure) get failureAsException;
  Future<void> dispose();
}
```

  - `advertisingStateOf`: idle to `idle`, starting to `starting`, on to `advertising`, stopping and replacing to `stopping`.
  - `advertisingFailureAsException`: `AdvertisingRefused(dataTooLarge)` to `AdvertisingException(AdvertisingFailureReason.dataTooBig)`, the other reasons to their existing `AdvertisingFailureReason` members (check `shared/exceptions.dart` line 365 for the names), permission to `PermissionDeniedException`, radio to `BluetoothUnavailableException`, unexpected to `BlueyPlatformException`.
  - `PublishedAdvertisingEvents`: began starting to `AdvertisingStartingEvent(source: 'BlueyServer', timestamp: at)`; started to `AdvertisingStartedEvent(name: content.name, services: content.services, …)`; began stopping to `AdvertisingStoppingEvent`; stopped to `AdvertisingStoppedEvent`. Today the server publishes no stopped event when an outage invalidates it; read `_setAdvertisingState` (line 464 on) and keep exactly what it does for each end.
  - `BlueyServer` gains three constructor parameters: `required AdvertisingSession advertising`, `required AdvertisingState Function(AdvertisingPhase) advertisingStateOf`, `required BlueyException Function(AdvertisingFailure) advertisingFailureAsException`.

- [ ] **Step 1: Failing tests** for the three translations (one per arm), then move the events and implement. Lower `events.dart`'s entry.
- [ ] **Step 2: Failing server tests** through `Bluey` over the fake: move the L1 roster test into `test/gatt_server/advertising_state_machine_test.dart` and strike its entry; a second `startAdvertising` with other content replaces it and the state passes `stopping`, `starting`, `advertising`; the same content again touches no radio; a failed start throws `AdvertisingException(dataTooBig)` (not the platform's error) and leaves `idle`; a failed stop throws and leaves `advertising`; a 5 s timeout leaves `idle` at 5 s with the stopping and stopped events, and `advertiseConfig.timeoutMs` is null; two `Server` objects of one `Bluey` read the same state and the second's start replaces the first's content; `dispose()` of a server while advertising stops the radio.
- [ ] **Step 3:** In `BlueyServer`: `startAdvertising` keeps `_ensureValid`, its two log lines, the capability check, `_controlServiceReady` and the pending `addService` waits, then builds `AdvertisingAsk(content: AdvertisedContent(name, services, supplementaryServices: [control service when peerDiscoverable], manufacturerData), mode, timeLimit: timeout)`, awaits `advertising.start(ask)` and throws a `Left` translated. `stopAdvertising` awaits `advertising.stop()` likewise. `advertisingState`, `advertisingStateChanges` and `isAdvertising` read the session through `advertisingStateOf`, with the server's own `invalidated` taking precedence once it has seen an outage, as today. Delete `_advertisingState`'s field and setter, `_activeAdvertisingName`, `_activeAdvertisingServices`, `_mapAdvertiseModeToPlatform`, the config building and the four event emissions. Its own outage and disposal handling stays; disposal calls `advertising.stop()` and ignores a `Left` after logging it, as `dispose()` tolerates a failed stop today.
- [ ] **Step 4:** In `bluey.dart`: build `AdvertisingAssembly(advertiser: PlatformAdvertiser(_platform), …)` once, pass its three things where `BlueyServer(` is built (line ~860), dispose it in `dispose()`. At most 974 lines.
- [ ] **Step 5:** Existing server tests: one that asserted `advertiseConfig.timeoutMs` asserts null and the Dart-side timeout; one that asserted a defect's behaviour is rewritten to the design's §7 item (7 to 10, 13), each named in the ledger. Regenerate the API dump: four `timestamp` parameters and moved paths only. Every gate. Commit `feat(gatt-server): servers advertise through one session`.

## Task B7: Documents and pull request 2

**Files:** `docs/ARCHITECTURE.md` (counts, GATT Server's advertising in §3, the translator paragraph), `CLAUDE.md` (Bounded Contexts line for GATT Server, the glossary rows Advertising, Ask, Content, Supplementary services; the Architecture section's edge sentence), `bluey/CHANGELOG.md` (the design's §7 items 7 to 10 and 13), `docs/backlog/` I386, I385 (Dart half done, native half open for slice 4), I320, and `docs/roadmap.md`; the design gains a short addendum listing "Names refined" from this plan.

- [ ] Write the documents; run every cloud gate against the B0 baseline.
- [ ] Open pull request 2, with the device check that needs Joel (an advertising timeout on Android and on iOS; a second `startAdvertising` replacing the first) and the calls of the design's §11 that land here.

---

## Design review (cohesion, coupling, DDD, Clean Architecture)

**Single responsibilities.** Each task builds one unit or one seam, and each unit has the one responsibility the design's §12 gives it; the plan adds none that mixes a rule with a timer. `RadioScan` (A4, A5) holds every scanning rule, split over two tasks by concern (the radio, then scanners and routing) but one class. `RadioScanSession`, `OpenScanner` and `OpenScan` (A7) feed, show and time, and decide nothing: the tests of A7 assert only what the aggregate's steps already decided, through the port's counters. `Advertising` (B2) answers the time limit and each ask's outcome in its step, so `AdvertisingSession` (B4) has no branch on phase. The two adapters (A9, B5) map and log. Each edge file (A10, B6) translates one family. The two refinements that add a member (`ScanEnded`, `AskOutcome`) exist so that an application unit is told a fact instead of deriving it.

**Dependencies and their direction.** Domain tasks (A3 to A5, B1, B2) import `shared/domain` only. Application tasks (A6, A7, B3, B4) import their domain, their ports, `Now` and `Log`. Adapters (A9, B5) import their ports, `bluey_platform_interface` and `shared/infrastructure` (A2). The edge (A10, B6) imports its own context's features and the unplaced public types it must throw or return. The composition root alone builds `PlatformScanning` and `PlatformAdvertiser`. `PeerDiscovery` (A11) names kernel types and a typedef it declares; `BlueyServer` (B6) names its own context's `features/gatt_server` and is handed the edge's two translators. No task adds an import between `features/discovery`, `features/gatt_server` and `features/connection`; A2 removes the one thing Connection's adapter held that the others need.

**Bounded contexts and language.** Scanning's words (radio scan, scan, ask, coverage, end, scanner) are Discovery's and appear only under `features/discovery` and `api/discovery`. Advertising's (ask, content, supplementary services, end) are GATT Server's; "scan response" appears only in `PlatformAdvertiser`. The names this plan refines keep the design's words and only make them unambiguous in one Dart library. The kernel gains `UUID`, `ManufacturerData` and `RadioOutage`, each plain.

**Layers.** Every created file's path states its layer, in the design's §6.2 and this plan's File Structure. Exceptions and public events are declared only under `api/`. `uuidFrom` answers an `Either` and lives in `shared/domain` as a function, so the public `UUID` gains no internal type.

**Claims checked against source** (at the branch head, `main` 48cf097 plus the design):

- `Link.on(LinkInput, {required DateTime at})` answers a `LinkStep(link, events, duty)` and `Link` is immutable: `features/connection/domain/link.dart` lines 74 to 176. `RadioScan.on` and `Advertising.on` mirror it.
- `ConnectionAssembly` is handed `ports`, `publisher`, `log`, `now` by `bluey.dart` line 90 and builds `PublishedLinkEvents(publisher)` itself: `api/connection/connection_assembly.dart` lines 45 to 63. The two new assemblies take the same four kinds of thing.
- `connectionFailureFrom`'s last four arms are the permission, radio, `PlatformException` and catch-all ones, with the detail texts A2 quotes: `platform_failures.dart`.
- The five scan events and four advertising events do not pass `timestamp` to `BlueyEvent` today, and `BlueyEvent` takes an optional one: `events.dart`, `shared/domain/bluey_event.dart`. `ScanStartingEvent` and `ScanStartedEvent` carry `serviceFilter` and `timeout`; `ScanStoppedEvent`'s `reason` is never set; `DeviceDiscoveredEvent` is emitted with no `source`; an invalidation emits no stopped event: `discovery/bluey_scanner.dart` lines 180 to 213 and 269.
- `AndroidScanner.scan` does not handle `startScan`'s future and `onScanComplete` is a no-op: `bluey_android/lib/src/android_scanner.dart`.
- `FakeBlueyPlatform` has `lastScanConfig`, `simulateScanFailure(Object)`, `isScanning`, `advertiseConfig` and `isAdvertising`: `test/fakes/fake_platform.dart`.
- `UUID`'s constructor throws only `ArgumentError`, which placed code may raise; `manufacturer_data.dart` imports `dart:typed_data` and `package:meta` only.
- Only `lib/src/bluey.dart` imports `discovery/{device,advertisement,scan_result,scan}.dart` inside `lib/src`; `lib/bluey.dart` exports them.
- `known_violations.dart` holds, for the files this plan moves or shrinks: seven `unplaced` entries under `discovery/`, `shared/uuid.dart` and `shared/manufacturer_data.dart`; one `boundaries` and one `frameworkPlacement` entry for `bluey_scanner.dart`; a `frameworkPlacement` entry for `peer_discovery.dart`; `oversized` entries for `bluey.dart` (974), `bluey_scanner.dart` (410), `events.dart` (477) and `bluey_server.dart` (1180).
- `BlueyServer.startAdvertising` (lines 607 to 680) builds the config, sets state around the platform call and rethrows; `_stopAdvertisingUnguarded` acts only in `advertising`.

**Findings fixed in this plan before it was handed over.** The design's scan and radio phases shared the name `Scanning` with the port (now `Served` and `RadioScanning`); the input and the phase were both `ScannerClosed` (the input is `ScannerDisposed`); the public scan events need the timeout and the design's `ScanAsk` did not carry it (it carries `timeLimit`, read by no rule); nothing told a handle that one of a scanner's two scans had ended (`ScanEnded`); the session would have had to read the advertising phase to know whose ask had been answered (`AskOutcome`, answered by the step); a static `UUID.parse` answering `Either` would have put an internal type on a public class (a top-level `uuidFrom`); and `AdvertiseMode` moving under `features/` could not be exported by `lib/bluey.dart` directly (the edge library `api/gatt_server/advertising.dart`).

Verdict: ready.
