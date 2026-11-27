# A Link's Opening Phase Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `Link` raises every link event from an `Opening` phase of its own, a borrower's failed connect logs at debug, and the stale `--first-statement` flag is gone.

**Architecture:** The domain grows first and additively (Task 1), then the session learns to begin a link (Task 2), then the table and the registry swap over and the old way in is deleted (Task 3). The log level (Task 4) and the documents and gate flag (Task 5) follow. Every task ends with the whole `bluey` suite green.

**Tech Stack:** Dart, Flutter test, `fake_async`; the repository's guards (`bluey_guards`).

**Spec:** `docs/superpowers/specs/2026-11-27-link-opening-phase-design.md`. Read it with this plan; where the spec says *(Claude's call)*, Joel approved it on 2026-11-27.

## Global Constraints

- TDD: a failing test first, for every change in `lib/`. No production code without one.
- No public API change: `cd bluey && dart run bluey_guards:public_api lib/bluey.dart api/bluey.api` must pass without `--write`.
- No log line an app reads changes or appears, except the level of a borrower's `connect failed` (Task 4). Messages, contexts, data keys and `errorCode`s are frozen (I399).
- The events an app sees, and their order, do not change.
- Comments say why, never how; no inline comments unless a line is genuinely special. Tests use `// arrange`, `// act`, `// assert` and doubles from `test/fixtures/`, never mocks.
- Domain files import only `shared/domain` and each other. `link_registry.dart` must end up importing no `domain/link_event.dart`.
- Coverage floors: 90% package, 95% domain. No list in `test/architecture/known_violations.dart` grows.
- Format: the `dart format` command in `CLAUDE.md` must exit 0.
- Commits: Conventional Commits (`refactor(connection): …`), ending with the session's attribution lines.
- All paths below are relative to `bluey/` unless they start with `docs/`, `.github/` or `CLAUDE.md`. Connection's code is `lib/src/features/connection/` (`domain/`, `application/`), its tests `test/features/connection/`.

## Review Focus

1. **`disconnect()` on a session whose link is still opening.** No caller can hold one, but the method is public. Expected: it starts no close, and answers success once the open fails. Test in Task 2.
2. **A platform that answers the open after a radio outage began.** Expected: as today, the outage is not heard while opening; the open's answer alone settles the attempt, and a link that then opens hears the next outage. Test in Task 1 (domain row) and Task 2 (session subscribes to outages only from `opened`).
3. **A second caller arriving while the first open is in flight, whose open then fails.** Expected: the waiter makes its own attempt, and the failed session is no longer the device's. Existing registry test `a waiter makes its own attempt when the attempt it waited on fails` must pass unchanged in Task 3; a table test in Task 3 pins the identity match.
4. **`session.id` read before the link opened.** Expected: a `StateError` that names the device, never a null. Test in Task 2.
5. **A late `OpenSucceeded` on a link that never opened or has ended.** Expected: nothing changes and nothing is raised. Test in Task 1.

---

### Task 1: The domain's opening phase

**Files:**
- Modify: `domain/link_phase.dart`, `domain/link_input.dart`, `domain/link.dart`, `domain/link_event.dart` (doc of `LinkOpenBegan` only)
- Modify (forced by exhaustive switches and the nullable id): `application/connection_log_words.dart`, `lib/src/api/connection/connection_state_translation.dart`, `application/link_session.dart`, and the readers of `session.link.id` (`application/bonding_session.dart`, `phy_session.dart`, `parameter_session.dart`, `mtu_session.dart`, `read_rssi.dart`, `read_write_payload_limit.dart`, `lib/src/api/connection/connections.dart`, `lib/src/connection/bluey_connection.dart`)
- Test: `domain/link_test.dart`, `domain/link_phase_test.dart`, `application/connection_log_words_test.dart`, `test/api/connection/connection_state_translation_test.dart`, `application/link_session_test.dart`

**Interfaces:**
- Produces:
  - `final class Opening extends LinkPhase` and `final class NeverOpened extends LinkPhase`, both `const`, equal by type. Neither is an `UpPhase`.
  - `final class OpenSucceeded extends LinkInput { const OpenSucceeded(this.id); final LinkId id; }` and `final class OpenFailed extends LinkInput { const OpenFailed(); }`.
  - `final class FollowTheLink extends LinkDuty { const FollowTheLink(this.id); final LinkId id; }` and `final class ForgetTheLink extends LinkDuty { const ForgetTheLink(); }`, equal by value. `CloseTheLink` becomes `const CloseTheLink(this.id)` with `final LinkId id`, equal by id.
  - `static LinkStep Link.begin({required DeviceAddress device, required DateTime at})`.
  - `Link.id` is `LinkId?`. `Link.hasEnded` stays `phase is Ended`. New `bool get neverOpened => phase is NeverOpened`.
  - `LinkId get id` on `LinkSession`: `link.id`, or `StateError('The link to <device> has not opened.')`.
- `Link.open(id, device, at)` **stays in this task** so the registry still compiles. Reimplement it as `begin` followed by `OpenSucceeded(id)`, answering a step with `entered: Linked`, `events: [LinkOpened]` and no duty, exactly what it answers today. Task 3 deletes it.

- [ ] **Step 1: Write the failing domain tests** in `link_test.dart`. Add a `beginning` group and an `opening` table. Use a helper `Link opening() => Link.begin(device: device, at: opened).link`.

```dart
test('a link begins opening, with no id, and raises that its open began', () {
  final step = Link.begin(device: device, at: at);
  expect(step.link.phase, const Opening());
  expect((step.link.id, step.link.device), (null, device));
  expect(step.entered, const Opening());
  expect(step.duty, isNull);
  expect(step.events, [LinkOpenBegan(device: device, at: at)]);
});

test('an open that succeeds links it under the id and raises that it opened', () {
  final step = opening().on(const OpenSucceeded(id), at: at);
  expect(step.link.phase, const Linked());
  expect(step.link.id, id);
  expect(step.entered, const Linked());
  expect(step.duty, const FollowTheLink(id));
  expect(step.events, [LinkOpened(device: device, at: at)]);
});

test('an open that fails leaves a link that never opened and raises nothing', () {
  final step = opening().on(const OpenFailed(), at: at);
  expect(step.link.phase, const NeverOpened());
  expect((step.link.id, step.link.end, step.link.endInSight), (null, null, null));
  expect((step.link.isUp, step.link.hasEnded, step.link.neverOpened), (false, false, true));
  expect(step.entered, const NeverOpened());
  expect(step.duty, const ForgetTheLink());
  expect(step.events, isEmpty);
});
```

Then three loops, each asserting `step.link.phase` unchanged, `step.duty` null, `step.entered` null and `step.events` empty:
  - an opening link, for each of `ServicesDiscovered()`, every `RadioReported(report)`, `ReportsEnded()`, `DisconnectRequested()`, `CloseConfirmed()`, `CloseFailed()`, `RadioOutageBegan(RadioOutage.off)`;
  - a link that never opened, for every input above plus `OpenSucceeded(id)` and `OpenFailed()`;
  - each of linked, ready, closing (by request) and ended (dropped), for `OpenSucceeded(LinkId('L2'))` and `OpenFailed()`, also asserting `step.link.id` is still `id`.

Update the existing close rows to expect `CloseTheLink(id)`, and the `isUp/isClosing/hasEnded` table to include an opening link `(false, false, false)`. Keep the existing `Link.open` test passing unchanged.

- [ ] **Step 2: Write the failing tests for the forced arms.**
  - `link_phase_test.dart`: `Opening` and `NeverOpened` are equal by type and differ from each other and from `Linked`.
  - `connection_log_words_test.dart`: `stateWordOf(const Opening())` is `'ConnectionState.connecting'`; `stateWordOf(const NeverOpened())` is `'ConnectionState.disconnected'`.
  - `connection_state_translation_test.dart`: `Opening` maps to `ConnectionState.connecting`, `NeverOpened` to `ConnectionState.disconnected`.
  - `link_session_test.dart`: `session.id` equals the id `links.open` answered.

- [ ] **Step 3: Run them.** `cd bluey && flutter test test/features/connection test/api/connection`. Expected: compile failures naming `Opening`, `Link.begin`, `OpenSucceeded`.

- [ ] **Step 4: Implement the domain.** Add the phases, inputs and duties. In `Link.on`, put the new arms before the existing ones in this order: `(Ended() || NeverOpened(), _)` stays put; `(Opening(), OpenSucceeded(:final id))`; `(Opening(), OpenFailed())`; `(Opening(), _)` stays put; `(_, OpenSucceeded() || OpenFailed())` stays put. `_in` gains an optional id so `OpenSucceeded` can set it. `endInSight` answers null for `Opening` and `NeverOpened`. Where a close duty is answered the link's id is non-null by construction (only an `UpPhase` or `Closing` link answers one); read it through one private getter whose doc says why, with a `StateError` behind it rather than `!`. Reword `LinkOpenBegan`'s doc: the link raises it as it begins. Update `Link`'s class doc and `LinkStep.events`' doc (three events now).

- [ ] **Step 5: Implement the forced arms and `LinkSession.id`.** Add the two arms to `stateWordOf` and `connectionStateOf`. Add `LinkSession.id`; the session's own `_links.close(...)` takes the id from the `CloseTheLink` duty, and `reportsOf` from `id`. Move every reader in the Files list from `session.link.id` to `session.id` (`bluey_connection.dart:130` becomes `_session.id.value`). `_carryOut` gains `case FollowTheLink() || ForgetTheLink(): break;` for now; Task 2 gives them bodies.

- [ ] **Step 6: Run the suite and the gates.** `cd bluey && flutter test` (all pass), `flutter analyze` (clean), the format command, and `dart run bluey_guards:public_api lib/bluey.dart api/bluey.api` (matches).

- [ ] **Step 7: Commit.** `refactor(connection): give a link an opening phase in the domain`

---

### Task 2: A session that begins its link

**Files:**
- Modify: `application/link_session.dart`
- Test: `application/link_session_test.dart`

**Interfaces:**
- Consumes: Task 1's `Link.begin`, `OpenSucceeded`, `OpenFailed`, `FollowTheLink`, `ForgetTheLink`.
- Produces:
  - `LinkSession.begin({required DeviceAddress device, required Links links, required LinkEvents events, required Log log, required Now now})`: builds the link with `Link.begin(device: device, at: now())`, raises that step's events through `events`, subscribes to nothing.
  - `void opened(LinkId id)`: feeds `OpenSucceeded(id)`.
  - `void notOpened()`: feeds `OpenFailed()`.
  - The existing unnamed constructor stays until Task 3.

**Decisions the tests pin:**
- On `FollowTheLink(id)` the session starts the two subscriptions the unnamed constructor starts (`links.reportsOf(id)` and `links.outages`). Make the two subscription fields nullable and cancel them null-safely in `_release`.
- On `ForgetTheLink` the session closes its phase stream and completes its teardown, so a `disconnect()` waiting on it answers success. Registered `onEnd` releases are **not** run: there is no `LinkEnd` to hand them. Say so in `onEnd`'s doc.
- The open's steps add their phase to `phases` (`Opening` is never seen, since nobody can listen before `begin` returns; `Linked` and `NeverOpened` are) but log **no** `state transition` line. Do this by keeping the log line out of the path `opened` and `notOpened` take, not by a flag on `_step`: split `_announce` into the telling (`_phases.add`) and the logging, and have `_step` take which.
- `isClosing` keeps its meaning (`!_link.isUp`), so an opening session already answers true.

- [ ] **Step 1: Write the failing tests** in a new `beginning` group, building with `LinkSession.begin(device: device, links: links, events: events, log: log, now: () => now)`:

```dart
test('a session begins by raising that the open began, and listens to nothing', () {
  final began = LinkSession.begin(/* … */);
  expect(events.raised, [LinkOpenBegan(device: device, at: now)]);
  expect(began.phase, const Opening());
  expect(began.isClosing, isTrue);
  expect(log.records, isEmpty);
  expect(links.outages /* has no listener */, …);
});
```
  For "listens to nothing", give `InMemoryLinks` (in `test/fixtures/features/connection/application/ports/in_memory_links.dart`) a read-only `bool get outagesHeard` (its outage controller's `hasListener`) and assert it false after `begin` and true after `opened`.
  - `reading the id before the link opened is a StateError naming the device`: `expect(() => began.id, throwsA(isA<StateError>().having((e) => e.message, 'message', contains(device.value))))`.
  - `opened links the session, raises that it opened and logs no state transition`: after `began.opened(id)`: `began.phase` is `Linked()`, `began.id` is `id`, `events.raised.last` is `LinkOpened(device: device, at: now)`, `log.records` is empty, and a `phases` listener attached before `opened` saw `[Linked()]`.
  - `an opened session hears its reports and the next outage`: after `opened`, a disconnected report ends it by drop; in a second test `links.outage(RadioOutage.off)` ends it by outage.
  - `an outage while opening is not heard`: fire the outage before `opened`; after `opened` the phase is `Linked()`.
  - `notOpened raises nothing more, logs nothing and ends the phases`: `events.raised` is still the one `LinkOpenBegan`, `log.records` is empty, the `phases` stream emitted `[NeverOpened()]` and is done.
  - `a disconnect on an opening session starts no close and answers once the open fails`: call `began.disconnect()`, then `began.notOpened()`; the future answers `success`; `links.closesAsked(device)` is 0. The frozen `disconnect entered` line is logged as for any disconnect; do not assert on the log here.

- [ ] **Step 2: Run them.** `cd bluey && flutter test test/features/connection/application/link_session_test.dart`. Expected: FAIL, `LinkSession.begin` is not defined.

- [ ] **Step 3: Implement** `begin`, `opened`, `notOpened` and the two duties as decided above. The unnamed constructor may now delegate its subscriptions to the same private method `FollowTheLink` runs.

- [ ] **Step 4: Run the whole suite**, `flutter analyze` and the format command. All pass.

- [ ] **Step 5: Commit.** `refactor(connection): let a session begin its link's open`

---

### Task 3: The table and the registry hold a link from its beginning

**Files:**
- Modify: `domain/live_link.dart`, `domain/live_links.dart`, `application/link_registry.dart`, `application/link_session.dart` (delete the unnamed constructor; `isClosing` becomes `isUp`), `domain/link.dart` (delete `Link.open`)
- Modify fixtures: `test/fixtures/features/connection/application/up_session.dart`
- Test: `domain/live_links_test.dart`, `application/link_registry_test.dart`, `application/link_session_test.dart`, `domain/link_test.dart`, `application/check_before_asking_test.dart`

**Interfaces:**
- Consumes: `LinkSession.begin`, `opened`, `notOpened`.
- Produces:
  - `abstract interface class LiveLink { bool get isUp; }`: whether the link can be used now; false while it opens, closes, or has ended and is not yet let go of. `LinkSession.isUp => _link.isUp` replaces `isClosing`.
  - `LiveLinks<L>`:
    - `Admission<L> admit(DeviceAddress device, LinkUser user)`: no entry answers `Open` and records nothing; an entry whose link is not up answers `Wait`; otherwise records the user and answers `Reuse`.
    - `void began(DeviceAddress device, L link)`: the device's entry now holds `link`, used by nobody. A device that already has an entry is a `StateError('<device> already has a link.')`.
    - `void opened(DeviceAddress device, LinkUser user)`: records `user` on the device's entry.
    - `void notOpened(DeviceAddress device, L link)`: drops the entry when `link` is the one it holds, matched by identity.
    - `givenBack`, `kept`, `ended` unchanged. `_Entry.link` is non-null.

**The registry's `_open`, in order** (this order is what apps observe; keep it):
1. `LinkSession.begin(...)` (raises `LinkOpenBegan`), 2. `_table.began(device, session)`, 3. listen to `session.phases` to announce changes, 4. log `connect started`, 5. `await _links.open(...)`.
- On failure: `session.notOpened()`, `_table.notOpened(device, session)`, log `connect failed`, announce the change, answer the failure.
- On success: `_table.opened(device, by)`, `session.onEnd(...)`, `session.opened(id)` (raises `LinkOpened`), log `connect succeeded`, announce the change, answer the session.

`_sessionOf` goes. The registry no longer imports `domain/link.dart`, `domain/link_event.dart` or `domain/link_id.dart`.

- [ ] **Step 1: Rewrite the table's tests.** In `live_links_test.dart`, the fake link gets a settable `isUp`. Replace uses of the old `opened(device, user, link)` with `began(device, link)` then `opened(device, user)`. Add:
  - `a link that is opening makes the next caller wait`: `admit` → `Open`; `began(device, link..isUp = false)`; second `admit` → `Wait`.
  - `beginning a second link for a device is a StateError`.
  - `a failed open drops only the link that failed`: `began(device, first)`, `notOpened(device, second)` changes nothing (next `admit` is `Wait`), `notOpened(device, first)` makes the next `admit` answer `Open`.
  - Every existing closing/ended row keeps its expectation with `isUp = false` where it had `isClosing = true`.

- [ ] **Step 2: Extend the registry's tests.** In `link_registry_test.dart`:
  - `an open raises its events and logs its lines in the order apps have always seen`: for a successful `hold`, `events.raised` is `[LinkOpenBegan(device: device, at: at), LinkOpened(device: device, at: at)]` and the log's messages are exactly `['connect started', 'connect succeeded']` (no `state transition`).
  - The existing failed-open test keeps every assertion (`events.raised` is the one `LinkOpenBegan`; the `connect failed` record at error).
  - Every other existing test must pass unchanged, in particular the waiting group.

- [ ] **Step 3: Move the fixtures and remaining tests off `Link.open` and the unnamed constructor.** `upSession` becomes `LinkSession.begin(...)..opened(id)`. `link_session_test.dart`'s `openSession` likewise; its two `isClosing` tests assert `isUp` with the booleans inverted. `link_test.dart`'s `after` helper folds over `Link.begin(...)` then `OpenSucceeded(id)`; delete the `Link.open` test. Fix `check_before_asking_test.dart` the same way.

- [ ] **Step 4: Run.** `cd bluey && flutter test test/features/connection`. Expected: compile failures naming `began` and `isUp`.

- [ ] **Step 5: Implement** the table, the registry and the deletions. Update the docs of `LiveLinks`, `_Entry` ("A device's link and who uses it"), `LinkRegistry` and `Link` ("`begin` is the only way to build a link").

- [ ] **Step 6: Verify.** `cd bluey && flutter test` (all pass); `grep -n "link_event\|Link\.open" lib/src/features/connection/application/link_registry.dart lib -r` finds no `Link.open` anywhere and no `link_event` import in the registry; `flutter analyze`; the format command; the API dump check; `flutter test test/architecture`.

- [ ] **Step 7: Commit.** `refactor(connection): hold a link from the moment its open begins (I398)`

---

### Task 4: A borrower's failed connect logs at debug (ruling 37)

**Files:**
- Modify: `application/link_registry.dart`
- Test: `application/link_registry_test.dart`

**Interfaces:**
- Produces: nothing new outside the file. `_logFailure` takes the `LinkUser`; a private function maps `LinkUser.app` to `BlueyLogLevel.error` and `LinkUser.borrower` to `BlueyLogLevel.debug`, with a doc saying why (a borrower's failed connect is routine while peers are discovered).

- [ ] **Step 1: Write the failing test** `a borrower's failed open logs at debug, with the line an app's has`:

```dart
links.failNextOpen(device, ConnectFailureReason.deviceNotConnectable);
await registry.borrow(device);
final failed = log.records.last;
expect(failed.level, BlueyLogLevel.debug);
expect(failed.message, 'connect failed');
expect(failed.context, 'bluey.connection');
expect(failed.data, {'address': device.value, 'exception': 'ConnectFailed'});
expect(failed.errorCode, 'ConnectFailed');
```
  And assert in the same file that a borrower's `connect started` is still at `BlueyLogLevel.info`.

- [ ] **Step 2: Run it.** Expected: FAIL, level is `error`.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run the whole suite.** All pass (the app's failed-open test still asserts error).
- [ ] **Step 5: Commit.** `fix(connection): log a borrower's failed connect at debug`

---

### Task 5: The gate flag, the documents, and the final gates

**Files:**
- Modify: `.github/workflows/ci.yml` (around line 139), `CLAUDE.md`, `docs/ARCHITECTURE.md`, `docs/superpowers/specs/2026-11-18-link-lifecycle-design.md` (section 6.13's row), `docs/backlog/I398-give-a-link-its-opening-phase.md`, `docs/roadmap.md`, `bluey/CHANGELOG.md`

- [ ] **Step 1: Remove the flag.** In `ci.yml`, delete the `flags` variable, its comment and its `if` block, and drop `$flags` from the `list_growth.dart` call. In `CLAUDE.md`, the list-growth command loses the flag and its comment loses the sentence that begins "The flag lets".
- [ ] **Step 2: Run list growth without it.** `cd bluey && dart run test/architecture/list_growth.dart origin/main test/architecture/known_violations.dart test/known_defects/roster.dart`. Expected: no list grew.
- [ ] **Step 3: Update the documents.**
  - `CLAUDE.md`: the key decision "The domain raises its own events" says `Link` raises `LinkOpenBegan`, `LinkOpened` and `LinkEnded`, and drops the registry parenthesis; the glossary's **Phase** row reads "opening, linked, ready, closing, ended, or never opened"; the structured-logging section gains one sentence: a borrower's `connect failed` logs at debug, the app's at error.
  - `docs/ARCHITECTURE.md` line 121: `Link` answers all three in the step it takes; delete the clause about the application raising `LinkOpenBegan`.
  - Slice 1's design, section 6.13: mark the `LinkOpenBegan` row resolved by this change, naming this plan.
  - `docs/backlog/I398…`: `status: fixed`, `last_verified: 2026-11-27`, and a closing note. Use the repository's `roadmap` skill for the backlog and `docs/roadmap.md` (tick the item at line 193; reword the note at line 44).
  - `bluey/CHANGELOG.md`, under the unreleased heading: "A failed connect made for peer discovery logs `connect failed` at debug again; an app's own failed connect still logs at error."
- [ ] **Step 4: Run every gate.**
  - `cd bluey && flutter test --coverage`
  - `dart run bluey_guards:coverage_gate coverage/lcov.info 90 lib`
  - `dart run bluey_guards:coverage_gate coverage/lcov.info 95 lib 'lib/src/features/*/domain' lib/src/shared/domain`
  - `flutter test test/architecture`
  - `dart run bluey_guards:public_api lib/bluey.dart api/bluey.api`
  - `flutter test test/known_defects --run-skipped --tags known-defect` (the roster's defects still fail, nothing else)
  - `cd bluey/example && flutter test`
  - from the root: `flutter analyze` and the format command
  - `cd bluey_guards && dart test`
- [ ] **Step 5: Commit.** `docs(connection): record the opening phase and drop the first-statement flag`
- [ ] **Step 6: Open the pull request** against `main` with the attribution header the thread's instructions give, a "What an app sees" section (nothing but the log level), and the gate results.

---

## Design review (cohesion, coupling, DDD, Clean Architecture)

**Responsibilities.** Task 1 changes only what a `Link` decides. Task 2 changes only how a `LinkSession` carries out a link's duties. Task 3 changes what `LiveLinks` holds and how `LinkRegistry` carries out an admission; the registry loses the raising of an event and the building of a link. Task 4 is one mapping in the unit that logs the connect's lines.

**Dependencies.** No new direction. Domain: `link.dart` imports `link_phase`, `link_input`, `link_event`, `link_end`, `link_id`, as today. Application: the registry drops three domain imports and gains none. Edge: one switch gains two arms. Nothing crosses a context; every file is Connection's except the documents.

**Bounded context and language.** Connection. New words, all the domain's: opening, never opened, follow, forget. The table's question becomes "is it up", the word `Link` already has. `LinkUser` (existing, domain) is read by the application to choose a log level; the domain knows nothing of logs.

**Layers.** Phases, inputs, duties, `Link.begin`, `LiveLinks`: domain. `LinkSession`, `LinkRegistry`, the frozen log words: application. `connectionStateOf`: edge (`api/connection/`).

**Claims checked against source (main at 3364a04).** `LinkSession.isClosing` is `!_link.isUp`. The unnamed `LinkSession` constructor is the only place reports and outages are subscribed. `_announce` both logs `state transition` and adds to `_phases`, and runs only from `_step`. `LinkRegistry._sessionOf` records the user in the table before raising `LinkOpened`. `Link.open` has eight uses, one in `lib/` (the registry). `session.link.id` has thirteen readers in `lib/`. `ConnectionState.connecting` exists. `LiveLinks.notOpened` today removes an entry only when its link is null. The spec says "thirteen readers" and Task 1 lists them by file.

Verdict: ready.
