# Link Lifecycle, Pull Request 2: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task, as pull request 1 was built (a fresh implementer and a fresh reviewer per task, a whole-branch review at the end). Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish slice 1: bring Joel's four open architecture rulings of 2026-11-26 into the Connection context that pull request 1 merged, then build the rest of Connection (Tasks 17 to 26 of the slice 1 plan: composition, value objects, capabilities, link features, MTU and RSSI, bonding, PHY, connection parameters, and the edge taking over).

**Architecture:** This plan does not replace `docs/superpowers/plans/2026-11-18-link-lifecycle.md` (the "slice plan"). It adds ten tasks, R1 to R10, that run first on the code pull requests 43 and 44 merged, and then amends Tasks 17 to 26 of the slice plan where a ruling or a carry-over changes them. An implementer of Task N reads the slice plan's Task N and this plan's amendment to it; where the two differ, this plan wins. After R1 to R10 the domain speaks only its own language (`LinkPhase`, `LinkEvent`, `LinkOperation`), and `api/connection/` is the one place that translates it to the public one (`ConnectionState`, the three public events, the exceptions).

**Tech Stack:** Dart 3 (sealed classes, records, switch expressions), Flutter 3.47.2, `fake_async`, the `bluey_guards` package, Pigeon (untouched here).

**Spec:** `docs/superpowers/specs/2026-11-18-link-lifecycle-design.md`, with the two reviews of pull request 43 (`/mnt/project-files/bluey-slice1-2026-11-18/architecture-review.md` and `architecture-review-fable.md`) and Joel's five rulings on them, restated under "Rulings" below. Task 26 writes those rulings into the design as an addendum.

## Global Constraints

Every constraint of the slice plan's "Global Constraints" holds. The ones a reviewer rejects a task for most often, and the ones this plan adds:

- TDD: no production line without a failing test first. Each task's first commit may hold the failing test alone.
- A list in any `known_violations.dart` or `roster.dart` only shrinks. The one exception this plan makes is named in R4 (`edgeFromBelow`, born with ten entries).
- `bluey/api/bluey.api` changes only where this plan says so (R7: three constructor lines; Task 18, 19 and 25 as the slice plan says). Any other difference in the dump fails the task.
- Log lines an app can read keep their context, message and data keys and values byte for byte (ruling 46). `test/logging/` and every `expect` on a log line are the proof; a task never edits one of those expectations to pass.
- No bounded context imports another. An `api/<context>/` file names only its own context's `features/<context>/` (ruling 4); after R4 the build holds it.
- Domain files import nothing but `dart:core`, `dart:async`, `package:meta` and their own context's domain and `shared/domain`. After R6 no application file imports `package:clock`.
- No `!` on a nullable in new or touched code; a sealed type and a `switch` instead.
- Comments say why, never how. No journal comments, no ruling numbers in code.
- Coverage: 90% of `bluey`'s lines, 95% under `lib/src/features/*/domain` and `lib/src/shared/domain`, no file with code that no test loads.
- File size caps of the size rule hold; `lib/src/bluey.dart` (977) and `lib/src/connection/bluey_connection.dart` (1456) may only shrink.
- Commits are Conventional Commits, scoped (`refactor(connection): …`, `feat(guards): …`), one task per commit series, and name no model.
- Branch `claude/project-thread-u804gs`, restarted from `main` at `9715b72`. One pull request.
- Gates that run in the cloud session: every Dart suite of the five packages, `flutter analyze`, the format check, the guards' tests, the architecture tests, list growth, the public API dump, known defects, both coverage floors. Kotlin and XCTest run on Joel's Mac; no task in this plan changes native code.

## Review Focus

The conditions most likely to bite an app that no single task's happy path exercises. Each has its test in the task named.

1. **A device that connects and drops thousands of times in one process.** `PlatformLinks` must hold nothing for a link that ended. Test in R1 (the carrier map is empty after an end, and a second link to the same device gets its own carrier).
2. **An app that filters `bluey.logEvents` by text.** The state word in `state transition` stays `ConnectionState.disconnecting`, and `errorCode` on `connect failed` stays the old type name, after the domain stops naming `ConnectionState` and failures gain codes. Tests in R5 and R9 (golden lines for every phase, operation and failure).
3. **An app that compares `ConnectionEvent` timestamps with its own clock under `fakeAsync`.** The public event carries the instant the domain stamped with the injected clock, not `DateTime.now()` at translation. Tests in R6 and R7.
4. **A second `connect` while the first link is closing, and a borrower arriving in the same instant.** `LiveLinks` must answer `Wait` then `Open` exactly as the table did before, with no session lost between the two maps that become one. Test in R8 (the existing decision-table tests, rerun unchanged, plus one for a borrower and the app racing a close).
5. **`requestMtu(600)`, `Mtu(22)`, and a feature the platform lacks.** Each is a typed failure naming a `LinkOperation`, and the exception an app sees keeps its message. Tests in Tasks 18, 20 and 21 as amended.

## Rulings

Joel's rulings of 2026-11-26 on the reviews of pull request 43, as this plan carries them:

- **Ruling 1 (API layer by context).** No Connection file sits at the root of `api/`. R3.
- **Ruling 2 (shared device streams).** Done in pull request 44.
- **Ruling 3 (published language).** The domain raises internal events; `api/<context>/` translates them to the public ones; the unit that raises an event stamps its time with an injected clock. Connection's events move in this pull request. R7.
- **Ruling 4 (edge isolation).** An edge file names only its own context's domain and application, and may name any context's public interfaces. R4 builds the rule.
- **Ruling 5 (phase).** `ConnectionState` stays public at `api/connection/`; `Link` has its own sealed phase; the edge maps. R5.

Rulings 1 to 41 of the build ledger stand. The calls this plan makes, numbered on from them. Joel overrules any by saying so; 51 and 48's constructor change are the two that touch the public API or the architecture.

