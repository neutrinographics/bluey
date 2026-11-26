---
id: I398
title: Give a link its opening phase, so the aggregate raises every link event
category: refactor
severity: low
platform: domain
status: open
last_verified: 2026-11-26
related: [I399]
---

## Symptom

None an app sees. Connection's aggregate, `Link`, raises two of a link's three events itself, `LinkOpened` and `LinkEnded`, but the first, `LinkOpenBegan` (published as `ConnectingEvent`), is raised by the application's `LinkRegistry`. A `Link` exists only once the radio has answered a connect, so there is nothing in the domain to raise it from. It is the one place where Connection's application decides an event the domain should decide.

## Location

- `bluey/lib/src/features/connection/application/link_registry.dart` (where it raises `LinkOpenBegan`)
- `bluey/lib/src/features/connection/domain/link.dart`, `link_phase.dart` (the phases start at `Linked`)

## Root cause

Slice 1 kept today's moment for creating a session: when the platform's connect succeeds. Giving `Link` an opening phase moves that moment to when the connect starts, which changes when a `LinkSession` exists and what `LiveLinks` holds for an attempt in flight. That is a change of shape, not a move, so it was left out of slice 1 (design `docs/superpowers/specs/2026-11-18-link-lifecycle-design.md`, sections 6.13 and 13).

## Notes

- Proposed timing: a small pull request straight after slice 1's second, before slice 2 begins. Joel has not confirmed it.
- Shape: `LinkPhase` gains an opening phase before `Linked`; the open's success and failure become inputs to `Link`; `LiveLinks`' entry for an attempt in flight holds that link. The public `ConnectionState` and the three public events do not change, and no log line an app reads may change (I399 owns that).
- Proof: the domain's table tests gain the opening rows, and the registry's tests show it raises nothing itself.
