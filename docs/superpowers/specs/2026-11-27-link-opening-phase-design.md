# A link's opening phase (I398), a quiet probe (ruling 37), and the stale gate flag

Date: 2026-11-27. Follows slice 1 (PR #45). Small change: one pull request, before slice 2.

## 1. Intent

Slice 1 left one place where Connection's application decides an event the domain should decide: `LinkRegistry` raises `LinkOpenBegan`, because a `Link` exists only once the radio has answered a connect (`docs/backlog/I398-give-a-link-its-opening-phase.md`; slice 1's design, section 6.13). Slice 2 builds on Connection, so the aggregate should own its whole life first.

Two smaller things ride along, both decided by Joel on 2026-11-27:

- **Ruling 37.** A borrower's failed connect logs at debug again. Failed connects are routine while peers are discovered, and since slice 1 each one logs at error.
- **The gate flag.** `--first-statement=edgeFromBelow` has done its job and is removed from `CLAUDE.md` and `.github/workflows/ci.yml`.

M7 of the final review (the example app asking with `Mtu.fromPlatform`) is already fixed on main, so nothing is carried.

## 2. Goals, non-goals, anti-goals

**Goals**

- `Link` raises all three link events. The registry raises none.
- A `Link`, its `LinkSession` and the `LiveLinks` entry exist from the moment an open begins.
- A borrower's failed connect logs at debug; the app's stays at error.

**Non-goals**

- Rewording any log line or data key (I399, one pass after slice 6).
- Any change to the public API: `ConnectionState`, the three public events and `bluey.api` stay as they are.
- Letting anyone cancel an open in flight. No caller holds a session before its link is up, today or after this change.

**Anti-goals**

- An app sees a new or missing event, a new `Connection` state, or a new or missing log line other than the level in ruling 37.
- A second table or flag beside `LiveLinks` that says an open is in flight.

## 3. Approaches

**A. `Link` gains an opening phase (chosen by Joel).** A `Link` is built when the open begins, in a new `Opening` phase, and raises `LinkOpenBegan` in that first step. The platform's answer returns to it as an input. The session and the table hold it from the start, so the table's empty placeholder for an attempt in flight goes away. Cost: a link has no id until the radio answers.

**B. A separate open-attempt object.** A small domain object raises `LinkOpenBegan` and builds the `Link` on success. Less change, but the link's life is then split across two objects and `Link` still does not own its beginning, which is what I398 is about.

**C. Leave the event in the registry and call it an application event.** Rejected in slice 1's review: the event is a fact about a link, and Joel asked for the compromise to be removed.

## 4. Design

