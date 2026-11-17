---
id: I351
title: Set up continuous integration so all six test gates run automatically
category: unimplemented
severity: medium
platform: both
status: fixed
last_verified: 2026-11-17
fixed_in: 0c62903
---

## What this is

The repository has no CI of any kind — no workflow config, no hosted
runners. Every test gate is run by hand: four Dart suites
(`flutter test` per package), the Android native suite (Gradle/JVM),
and the iOS native suite (XCTest on a simulator, which needs a macOS
runner). The 2026-07-10 audit work grew the native suites considerably
(Kotlin 114 tests, XCTest 83 including delegate-sequence tests), which
raises the cost of forgetting to run them.

## Why it matters

A gate that only runs when someone remembers is a gate that will
eventually be skipped — most likely on exactly the change that breaks
it. The Swift and Kotlin suites are the ones guarding the layers where
bugs have historically escaped to hardware; they are also the ones
least likely to be run by habit during Dart-focused work.

## Rough approach

Decisions for the owner before implementation: which platform (GitHub
Actions is the default assumption if the repo lands on GitHub), what
runner budget (the XCTest job needs macOS, which is billed at a
premium), and which gates block merges versus run on a schedule. A
reasonable starting shape: Dart suites + analyze on every push (cheap,
Linux), Gradle on every push (Linux, needs a pinned Flutter SDK for
`FLUTTER_ROOT`), XCTest on pull requests or nightly (macOS runner,
simulator boot). The exact commands for every gate are already
documented in CLAUDE.md.

## Related

- [Testing conventions](../testing-conventions.md) — "Which gate to run".
- Audit context: [2026-07-10 networking-scenario test audit](../reviews/2026-07-10-networking-scenario-test-audit.md) (R5 asked for XCTest "in the routine gate"; this item is what makes any gate routine).

## Audit 2026-11-17

Fixed by `0c62903` (Run every gate on every pull request with GitHub Actions). The [2026-11-17 audit](../reviews/2026-11-17-correctness-and-test-rig-audit.md) (L12) found that a fresh checkout did not resolve on current Flutter stable, because no SDK version was pinned and no lockfile was committed; `fa63907` (Pin Flutter 3.47.2 and commit the workspace lockfile) closed that. Both landed in the architecture foundation slice ([design](../superpowers/specs/2026-11-17-architecture-foundation-design.md)).