- **42.** One pull request. R1 to R10 run before Task 17, so every later task is written once, against the final names.
- **43.** The translator's home is `api/connection/connection_failure_translation.dart`. `api/` keeps only the composition root and files that belong to no single context.
- **44.** Two new guard rules. `edge contexts` is born empty and stays empty. `edge from below` lists the ten imports of `lib/src/api/` from unplaced files and only shrinks; four leave in Task 25, the other six with the Peer slice. The list-growth command learns `--first-statement=<list>`, which lets a list be born with entries in the one change that introduces it and is ignored, with a printed note, once the base has the list.
- **45.** `LinkPhase` is sealed: `Linked` and `Ready` (both `UpPhase`), `Closing(returnTo, by)`, `Ended(end)`. `Link.phase` replaces `Link.state` and the three private fields. The domain, not the session, decides when a phase was entered (`LinkStep.entered`). `ClosingBy` is `request`, `radio` or `both`.
- **46.** What an app can read in a log line is frozen in this slice: contexts, messages, data keys (`address`, `deviceId` as they are today, inconsistent or not) and values, including the word `ConnectionState.<name>` for a state and today's type names as `errorCode`. Renaming them is a public change for a later slice with a CHANGELOG line.
- **47.** The clock is `typedef Now = DateTime Function();` in `shared/application/now.dart`, passed in by the composition root as `clock.now`. Application code takes it by constructor; `package:clock` leaves the application allowance of the architecture test.
- **48.** Internal events are a sealed `LinkEvent` (`LinkOpenBegan`, `LinkOpened`, `LinkEnded`). The aggregate raises what it decides: `Link` returns `LinkOpened` and `LinkEnded` in its step, stamped with the instant it is handed. `LinkOpenBegan` has no aggregate yet, so the registry raises it. All three leave the application through the port `LinkEvents`. `api/connection/` implements the port by translating to `ConnectingEvent`, `ConnectedEvent` and `DisconnectedEvent`, which move to `api/connection/connection_events.dart` and gain an optional `timestamp` parameter so the translator can pass the domain's instant. That is three added optional parameters in the public API dump, nothing removed.
- **49.** `LiveLinks` holds the links it tabulates, so the registry keeps one map, not three, and `Admission` becomes sealed (`Open`, `Wait`, `Reuse`). What the table reads of a link is a domain interface, `LiveLink`; the table is generic only over which `LiveLink` it holds.
- **50.** A failure names what was attempted with `LinkOperation`, an enum in Connection's own words (`open`, `negotiateMtu`, `readSignalStrength`), not the platform interface's method names. The domain carries no log word and no failure code: the frozen strings of ruling 46 live in one application file, `connection_log_words.dart`, as exhaustive mappings, and leave with it.
- **51.** Published language for values. A value object an app builds and hands in (`Mtu`, `Phy`, `PhyPair`, `ConnectionParameters`, `ConnectionPriority`, `BondState`) is published as it stands and re-exported by its context's `api/<context>/` library; it is not copied into an edge twin. A public library exports nothing under `lib/src/features/` directly: `PublicExportsRule` refuses it, held from R10. Events, phases and failures are translated; values are shared.
- **52.** The assembly of Task 17 is told the platform by an edge enum and a name (`ConnectionExtension { android, ios, none }`, `platformName`), mapped by the composition root from Platform's `PlatformKind`. Connection's edge never imports `features/platform/`.
- **53.** `LinkGattClient` is handed a `BlueyException Function(LinkEnd)` by the assembly and loses its four imports of `lib/src/api/` in Task 25.
- **54.** Ruling 37 (the log level of a probe's failed connect) is still Joel's to make and is not decided here. The build leaves the level as merged and the pull request description lists it as open.

## File Structure

New files, by task. Tests mirror each path under `bluey/test/` (and `bluey_guards/test/`).

| File | Responsibility | Task |
|---|---|---|
| `bluey/lib/src/api/connection/connection_failure_translation.dart` | Connection's failures and ends as the exceptions an app catches (moved) | R3 |
| `bluey_guards/lib/src/architecture/rules/edge_context_rule.dart` | An edge file names only its own context's features | R4 |
| `bluey_guards/lib/src/architecture/rules/edge_from_below_rule.dart` | Code below the edge does not import the edge | R4 |
| `bluey/lib/src/features/connection/domain/link_phase.dart` | Where a link is in its life, in the domain's words | R5 |
| `bluey/lib/src/api/connection/connection_state.dart` | The public `ConnectionState` (moved from the domain) | R5 |
| `bluey/lib/src/api/connection/connection_state_translation.dart` | `connectionStateOf(LinkPhase)` | R5 |
| `bluey/lib/src/features/connection/application/connection_log_words.dart` | Every app-readable word of Connection's logs that this slice freezes | R5, R9 |
| `bluey/lib/src/shared/application/now.dart` | `typedef Now` | R6 |
| `bluey/lib/src/features/connection/domain/link_event.dart` | What happened to a link, in the domain's words | R7 |
| `bluey/lib/src/features/connection/application/ports/link_events.dart` | The port the application raises events through | R7 |
| `bluey/lib/src/api/connection/connection_events.dart` | The public events (moved from the domain) | R7 |
| `bluey/lib/src/api/connection/connection_event_translation.dart` | `PublishedLinkEvents implements LinkEvents` | R7 |
| `bluey/lib/src/features/connection/domain/link_operation.dart` | What was attempted on a link | R9 |
| `bluey/lib/src/features/connection/domain/live_link.dart` | What the table of live links reads of a link | R8 |

Deleted: `api/failure_translation.dart` (R3), `features/connection/domain/connection_state.dart` (R5), `features/connection/domain/connection_event.dart` (R7).

---

## Before R1: pre-flight

- [ ] Restart `claude/project-thread-u804gs` from `origin/main` (`9715b72` or later); install Flutter 3.47.2; `dart pub get` at the root; create the Gradle wrapper only if a native gate is run.
- [ ] Start the build ledger at `.superpowers/sdd/2026-11-26-link-lifecycle-pr2/` (git-ignored), with `progress.md` and `parked-minors.md` as in pull request 1, and add this plan's rows to the pre-flight scan table: for each of R1 to R10 and Tasks 17 to 26, the files it touches that carry a size entry, the lists it is expected to shrink, and whether the API dump may change.
- [ ] Run every cloud gate once on the untouched branch and record the numbers (tests, coverage, list lengths) as the baseline.

---

## Task R1: Carriers and fakes hold nothing for an ended link

Ruling 41 and parked minors 28 and 32.

**Files:**
- Modify: `bluey/lib/src/features/connection/infrastructure/adapters/platform_links.dart`
- Modify: `bluey/test/fakes/fake_platform.dart`, `bluey/test/fixtures/features/connection/in_memory_links.dart` (the path the fixture has today)
- Test: `bluey/test/features/connection/infrastructure/platform_links_test.dart`, the two fixtures' own tests

**Interfaces:**
- Produces: nothing new. `PlatformLinks` gains `@visibleForTesting int get carriedLinks`.

- [ ] **Step 1: Failing test.** In `platform_links_test.dart`, group `carriers`: `'holds no carrier once a link has ended'` opens a link, listens to `reportsOf`, has the fake platform report `disconnected`, and expects `links.carriedLinks == 0`; `'a late end of an old link leaves the new link's carrier in place'` opens A, ends A but delays its stream's done, opens A again as a new `LinkId`, completes the old stream, and expects `carriedLinks == 1` and the new link's reports still delivered.
- [ ] **Step 2:** Run `cd bluey && flutter test test/features/connection/infrastructure/platform_links_test.dart`; both fail (no getter, then 1 and 0).
- [ ] **Step 3:** In `PlatformLinks`, remove a carrier from `_reports` when its stream ends or `close` resolves, and only if the map still holds that same carrier (`identical`), so a late end never removes a successor's.
- [ ] **Step 4:** Parked 32, test first: `InMemoryLinks.close` of a link whose device has since been opened again leaves the newer link open. Fix by comparing identity, not address.
- [ ] **Step 5:** Parked 28, test first in `test/fakes/fake_platform_test.dart`: a `disconnect` of a device that was never connected installs no second signal and no held answer. Fix in the fake.
- [ ] **Step 6:** Run the whole `bluey` suite; commit `fix(connection): drop the carrier of a link that ended`.

## Task R2: The Android echo filter forgets a mark the link outlived

Parked minor 29, now in `DisconnectEcho`.

**Files:**
- Modify: `bluey_android/lib/src/disconnect_echo.dart`
- Test: `bluey_android/test/disconnect_echo_test.dart`

- [ ] **Step 1: Failing tests.** `'a mark is forgotten when the device reports connecting'` and `'… connected'`: `expectFor(device)`, feed `connecting` (then `connected`) through the method the manager feeds reports through, then `isEcho(device, disconnected)` is false. Keep the existing test that a mark survives `disconnecting`.
- [ ] **Step 2:** Run `cd bluey_android && flutter test test/disconnect_echo_test.dart`; the two fail.
- [ ] **Step 3:** Clear the mark on `connecting` and `connected` as well as `disconnected`.
- [ ] **Step 4:** Run the package's suite and its architecture test; commit `fix(android): forget a disconnect echo mark once the device links again`.

## Task R3: Connection's translator lives with Connection's edge

Ruling 1; review minors on `api/connection/connection.dart` and the edge docs.

**Files:**
- Move: `bluey/lib/src/api/failure_translation.dart` to `bluey/lib/src/api/connection/connection_failure_translation.dart`
- Move: `bluey/test/api/failure_translation_test.dart` and `failure_translation_parity_test.dart` to `bluey/test/api/connection/connection_failure_translation_test.dart` and `…_parity_test.dart`
- Modify: every importer (`api/connection/bluey_connection.dart`, `connections.dart`, `borrowed_connection.dart`, `lib/src/bluey.dart`, `lib/src/connection/bluey_connection.dart`), `api/connection/connection.dart`, `test/architecture/known_violations.dart` only if an entry names the old path (rewrite the path, same count)

**Interfaces:**
- Produces: the same three functions, unchanged: `connectionFailureAsException`, `linkEndAsException`, `valueOrThrow`.

- [ ] **Step 1:** `git mv` the file and the two tests; fix imports; run `flutter analyze` and the two tests.
- [ ] **Step 2:** `api/connection/connection.dart`: sort the imports and exports, delete the trailing doc comment that documents nothing, and correct the class doc where it says a `Connection` reports `connecting` (it never does; a `Connection` exists only once linked).
- [ ] **Step 3:** Head `lib/src/connection/bluey_connection.dart` with a library doc saying the file holds only `LinkGattClient`, the GATT client of one link, and leaves with the GATT client slice; no rename of the file in this slice.
- [ ] **Step 4:** Run the `bluey` suite, the architecture test and the API dump check (no change); commit `refactor(api): move Connection's failure translation under api/connection`.

## Task R4: The build holds the edge to its own context

Ruling 4 and the recommended guard.

**Files:**
- Modify: `bluey_guards/lib/src/architecture/placement.dart` (`InApi`)
- Create: `bluey_guards/lib/src/architecture/rules/edge_context_rule.dart`, `edge_from_below_rule.dart`
- Modify: `bluey_guards/lib/src/gates/list_growth.dart` and the command that wraps it (`bluey/test/architecture/list_growth.dart` and its siblings in the other packages call into it)
- Modify: `bluey/test/architecture/bluey_architecture.dart`, `known_violations.dart`; `.github/workflows/ci.yml` (the list-growth step, `bluey` only); `CLAUDE.md` (the list-growth command); `docs/ARCHITECTURE.md` sections 4 and 5 (two rule rows)
- Test: `bluey_guards/test/architecture/placement_test.dart`, `rules/edge_context_rule_test.dart`, `rules/edge_from_below_rule_test.dart`, `bluey_guards/test/gates/list_growth_test.dart`

**Interfaces:**
- Produces:
  - `InApi({this.context})`, `final String? context`: the first folder under `lib/src/api/`, null for a file directly in `api/`. Equality and `toString` include it.
  - `EdgeContextRule({required String package, required Set<String> compositionRoots})`, `name => 'edge contexts'`. A violation is `Violation(source.path, target.path)`.
  - `EdgeFromBelowRule({required String package, required Set<String> compositionRoots})`, `name => 'edge from below'`. A violation is `Violation(source.path, target.path)`, listed as `'<source> -> <target>'`.
  - `ListGrowth.between(…, Set<String> firstStatements = const {})` and the command flag `--first-statement=<list>` (repeatable).

- [ ] **Step 1: Failing tests for the placement.** `lib/src/api/connection/x.dart` is `InApi(context: 'connection')`; `lib/src/api/bluey.dart` is `InApi(context: null)`; the two are not equal.
- [ ] **Step 2: Failing tests for `EdgeContextRule`.** Over an in-memory `SourceTree`: `api/connection/a.dart` importing `features/connection/domain/x.dart` passes; importing `features/gatt/domain/y.dart` is a violation; importing `api/gatt/z.dart` passes (another context's public interface); a file directly in `api/` importing any `features/` file is a violation unless it is a composition root; imports of `shared/` and of unplaced legacy files are not judged.
- [ ] **Step 3: Failing tests for `EdgeFromBelowRule`.** An unplaced file (`lib/src/peer/p.dart`) importing `lib/src/api/connection/connection.dart` is a violation; a composition root is not; a file under `features/` or `shared/` is not judged here (the layer rule already refuses it); an `api/` file importing `api/` is not a violation.
- [ ] **Step 4:** Implement both rules with the helpers of `rule_support.dart`; run `cd bluey_guards && dart test`.
- [ ] **Step 5: Failing tests for the gate.** With `firstStatements: {'edgeFromBelow'}`: a list the base lacks may hold entries; a list the base has is judged as ever and the result carries a note that the flag no longer applies; a flag naming a list the head lacks is an error. Implement; the command prints the note.
- [ ] **Step 6:** In `bluey_architecture.dart` add both rules with `compositionRoots: {'lib/src/bluey.dart', 'lib/src/api/bluey.dart'}`. In `known_violations.dart` add `const edgeContexts = <String>[];` and `const edgeFromBelow` with exactly these ten, sorted:

```
lib/src/connection/bluey_connection.dart -> lib/src/api/connection/android_connection_extensions.dart
lib/src/connection/bluey_connection.dart -> lib/src/api/connection/connection.dart
lib/src/connection/bluey_connection.dart -> lib/src/api/connection/connection_failure_translation.dart
lib/src/connection/bluey_connection.dart -> lib/src/api/connection/ios_connection_extensions.dart
lib/src/peer/bluey_peer.dart -> lib/src/api/connection/borrowed_connection.dart
lib/src/peer/bluey_peer.dart -> lib/src/api/connection/connection.dart
lib/src/peer/peer_connection.dart -> lib/src/api/connection/connection.dart
lib/src/peer/peer_discovery.dart -> lib/src/api/connection/borrowed_connection.dart
lib/src/peer/peer_discovery.dart -> lib/src/api/connection/connection.dart
lib/src/peer/peer_remote_service_view.dart -> lib/src/api/connection/connection.dart
```

  If the rule finds a different set, the rule's finding is the truth: stop and record the difference in the ledger before listing it.
- [ ] **Step 7:** Pass `--first-statement=edgeFromBelow` in ci.yml's `bluey` list-growth call and in `CLAUDE.md`'s command; note beside both that it is removed in the first change after this one merges. Run `cd bluey && dart run test/architecture/list_growth.dart origin/main test/architecture/known_violations.dart test/known_defects/roster.dart --first-statement=edgeFromBelow`; it passes.
- [ ] **Step 8:** Add the two rows to `docs/ARCHITECTURE.md`; run the architecture tests of all five packages; commit `feat(guards): hold the edge to its own context and code below it off the edge`.

## Task R5: A link has its own phase

Ruling 5; parked minors 3, 4 and 14.

**Files:**
- Create: `features/connection/domain/link_phase.dart`, `api/connection/connection_state.dart`, `api/connection/connection_state_translation.dart`, `features/connection/application/connection_log_words.dart`
- Delete: `features/connection/domain/connection_state.dart`
- Modify: `domain/link.dart`, `application/link_session.dart`, `application/link_registry.dart`, `infrastructure/adapters/platform_links.dart` (the context constant only), `api/connection/bluey_connection.dart`, `api/connection/connection.dart`, `lib/src/connection/bluey_connection.dart` and any legacy reader of `session.states`
- Test: `test/features/connection/domain/link_test.dart` (rewritten to phases), `link_phase_test.dart`, `test/api/connection/connection_state_translation_test.dart`, `test/features/connection/application/connection_log_words_test.dart`, `link_session_test.dart`

**Interfaces:**
- Produces:

```dart
// domain/link_phase.dart
sealed class LinkPhase { const LinkPhase(); }
sealed class UpPhase extends LinkPhase { const UpPhase(); }
final class Linked extends UpPhase { const Linked(); }
final class Ready extends UpPhase { const Ready(); }
enum ClosingBy { request, radio, both }
final class Closing extends LinkPhase {
  const Closing({required this.returnTo, required this.by});
  final UpPhase returnTo;   // where a failed close of ours returns the link
  final ClosingBy by;       // who is closing it: our request, the radio, or both
}
final class Ended extends LinkPhase { const Ended(this.end); final LinkEnd end; }
```

  All four are equal by value. `Link.phase` (a `LinkPhase`) replaces `Link.state`, `_upState`, `_closeAsked` and `_radioClosing`; `Link.end` is `switch (phase) { Ended(:final end) => end, _ => null }`; `isUp`, `isClosing`, `hasEnded` and `endInSight` keep their meaning and are derived from the phase.
  - `LinkStep(this.link, {this.duty, this.entered})`: `entered` is the phase the step entered, null when the step stayed in the same kind of phase (a `Closing` whose `by` changed has not entered `Closing` again).
  - `LinkDuty { closeTheLink, release }` (`releaseAndAnnounce` renamed: what is announced is an event the link raises in R7, not a duty).
  - `LinkSession.phases` (`Stream<LinkPhase>`, replacing `states`) and `LinkSession.phase`.
  - `ConnectionState connectionStateOf(LinkPhase phase)`: `Linked` to `linked`, `Ready` to `ready`, `Closing` to `disconnecting`, `Ended(EndedByRadioOutage)` to `invalidated`, any other `Ended` to `disconnected`.
  - `application/connection_log_words.dart` is the one home of every word of Connection's log lines that an app can read and that this slice freezes (ruling 46). In this task it holds `const connectionLogContext = 'bluey.connection';` and `String stateWordOf(LinkPhase phase)`, which answers `'ConnectionState.linked'`, `'.ready'`, `'.disconnecting'`, `'.disconnected'`, `'.invalidated'` as literals. Its library doc says these are the words logs had before the domain had its own, kept so an app's log filters hold, and that the slice which revises log wording deletes the file.

- [ ] **Step 1: Failing domain tests.** Rewrite `link_test.dart`'s table over phases, one row per row it has today, plus: a request while the radio closes gives `Closing(by: both)` and `entered == null`; `CloseFailed` from `Closing(returnTo: Ready, by: request)` returns to `Ready` with `entered == Ready()`; from `by: both` it stays `Closing(by: radio)`; every input on `Ended` returns the same link with no duty and no `entered`.
- [ ] **Step 2:** Run; they fail to compile. Write `link_phase.dart` and rewrite `Link` over it, each transition one `switch` arm on `(phase, input)`. No `StateError` for a combination the types now exclude (parked 14).
- [ ] **Step 3: Failing tests for the two mappings.** `connectionStateOf` for each of the seven shapes (two up phases, `Closing`, and `Ended` with each `LinkEnd`); `stateWordOf` returns the five exact strings. The log test also asserts the session's `state transition` line for each phase against the literal it had on `main` (copy the expectation from `git show origin/main:bluey/test/...` rather than from the new code).
- [ ] **Step 4:** Move `ConnectionState` to `api/connection/connection_state.dart` with its doc corrected (no clause about peers; `connecting` is kept for apps that switch over it and is never reported by a `Connection`). `api/connection/connection.dart` exports it. Run the API dump check: no change.
- [ ] **Step 5:** `LinkSession`: `phases`; emit and log on `step.entered` only; replace `_link.end!` and `_closeInFlight!` with pattern matches (parked 3, 4). `BlueyConnection.state`/`stateChanges` map with `connectionStateOf`. The three `'bluey.connection'` literals become `connectionLogContext`.
- [ ] **Step 6:** Run the `bluey` suite (the logging tests included, unedited), the architecture test, coverage floors; commit `refactor(connection): give Link its own phase and translate it at the edge`.

## Task R6: The application is handed its clock

Ruling 47. A task of its own so the events of R7 change one thing.

**Files:**
- Create: `bluey/lib/src/shared/application/now.dart`
- Modify: `features/connection/application/link_registry.dart`, `link_session.dart`, `lib/src/bluey.dart` (construction only), `test/architecture/bluey_architecture.dart` (the application allowance), `test/fixtures/connection_rig.dart`
- Test: `link_registry_test.dart`, `link_session_test.dart`

**Interfaces:**
- Produces: `typedef Now = DateTime Function();` and `required Now now` on `LinkRegistry` and `LinkSession`.

- [ ] **Step 1: Failing tests.** With `now` a function the test advances by hand (not `fakeAsync`'s clock), the registry's wait for a closing link times out when the handed clock passes the deadline, and the duration in the `connect succeeded` log line is measured by it.
- [ ] **Step 2:** Implement; `lib/src/bluey.dart` passes `clock.now`. Remove `package:clock` from `link_registry.dart` and from the application allowance of the architecture test; the architecture test passes with no new list entry.
- [ ] **Step 3:** Whole `bluey` suite; commit `refactor(connection): hand the application its clock`.

## Task R7: The link raises its own events; the edge publishes them

Ruling 3.

**Files:**
- Create: `features/connection/domain/link_event.dart`, `features/connection/application/ports/link_events.dart`, `api/connection/connection_events.dart`, `api/connection/connection_event_translation.dart`
- Delete: `features/connection/domain/connection_event.dart`
- Modify: `domain/link.dart`, `application/link_registry.dart`, `application/link_session.dart`, `lib/src/bluey.dart` (construction only), `lib/bluey.dart` (one export path), `bluey/api/bluey.api`
- Test: `test/features/connection/domain/link_event_test.dart`, `link_test.dart`, `test/api/connection/connection_event_translation_test.dart`, registry and session tests; fixture `test/fixtures/features/connection/recording_link_events.dart`

**Interfaces:**
- Produces:

```dart
// domain/link_event.dart
sealed class LinkEvent {
  const LinkEvent({required this.device, required this.at});
  final DeviceAddress device;
  final DateTime at;
}
final class LinkOpenBegan extends LinkEvent { … }
final class LinkOpened extends LinkEvent { … }
final class LinkEnded extends LinkEvent { …; final LinkEnd end; }

// domain/link.dart: the aggregate raises what it decides
static LinkStep Link.open({required LinkId id, required DeviceAddress device, required DateTime at});
LinkStep on(LinkInput input, {required DateTime at});
// LinkStep gains: final List<LinkEvent> events;  (empty unless the step raised one)

// application/ports/link_events.dart
abstract interface class LinkEvents { void raise(LinkEvent event); }

// api/connection/connection_event_translation.dart
final class PublishedLinkEvents implements LinkEvents {
  PublishedLinkEvents(EventPublisher publisher);
}
```

  - **Who raises what.** `Link.open` is the only way to build a link (the public constructor goes) and its step carries `LinkOpened`. `Link.on` carries `LinkEnded` in the one step that enters `Ended`, and never again. The session and the registry do not construct those two events; they pass `now()` in and hand `step.events` to the port, in order, after the step's state is stored. `LinkOpenBegan` is the one event with no aggregate behind it, since no `Link` exists until the radio answers: the registry constructs it when `LiveLinks` answers `Open`, before it asks the port to open. The design review records this as the one event the application raises, and why.
  - `LinkRegistry({required Links links, required LinkEvents events, required Log log, required Now now})`, and `LinkEvents` in place of `EventPublisher` on `LinkSession`.
  - Public: `ConnectingEvent({required DeviceAddress deviceAddress, String? source, DateTime? timestamp})`, and the same added parameter on `ConnectedEvent` and `DisconnectedEvent`, each forwarding `super.timestamp`.
  - `PublishedLinkEvents` owns the public reason words of `DisconnectedEvent`: `EndedOnRequest` is `'requested'`, `EndedByDrop` is `'linkLoss'`, `EndedByRadioOutage` is `'radioOutage'`, exactly as `LinkSession._reasonOf` has them today; `_reasonOf` is deleted from the session.

- [ ] **Step 1: Failing domain tests.** `Link.open(…, at: t)` answers a step whose link is `Linked`, whose `entered` is `Linked()` and whose `events` are `[LinkOpened(device, at: t)]`. For each row of the table that enters `Ended`, `events` is `[LinkEnded(device, at, end)]` with the row's end; for every other row, and for every input on an ended link, `events` is empty.
- [ ] **Step 2: Failing translation tests.** For each `LinkEvent`, the published event's type, `deviceAddress`, `reason` and `timestamp == event.at`.
- [ ] **Step 3: Failing application tests.** With a `RecordingLinkEvents` and a fixed `now`: an opened link records `LinkOpenBegan` then `LinkOpened`, a reused one records neither, a failed open records `LinkOpenBegan` alone; a link that ends records exactly one `LinkEnded`, also when a late report follows; each `at` is the handed instant.
- [ ] **Step 4:** Implement; move the three public events to `api/connection/connection_events.dart` (base `ConnectionEvent` with them), add the parameter, change the export in `lib/bluey.dart`.
- [ ] **Step 5:** Run `cd bluey && dart run bluey_guards:public_api lib/bluey.dart api/bluey.api`; it reports exactly the three constructor lines. Rewrite with `--write` and confirm by `git diff` that nothing else moved.
- [ ] **Step 6:** Whole `bluey` suite (integration tests that expect the three events on `bluey.events` pass unedited), architecture, coverage; commit `refactor(connection): raise link events in the domain and publish them at the edge`.

## Task R8: The registry keeps one table

Review minors on `LiveLinks` and `LinkRegistry`.

**Files:**
- Create: `features/connection/domain/live_link.dart`
- Modify: `domain/live_links.dart`, `application/link_session.dart`, `application/link_registry.dart`, `application/borrow_link.dart`, `application/connect_device.dart`, `api/connection/connections.dart` where it calls `keep`/`giveBack`
- Test: `test/features/connection/domain/live_links_test.dart`, `link_registry_test.dart`, `borrow_link_test.dart`

**Interfaces:**
- Produces:

```dart
// domain/live_link.dart: what the table needs to know of a link it holds
abstract interface class LiveLink { bool get isClosing; }

sealed class Admission<L extends LiveLink> { const Admission(); }
final class Open<L extends LiveLink> extends Admission<L> { const Open(); }
final class Wait<L extends LiveLink> extends Admission<L> { const Wait(); }
final class Reuse<L extends LiveLink> extends Admission<L> { const Reuse(this.link); final L link; }

final class LiveLinks<L extends LiveLink> {
  Admission<L> admit(DeviceAddress device, LinkUser user);
  void opened(DeviceAddress device, LinkUser user, L link);
  AfterGiveBack givenBack(DeviceAddress device, LinkUser user);
  void kept(DeviceAddress device);
  void ended(DeviceAddress device, L link);   // by identity: an old link's end never drops its successor
}
```

  The table is generic only so the registry gets back the type it put in; what the table reads of a link is named in the domain (`LiveLink`), and `LinkSession implements LiveLink`. `LinkRegistry.hold(DeviceAddress device, {Duration? timeout})` answers the app's `LinkSession`; `LinkRegistry.borrow(DeviceAddress device, {Duration? timeout})` answers a `BorrowedLink` whose `giveBack` and `keep` are closures over the registry. `acquire`, `giveBack(session)` and `keep(session)` are private.

- [ ] **Step 1:** Port `live_links_test.dart` to the new form with a two-line test `LiveLink`, every row kept; add `'a borrower and the app both arriving while the link closes each wait, then one opens and the other reuses'` and `'ended by an old holder leaves the new entry'`.
- [ ] **Step 2:** Implement; the registry's `_sessions` map and every `session!` go. Run the Connection tests and the integration tests of probes (`test/integration/`), unedited.
- [ ] **Step 3:** Commit `refactor(connection): let LiveLinks hold the links it tabulates`.

## Task R9: Failures name the operation in the domain's words

Review Important on stringly operations; parked minor 9.

**Files:**
- Create: `features/connection/domain/link_operation.dart`
- Modify: `domain/connection_failure.dart`, `application/connection_log_words.dart`, `infrastructure/adapters/platform_failures.dart`, `platform_links.dart`, `application/link_registry.dart`, `link_session.dart`, `api/connection/connection_failure_translation.dart`
- Test: `connection_failure_test.dart`, `connection_log_words_test.dart`, `platform_failures_test.dart`, the translator's tests

**Interfaces:**
- Produces:

```dart
// domain/link_operation.dart: what can be attempted on a link, in Connection's words
enum LinkOperation { open, close }
```

  The domain holds no string for an operation and no code for a failure: those are wording, and wording an app can read is frozen in one place. Later tasks add values in the domain's words, never the platform interface's method names: `negotiateMtu`, `readWritePayloadLimit`, `readSignalStrength` (Task 21); `readBondState`, `watchBondState`, `bond`, `removeBond` (22); `readPhy`, `watchPhy`, `requestPhy` (23); `readParameters`, `requestParameters` (24).
  - `application/connection_log_words.dart` gains `String operationWordOf(LinkOperation operation)` and `String failureCodeOf(ConnectionFailure failure)`, each an exhaustive `switch` answering the literal logs and exception messages carry today (`open` is `'connect'`, `close` is `'disconnect'`; a later task's value takes the string the legacy code logs for it, e.g. `negotiateMtu` is `'requestMtu'`; a failure's code is its class name on `main`, e.g. `'ConnectFailed'`, `'OperationTimedOut'`). Exhaustive, so a new operation or failure cannot be added without its word.
  - `OperationTimedOut(LinkOperation operation)`, `OperationRejected(LinkOperation operation, int status)`.
  - `connectionFailureFrom(Object error, {required LinkOperation operation})`, `answering<T>(LinkOperation operation, Future<T> Function() call)`.
  - `UnexpectedPlatformFailure` equality and hash exclude `cause`; `ConnectFailed.message` is a sentence, not a `toString` of a type.

- [ ] **Step 1: Failing tests.** Each operation's word and each failure's code against the literal; the `connect failed` log line's `errorCode` and `exception` values against the lines on `main`; two `UnexpectedPlatformFailure`s with different causes and the same message are equal; the translator's message for `OperationTimedOut(LinkOperation.open)` is the string it is today.
- [ ] **Step 2:** Implement; replace every `failure.runtimeType` in a log call with `failureCodeOf(failure)`, and the translator reads `operationWordOf`.
- [ ] **Step 3:** Whole suite, parity test, API dump (no change); commit `refactor(connection): name the attempted operation in the domain's words`.

## Task R10: A context reaches apps only through its edge

The half of ruling 51 the build can hold.

**Files:**
- Modify: `bluey_guards/lib/src/architecture/rules/public_exports_rule.dart`, `docs/ARCHITECTURE.md` (the `public exports` row)
- Test: `bluey_guards/test/architecture/rules/public_exports_rule_test.dart`

- [ ] **Step 1: Failing tests.** A public library that exports a file under `lib/src/features/` is a violation; exports of `lib/src/api/`, `lib/src/shared/` and unplaced files pass as today.
- [ ] **Step 2:** Implement. Run `bluey`'s architecture test: `publicExports` keeps its one entry and gains none, since R7 moved the only such export.
- [ ] **Step 3:** Guards' tests, the architecture tests of all five packages; commit `feat(guards): refuse a public export from inside a context`.

---

## Amendments to Tasks 17 to 26 of the slice plan

Each task is built as the slice plan writes it, with these changes. Names from R1 to R10 replace the slice plan's wherever it still says `ConnectionState` below the edge, `EventPublisher` in Connection's application, `clock.now()`, a `String operation`, or `api/failure_translation.dart`.

### Task 17 (composition)

- `platformConnectionPorts` and `ConnectionAssembly` take `Now now` and `EventPublisher publisher`; the assembly builds `PublishedLinkEvents(publisher)` and hands the registry and sessions `LinkEvents` and `now`. `inMemoryConnectionPorts` takes a `LinkEvents` (default `RecordingLinkEvents`) and a `Now`.
- The assembly, not `lib/src/bluey.dart`, constructs `LinkRegistry`, `ConnectDevice`, `BorrowLink`, `Connections` and `borrowingThrough`; `bluey.dart` shrinks by those lines and its size entry is lowered to the new count.
- `_connectionIdOf`'s fallback to the device address: first test whether any test or fake relies on it. If none does, the fallback becomes a `StateError` naming the missing id; if one does, keep it and document why on the function.
- Parked 22, 23, 24, test first: a failing give-back after a failed operation logs the original failure before the give-back's; a failed `connect` puts one `ErrorEvent` on `bluey.events`; `tryUpgrade`'s doc says what it borrows.

### Task 18 (value objects)

- Ruling 51: the value objects move to `features/connection/domain/value_objects/` and are exported to apps only through `api/connection/connection.dart`; `lib/bluey.dart` drops its direct exports of them. The API dump may change only by the `Mtu` range check's doc and what the slice plan lists.

### Task 19 (Platform's capabilities)

- `Capabilities` and `PlatformKind` reach apps through a new `api/platform/platform.dart` that re-exports them; `lib/bluey.dart` exports that file. The `publicExports` list loses its one entry here if the platform interface's export is no longer needed, as the slice plan intends.
- No file under `api/connection/` or `features/connection/` imports `features/platform/` (the R4 rule and the boundary rule both hold it).

### Task 20 (link features)

- The translator is at `api/connection/connection_failure_translation.dart`. `FeatureUnsupported(LinkOperation operation)` and `MtuAboveMaximum` each get their code in `failureCodeOf`. The platform's name reaches the translator as the assembly's `platformName` string (ruling 52), not through `Capabilities`.
- `linkFeaturesFrom` stays exactly where the slice plan puts it: Connection's infrastructure, reading the platform interface's capabilities and never Platform's. Connection and Platform each map the platform interface for themselves, so neither context names the other and no bridge is needed.

### Task 21 (MTU, payload limit, RSSI)

- Durations are measured with `Now`. `loggedLinkOperation` takes a `LinkOperation` and logs `operationWordOf(operation)` and `failureCodeOf(failure)`. `checkLinkFeature` answers `FeatureUnsupported(operation)`.
- Ruling 31: pull request 1 already logs a failed first read in `LinkGattClient`. `MtuSession` takes that logging over, with the same line; Task 25 deletes the legacy copy. A test asserts the line is logged once, not twice, while both exist.

### Tasks 22 to 24 (bonding, PHY, connection parameters)

- Each adds its `LinkOperation` values, in the domain's words, with their frozen log words, in its own first commit. Each session takes `Now` and `Log`; each `changes` stream carries no errors (ruling 4 of the ledger) and a failed first read is logged once under ruling 31, as in Task 21.

### Task 25 (the edge takes over)

- Ruling 52: `ConnectionAssembly` takes `ConnectionExtension extension` and builds `AndroidConnection`, `IosConnection` or neither. Ruling 53: `LinkGattClient` takes `BlueyException Function(LinkEnd) endAsException` and stops importing `lib/src/api/`; the four `lib/src/connection/bluey_connection.dart` entries leave `edgeFromBelow`, and the file's size entry is lowered.
- Parked 25 and 31 as the ledger states them, test first.
- `link_facts_through_the_api_test.dart` also asserts `connection.state` through each phase, so the phase mapping is proved from the public side.

### Task 26 (docs, gates, pull request)

- Design addendum "Rulings of 2026-11-26" in `docs/superpowers/specs/2026-11-18-link-lifecycle-design.md`: the five rulings and rulings 42 to 54, and section 6.13's table with rows for the GATT client and the assembly. `docs/ARCHITECTURE.md`: published language (events, phases and failures translated; values shared), the two new rules, the clock, and that an aggregate raises its events. `CLAUDE.md`: Key Design Decisions and the logging section where names changed, and the glossary gains Connection's inner words: Link, phase, end, operation, borrow.
- `connectAsPeer`'s borrow rule is noted in the root for slice 5, not moved.
- `bluey/CHANGELOG.md`: one line, the three events accept an optional `timestamp`.
- The three known compromises of the design review each get a `docs/backlog/` entry and a row in `docs/roadmap.md` (the `roadmap` skill's conventions), with the slice proposed to end it: the opening phase of `Link` (a follow-up pull request straight after this one, before slice 2), the frozen log words (one pass over every context's logs after the last context has moved), and values published from the domain (decided as a standing rule or changed in Task 18, as Joel rules).
- The pull request description lists: what changed for apps (that one line), ruling 37 still open, the native gates Joel runs on his Mac, and that `--first-statement=edgeFromBelow` is removed in the next change.

---

## Design review (cohesion, coupling, DDD, Clean Architecture)

**Each unit's single responsibility.**
- `LinkPhase`: where one link is in its life. `Link`: the aggregate; it decides each transition, the duty it leaves and the event it raises. `LinkEvent`: what happened to a link and when. `LinkOperation`: what can be attempted on a link. None formats, logs, holds a string for a log, or names a public type.
- `LiveLinks`: who holds which device's link and what an arrival does. `LiveLink`: the one thing the table reads of a link (whether it is closing), named in the domain so the table takes no predicate and no application type.
- `LinkSession`: runs one link's inputs through `Link`, performs duties, reports phases, forwards the events the link raised. `LinkRegistry`: opens links and admits users. `LinkEvents`: the one way events leave the application.
- `connection_log_words.dart`: every word of Connection's log lines that an app can read and this slice freezes: the context, the state words, the operation words, the failure codes. One reason to change (log wording is revised) and one deletion ends it. It is why the domain can use its own words while the logs keep theirs.
- `connectionStateOf`, `PublishedLinkEvents`, `connection_failure_translation.dart`: three translators, one per kind of thing published (phase, event, failure), each a pure mapping.
- `EdgeContextRule`, `EdgeFromBelowRule`: one question each about one direction of import.

**Each dependency and its direction.**
- `features/connection/domain` imports `shared/domain` only. After R5 and R7 it imports nothing public: `ConnectionState` and the public events are gone from it.
- `features/connection/application` imports its domain, its ports, `shared/application` (`Log`, `Now`). It no longer imports `EventPublisher` or `package:clock`. `LinkSession` implements the domain's `LiveLink`: application depending on domain, the allowed direction.
- `features/connection/infrastructure` implements the ports over the platform interface.
- `api/connection/` imports `features/connection/**` and `shared/**`, and implements `LinkEvents`: the port is declared inward, implemented outward. It imports no other context's `features/`.
- The composition root alone names Platform and Connection together, in one place: `PlatformKind` to `ConnectionExtension`. `LinkFeatures` is mapped in Connection's infrastructure from the platform interface, so it names no other context.
- `bluey_guards` rules depend on `SourceTree`, `Placement` and `Dependency`, as every rule does.
- Still pointing the wrong way, listed and shrinking: ten imports of the edge from unplaced code (four leave in Task 25).

**Bounded context and language.**
- Everything here is the Connection context, plus two guard rules and one shared typedef. Inside it the words are link, phase (linked, ready, closing, ended), end, duty, operation, borrower. At the edge the words are Connection, `ConnectionState`, connecting/connected/disconnected events, exceptions. The glossary in `CLAUDE.md` defines Connection but none of its inner words; Task 26 adds Link, phase, end, operation and borrow. The domain's operations are named for what Connection does (`negotiateMtu`, `readSignalStrength`), and the platform interface's method names appear only in infrastructure and in the frozen log words.
- `Client`, `Server`, `Peer` are untouched. Platform's `Capabilities` stays Platform's; Connection sees only `LinkFeatures`, its own word.

**The layer each file lands in.** The File Structure table gives it per file: four domain files, two application files (one a port), one shared application typedef, five edge files, two guard rules.

**Claims about existing classes, checked against source at `9715b72`.**
- `Link` holds a public `ConnectionState state` and the private `_upState`, `_closeAsked`, `_radioClosing` (`domain/link.dart`), so ruling 5 is a rewrite of its fields, not of its table.
- `LinkSession` exposes `Stream<ConnectionState> get states`, emits `DisconnectedEvent` through `EventPublisher` with `_reasonOf`, logs `'state': '${_link.state}'`, and uses `_link.end!` and `_closeInFlight!` (`application/link_session.dart`).
- `LinkRegistry` takes `EventPublisher events`, calls `clock.now()`, has public `acquire`, `giveBack(session)`, `keep(session)`, and logs `failure.runtimeType` (`application/link_registry.dart`).
- `LiveLinks.admit(device, user, {required Link? link})` and `enum Admission { open, wait, reuse }` (`domain/live_links.dart`).
- `connectionFailureFrom(error, {required String operation})` and `answering<T>(String operation, call)` (`infrastructure/adapters/platform_failures.dart`); `PlatformLinks._reports` is never pruned.
- `ConnectingEvent`, `ConnectedEvent`, `DisconnectedEvent` take `super.source` and no timestamp; `BlueyEvent` defaults its timestamp to `DateTime.now()` (`shared/domain/bluey_event.dart`).
- `lib/bluey.dart` exports `src/features/connection/domain/connection_event.dart`, the only export under `features/`; it exports `shared/` files directly, which stays allowed.
- `PublicExportsRule` accepts any export under `lib/src/`; `InApi` has no field; `ListGrowth.between` counts a list the base lacks as empty (`bluey_guards`).
- The ten imports of `lib/src/api/` from unplaced files are the ten listed in R4, found by search; `lib/src/bluey.dart` is a composition root and is not among them.
- `DisconnectEcho` clears its mark only on `disconnected` (`bluey_android/lib/src/disconnect_echo.dart`).

**Known compromises, each with its end.**
- `LinkOpenBegan` is raised by the registry, not by an aggregate, because a `Link` exists only once the radio has answered. Giving `Link` an opening phase would end it; that changes when a session exists and is not in this slice.
- `connection_log_words.dart` keeps public-sounding words (`ConnectionState.linked`) in the application layer. It is a frozen vocabulary, not a dependency: no import of the edge. It ends with the slice that revises log wording.
- Values an app builds are published from the domain (ruling 51) and not translated.

**Findings fixed in this document before the verdict.**
- A first draft kept `releaseAndAnnounce`; announcing is not the domain's duty once `entered` exists, so the duty is `release`.
- A first draft had the translator read the clock; ruling 3 says the raising unit stamps the time, so `LinkEvent.at` is set in the application and the translator only passes it on.
- A first draft handed `ConnectionAssembly` Platform's `Capabilities`; that is an edge file naming another context's domain, so ruling 52 replaced it.
- A first draft renamed the `address`/`deviceId` log keys for consistency; that changes what an app reads, so ruling 46 freezes them.
- Review of 2026-11-26 (Joel asked for a check against DDD and cohesion), six findings, all fixed above:
  1. The application constructed every event. An aggregate raises its own: `Link` now returns `LinkOpened` and `LinkEnded` in its step.
  2. `LinkOperation` carried the platform interface's method names (`getMaximumWriteLength`) and a log `word`, and failures carried a log `code`, all in the domain. The domain now uses its own words and holds no wording; the frozen strings are one application file.
  3. `LiveLinks<S>` took an opaque `S` and a predicate, which emptied the table of domain language. It now holds a `LiveLink`, a domain interface.
  4. The amendment to Task 20 moved `linkFeaturesFrom` to the composition root and had it read Platform's capabilities, against the slice plan and against the rule that contexts meet only through a bridge. It stays in Connection's infrastructure over the platform interface.
  5. One task changed the clock, the events and a guard rule. They are three tasks now (R6, R7, R10), each with one reason to be rejected.
  6. Event and phase names: `LinkOpening` and `LinkEndReached` were not past-tense facts and `requestOverRadio` hid a pair. They are `LinkOpenBegan`, `LinkEnded` and `ClosingBy.both`.

Verdict: ready.

## Self-Review

- **Coverage of the rulings and carry-overs.** Ruling 1: R3. Ruling 3: R7. Ruling 4: R4. Ruling 5: R5. Guard with a shrink-only list: R4. Ruling 41: R1. Ruling 31: Tasks 21 to 24. Parked 9: R9; 22, 23, 24: Task 17; 25, 31: Task 25; 28, 32: R1; 29: R2; 3, 4, 14: R5. Ruling 37: left open, named in Task 26. Review minors on `connection.dart`, the `LinkGattClient` file note, `LiveLinks`, stringly operations, `runtimeType` in logs, the clock: R3, R8, R9, R6. The export guard of ruling 51: R10.
- **Type consistency.** `LinkEvents`, `LinkOpenBegan`, `LinkOpened`, `LinkEnded`, `LiveLink`, `Now`, `LinkPhase`, `LinkOperation`, `ConnectionExtension`, `PublishedLinkEvents`, `connectionStateOf`, `stateWordOf`, `operationWordOf`, `failureCodeOf`, `connectionLogContext` are spelled the same wherever they appear.
- **Review Focus.** Each of the five lines names its task and its test.
- **Proportion.** Tasks R1 to R10 give signatures, test names and assertions; bodies are the implementer's.

## Execution Handoff

Subagent-driven, as pull request 1 was and as Joel chose for this slice: Opus for every implementer and reviewer, one task at a time in the order R1 to R10, then 17 to 26, with the ledger updated after each. A design question that comes up during the build goes to the coordinator for its own thread; the build does not answer it.