Everything below is in the Connection context, under `bluey/lib/src/features/connection/`. Calls marked *(Claude's call)* were not Joel's and can be overruled.

### 4.1 Domain

**Phases** (`domain/link_phase.dart`). Two are added:

- `Opening`: the open was asked for and the radio has not answered. Not an `UpPhase`.
- `NeverOpened`: the open failed. Final, like `Ended`, but it carries no `LinkEnd`: a link that never opened did not end for any of the reasons a `LinkEnd` names, and giving it one would let "ended" reach code that only ever handles links that were up. *(Claude's call.)*

**Inputs** (`domain/link_input.dart`). `OpenSucceeded(LinkId id)` and `OpenFailed()`.

**Building a link** (`domain/link.dart`). `Link.open(id, device, at)` is replaced by `Link.begin(device, at)`, which answers a step that entered `Opening` and raised `LinkOpenBegan`. It is still the only way to build a link.

**The new rows of `Link.on`:**

| Phase | Input | Next | Raises | Duty |
|---|---|---|---|---|
| `Opening` | `OpenSucceeded(id)` | `Linked`, with the id | `LinkOpened` | `FollowTheLink(id)` |
| `Opening` | `OpenFailed` | `NeverOpened` | nothing | `ForgetTheLink` |
| `Opening` | anything else | `Opening` | nothing | none |
| `NeverOpened` | anything | `NeverOpened` | nothing | none |
| any other | `OpenSucceeded`, `OpenFailed` | unchanged | nothing | none |

"Anything else" in `Opening` includes a radio outage and a disconnect request. Neither can arrive today (nothing listens for the link and nobody holds its session until it is up), and ignoring them keeps today's behaviour: the open's own answer settles the attempt. Cancelling an open is a feature for another day.

A failed open raises nothing, so `ConnectingEvent` is still followed by silence when a connect fails, as today.

**Duties.** Two are added, so the session still only does what the link answers:

- `FollowTheLink(id)`: the link is up; start listening to its reports and to radio outages.
- `ForgetTheLink`: the open failed; nothing was acquired, so let go of the link.

`CloseTheLink` gains the id to close, `CloseTheLink(id)`, so the session never has to read an id that might not be there. *(Claude's call.)*

**The id.** `Link.id` becomes `LinkId?`: null while opening and for a link that never opened, set for good by `OpenSucceeded`. *(Claude's call; the alternative, an id invented before the radio answers, would be a second identity beside the platform's.)*

**The table** (`domain/live_links.dart`, `domain/live_link.dart`).

- An entry always holds a link; the null placeholder goes.
- `LiveLink.isClosing` becomes `isUp`, since the table's one question is whether a link can be reused, and it now has two reasons to answer no. `admit` answers `Wait` for a link that is not up.
- `admit` answering `Open` records nothing; the owner follows it at once with `began(device, link)`. `opened(device, user)` records the user; `notOpened(device, link)` drops the entry, matched by identity like `ended`.

### 4.2 Application

**`LinkSession`** (`application/link_session.dart`).

- Built by `LinkSession.begin(device, …)`, which takes `Link.begin`'s step and raises its event through `LinkEvents`. It subscribes to nothing yet.
- `opened(LinkId id)` and `notOpened()` feed `OpenSucceeded` and `OpenFailed`. On `FollowTheLink` it starts the two subscriptions its constructor starts today. On `ForgetTheLink` it closes its phase stream.
- `LinkSession.id` is added: the link's id, for whoever holds a session. A session is handed out only once its link is up, so it is always there; reading it earlier is a `StateError`. The thirteen readers of `session.link.id` move to it. *(Claude's call.)*
- **Frozen log lines.** The open's steps log no `state transition` line, since none is logged for them today. `stateWordOf` still gets a word for each new phase so its switch stays exhaustive; I399 decides whether the lines appear.

**`LinkRegistry`** (`application/link_registry.dart`).

- `_open` begins a session, stores it with `began`, logs `connect started`, asks the platform, and tells the session the answer. It names no `LinkEvent`.
- The order an app can observe is unchanged: `ConnectingEvent`, then `connect started`; on success the table records the user, then `ConnectedEvent`, then `connect succeeded`.
- **Ruling 37.** `connect failed` is logged at the level the link's user gives: error for the app, debug for a borrower. Context, message, data and `errorCode` do not change. `connect started` and `connect succeeded` stay at info for both.

### 4.3 Edge

`connectionStateOf` (`api/connection/connection_state_translation.dart`) maps `Opening` to `ConnectionState.connecting` and `NeverOpened` to `ConnectionState.disconnected`. No `Connection` is ever built over a session in either phase, so no app reads them; the mapping exists because the switch is exhaustive, and those are the true words. `PublishedLinkEvents` does not change.

### 4.4 Outside the code

- `.github/workflows/ci.yml:139` and `CLAUDE.md:78`: drop `--first-statement=edgeFromBelow` and the sentence that explains it.
- `CLAUDE.md` (the key decision on events, the `Phase` glossary row, the structured-logging note), `docs/ARCHITECTURE.md` (the published-language paragraph), slice 1's design section 6.13 (the row is resolved), `docs/roadmap.md`, `docs/backlog/I398…` (status fixed), `CHANGELOG.md` (the probe's log level).

## 5. Proof

- `link_test.dart`: the table gains every row of 4.1, including that each existing phase ignores the two new inputs and that `Opening` ignores an outage and a disconnect request.
- `live_links_test.dart`: a link that is opening makes the next caller wait; a failed open's give-up is matched by identity.
- `link_session_test.dart`: nothing is subscribed before `opened`; the open's steps log no `state transition`.
- `link_registry_test.dart`: the events and log lines of a successful and a failed open are exactly today's, in today's order; a borrower's failed open logs at debug and the app's at error; `link_registry.dart` no longer imports `link_event.dart`.
- The whole `bluey` suite, the architecture rules, list growth without the flag, the API dump (unchanged), and both coverage floors.

## 6. Left to the builder

Test names, fixture updates (`up_session.dart`, the in-memory `Links`), and the exact wording of doc comments.

## 7. Design review (cohesion, coupling, DDD, Clean Architecture)

**Responsibilities.** `Link` decides what each input does to a link, now from the open's beginning. `LinkSession` carries out the link's duties. `LinkRegistry` carries out `LiveLinks`' admissions and logs the connect's lines. `LiveLinks` decides who opens, waits and reuses. None gains a second job; the registry loses one (raising an event).

**Dependencies.** Unchanged in direction. Domain files import only `shared/domain` and each other. `LinkSession` and `LinkRegistry` import domain and the application's ports. The edge imports domain phases to translate them. No new import crosses a context.

**Bounded context and language.** All of it is Connection. New words: *opening* (a phase), *never opened* (a phase), *follow* and *forget* (duties). `LinkUser` already names who asks for a link, and the log level is read from it in the application, where logging lives.

**Layers.** `Opening`, `NeverOpened`, the two inputs and the two duties are domain. The log level and the frozen-line rule are application. The state mapping is edge.

**Claims checked against source.** `LinkSession.isClosing` is already defined as `!_link.isUp` (`link_session.dart`), so renaming the table's question changes no behaviour. `LinkSession`'s constructor is where reports and outages are subscribed today. `LinkRegistry._sessionOf` stores the session before raising `LinkOpened`, which 4.2 keeps. `ConnectionState.connecting` exists (`api/connection/connection_state.dart`). No session announces `Linked` at open today, since `_announce` runs only from `_step`, and the first link is built by `Link.open` outside it.

Verdict: ready.
